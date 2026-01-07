#!/bin/bash

# Lấy đường dẫn tuyệt đối của thư mục chứa script
DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "🚀 Đang bắt đầu thiết lập Dotfiles cho CachyOS (Niri, Waybar, Fuzzel)..."

# 1. Cài đặt GNU Stow nếu chưa có
if ! command -v stow &> /dev/null; then
    echo "📦 Đang cài đặt GNU Stow..."
    sudo pacman -S --needed stow -y
else
    echo "✅ GNU Stow đã được cài đặt."
fi

# 2. Danh sách các gói cấu hình (tương ứng với tên các thư mục con)
PACKAGES=("niri" "waybar" "fuzzel")

# 3. Dọn dẹp và liên kết (Stow)
echo "🔗 Đang tiến hành tạo liên kết (Symlinks)..."

cd "$DOTFILES_DIR"

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
        echo "🔹 Đang xử lý: $pkg"
        
        # Xóa thư mục/file cũ trong ~/.config để tránh xung đột với Stow
        # Stow sẽ không link nếu tại đích đã có file/thư mục thật
        rm -rf "$HOME/.config/$pkg"
        
        # Tạo thư mục cha nếu chưa có (để đảm bảo Stow link đúng vào .config)
        mkdir -p "$HOME/.config"
        
        # Chạy lệnh Stow
        stow "$pkg"
    else
        echo "⚠️ Cảnh báo: Không tìm thấy thư mục cấu hình cho $pkg"
    fi
done

echo "🎉 Chúc mừng! Mọi thứ đã được đồng bộ."
echo "Hãy nhấn Mod+Shift+R để reload Niri hoặc khởi động lại máy để thấy thay đổi."
