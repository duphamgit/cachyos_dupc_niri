//! KDE KWin compositor implementation using D-Bus scripting API.
//!
//! Uses KWin's JavaScript scripting interface via D-Bus to enumerate and
//! focus windows. This works for both native Wayland and XWayland windows.

use super::{Compositor, WindowInfo};
use anyhow::{Context, Result, anyhow};
use serde::Deserialize;
use std::fs;
use std::io::Write;
use std::time::Duration;
use zbus::blocking::{Connection, MessageIterator, Proxy};
use zbus::message::Type as MessageType;
use zbus::zvariant::ObjectPath;

/// JavaScript script to list all windows.
/// Outputs JSON array via print() which emits a D-Bus signal.
const LIST_WINDOWS_SCRIPT: &str = r#"(function() {
    var windows = workspace.windowList();
    var result = [];
    for (var i = 0; i < windows.length; i++) {
        var w = windows[i];
        if (w.dock || w.desktopWindow || w.notification || w.splash) continue;
        if (w.popupWindow || w.dialog) continue;
        if (w.resourceClass.toLowerCase() === 'zlaunch') continue;
        if (w.resourceClass === '') continue;
        var desk = 1;
        if (w.desktops && w.desktops.length > 0 && w.desktops[0]) {
            desk = w.desktops[0].x11DesktopNumber || 1;
        }
        result.push({
            id: w.internalId.toString(),
            title: w.caption || w.resourceClass,
            class: w.resourceClass,
            workspace: desk,
            focused: w.active
        });
    }
    print(JSON.stringify(result));
})();
"#;

/// JavaScript script template to focus a window by its internal ID.
const FOCUS_WINDOW_SCRIPT_TEMPLATE: &str = r#"(function() {
    var targetId = '%WINDOW_ID%';
    var windows = workspace.windowList();
    for (var i = 0; i < windows.length; i++) {
        if (windows[i].internalId.toString() === targetId) {
            workspace.activeWindow = windows[i];
            return;
        }
    }
})();
"#;

/// Window information from KWin script JSON output.
#[derive(Debug, Deserialize)]
struct KwinWindow {
    id: String,
    title: String,
    class: String,
    workspace: i32,
    focused: bool,
}

/// KWin compositor client using D-Bus scripting API.
pub struct KwinCompositor {
    connection: Connection,
}

impl KwinCompositor {
    /// Create a new KWin compositor client.
    ///
    /// Returns None if KDE session is not detected or KWin is not available.
    pub fn new() -> Option<Self> {
        // Check if we're in a KDE session
        if std::env::var("KDE_SESSION_VERSION").is_err() {
            return None;
        }

        // Connect to session D-Bus
        let connection = Connection::session().ok()?;

        // Verify KWin is available by calling supportInformation
        let kwin_proxy = Proxy::new(&connection, "org.kde.KWin", "/KWin", "org.kde.KWin").ok()?;

        let _: String = kwin_proxy.call("supportInformation", &()).ok()?;

        Some(Self { connection })
    }

    /// Execute a KWin script and capture its print output.
    fn run_script(&self, script_content: &str) -> Result<Option<String>> {
        // Write script to temp file
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
        let script_path = format!(
            "{}/zlaunch-kwin-script-{}.js",
            runtime_dir,
            std::process::id()
        );

        let mut file =
            fs::File::create(&script_path).context("Failed to create temp script file")?;
        file.write_all(script_content.as_bytes())
            .context("Failed to write script content")?;
        drop(file);

        // Run the script and capture result, then cleanup
        let result = self.run_script_impl(&script_path);

        // Always cleanup temp file
        let _ = fs::remove_file(&script_path);

        result
    }

    /// Internal script execution after file is written.
    fn run_script_impl(&self, script_path: &str) -> Result<Option<String>> {
        // Create proxy for the Scripting interface
        let scripting_proxy = Proxy::new(
            &self.connection,
            "org.kde.KWin",
            "/Scripting",
            "org.kde.kwin.Scripting",
        )
        .context("Failed to create Scripting proxy")?;

        // Load the script via D-Bus
        let script_id: i32 = scripting_proxy
            .call("loadScript", &(script_path, "zlaunch-temp"))
            .context("Failed to load KWin script")?;

        if script_id < 0 {
            return Err(anyhow!("KWin returned invalid script ID: {}", script_id));
        }

        let script_path_dbus = format!("/Scripting/Script{}", script_id);
        let script_object_path = ObjectPath::try_from(script_path_dbus.as_str())
            .context("Invalid script object path")?;

        // Set up a rule to match the print signal from this script
        let rule = format!(
            "type='signal',sender='org.kde.KWin',path='{}',interface='org.kde.kwin.Script',member='print'",
            script_path_dbus
        );

        // Create proxy for DBus to add match rule
        let dbus_proxy = Proxy::new(
            &self.connection,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
        )
        .context("Failed to create DBus proxy")?;

        // Add match rule
        let _: () = dbus_proxy
            .call("AddMatch", &(&rule,))
            .context("Failed to add D-Bus match rule")?;

        // Create message iterator to receive signals
        let iter = MessageIterator::from(&self.connection);

        // Create proxy for the loaded script
        let script_proxy = Proxy::new(
            &self.connection,
            "org.kde.KWin",
            script_object_path,
            "org.kde.kwin.Script",
        )
        .context("Failed to create Script proxy")?;

        // Run the script
        let _: () = script_proxy
            .call("run", &())
            .context("Failed to run KWin script")?;

        // Wait for the print signal with timeout
        let mut output: Option<String> = None;
        let deadline = std::time::Instant::now() + Duration::from_millis(500);

        for msg_result in iter {
            if std::time::Instant::now() >= deadline {
                break;
            }

            if let Ok(msg) = msg_result
                && msg.header().message_type() == MessageType::Signal
                && let Some(member) = msg.header().member()
                && member.as_str() == "print"
                && let Ok(text) = msg.body().deserialize::<String>()
            {
                output = Some(text);
                break;
            }
        }

        // Stop the script
        let _: std::result::Result<(), _> = script_proxy.call("stop", &());

        // Remove match rule
        let _: std::result::Result<(), _> = dbus_proxy.call("RemoveMatch", &(&rule,));

        Ok(output)
    }
}

impl Compositor for KwinCompositor {
    fn list_windows(&self) -> Result<Vec<WindowInfo>> {
        let output = self
            .run_script(LIST_WINDOWS_SCRIPT)?
            .ok_or_else(|| anyhow!("No output from KWin script (timeout or no windows)"))?;

        let windows: Vec<KwinWindow> =
            serde_json::from_str(&output).context("Failed to parse KWin window list JSON")?;

        Ok(windows
            .into_iter()
            .map(|w| WindowInfo {
                address: w.id,
                title: w.title,
                class: w.class,
                workspace: w.workspace,
                focused: w.focused,
            })
            .collect())
    }

    fn focus_window(&self, window_id: &str) -> Result<()> {
        let script = FOCUS_WINDOW_SCRIPT_TEMPLATE.replace("%WINDOW_ID%", window_id);
        self.run_script(&script)?;
        Ok(())
    }

    fn name(&self) -> &'static str {
        "KWin"
    }
}
