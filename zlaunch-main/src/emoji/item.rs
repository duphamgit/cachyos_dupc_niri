/// An emoji item for display in the emoji picker grid.
#[derive(Clone, Debug)]
pub struct EmojiItem {
    /// The emoji character(s).
    pub emoji: String,
    /// The display name of the emoji.
    pub name: String,
}

impl EmojiItem {
    /// Create a new emoji item.
    pub fn new(emoji: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            emoji: emoji.into(),
            name: name.into(),
        }
    }
}
