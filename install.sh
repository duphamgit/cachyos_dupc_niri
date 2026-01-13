#!/bin/bash

# Lấy đường dẫn tuyệt đối của thư mục chứa script
DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "🚀 Đang bắt đầu thiết lập Dotfiles & LED cho CachyOS... Niri version"

# 1. Cài đặt các gói cần thiết
# Thêm i2c-tools để hỗ trợ quét phần cứng và rofi-wayland để chạy mượt trên Niri
echo "📦 Đang cài đặt các thành phần hệ thống..."
sudo pacman -S --needed stow openrgb i2c-tools qt5-wayland qt6-wayland waypaper rofi-wayland zed fcitx5-bamboo fcitx5-configtool chromium github-cli -y
# cài đặt zlaunch phiên bản cá nhân
echo "📦 Đang cài đặt zlaunch app launcher AI gemini..."
sudo pacman -S base-devel rustup
rustup default stable
cd cachyos_dupc_niri/zlaunch-main/
cargo install --path .
# 2. Thiết lập OpenRGB (Driver & Udev)
echo "🛠️ Đang cấu hình driver cho LED..."

# Tự động nạp các module cần thiết cho Intel SMBus (Mainboard B760M) và I2C
# i2c-i801 là driver quan trọng nhất cho dòng mainboard của bạn
if [ ! -f /etc/modules-load.d/openrgb.conf ]; then
    echo -e "i2c-dev\ni2c-i801" | sudo tee /etc/modules-load.d/openrgb.conf
    # Nạp ngay lập tức để không cần khởi động lại
    sudo modprobe i2c-dev i2c-i801
fi

# Dọn dẹp udev rules cũ để tránh lỗi "Multiple udev rules installed"
if [ -f /etc/udev/rules.d/60-openrgb.rules ]; then
    sudo rm /etc/udev/rules.d/60-openrgb.rules
fi

# Cài đặt udev rules chính thức từ package (ổn định hơn tải từ git)
# Thông thường package openrgb trên Arch đã có sẵn, ta chỉ cần kích hoạt
sudo udevadm control --reload-rules && sudo udevadm trigger

# Cấp quyền cho user hiện tại truy cập I2C mà không cần sudo
sudo usermod -aG i2c $USER

# 3. Danh sách các gói cấu hình
PACKAGES=("niri" "waybar" "fuzzel" "openrgb" "rofi" "zlaunch")

# 4. Dọn dẹp và liên kết (Stow)
echo "🔗 Đang tiến hành tạo liên kết (Symlinks)..."

cd "$DOTFILES_DIR"

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
        echo "🔹 Đang xử lý: $pkg"

        # Chỉ xóa nếu nó là thư mục thật hoặc file thật, tránh xóa nhầm symlink
        if [ -e "$HOME/.config/$pkg" ]; then
            rm -rf "$HOME/.config/$pkg"
        fi

        mkdir -p "$HOME/.config"

        # Chạy lệnh Stow
        stow "$pkg"
    else
        echo "⚠️ Cảnh báo: Không tìm thấy thư mục cấu hình cho $pkg"
    fi
done

echo "------------------------------------------------------------"
echo "🎉 Chúc mừng! Mọi thứ đã được đồng bộ."
echo "👉 Lưu ý: Bạn cần REBOOT để quyền I2C có hiệu lực."
echo "👉 Sau đó, mở OpenRGB và nhấn 'Rescan Devices' để nhận Mainboard."
echo "👉 Nhấn Mod+Space để mở App Launcher (Rofi)."
