#!/bin/bash

# Lấy đường dẫn tuyệt đối của thư mục chứa script
DOTFILES_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "🚀 Đang bắt đầu thiết lập Dotfiles & LED cho CachyOS..."

# 1. Cài đặt các gói cần thiết (Thêm OpenRGB và Qt plugins)
echo "📦 Đang cài đặt các thành phần hệ thống..."
sudo pacman -S --needed stow openrgb qt5-wayland qt6-wayland -y

# 2. Thiết lập OpenRGB (Driver & Udev)
echo "🛠️ Đang cấu hình driver cho LED..."

# Tự động nạp module i2c-dev khi khởi động
if [ ! -f /etc/modules-load.d/openrgb.conf ]; then
    echo "i2c-dev" | sudo tee /etc/modules-load.d/openrgb.conf
fi

# Tải udev rules nếu chưa có để nhận diện mainboard
if [ ! -f /etc/udev/rules.d/60-openrgb.rules ]; then
    sudo curl -L https://gitlab.com/CalcProgrammer1/OpenRGB/-/raw/master/60-openrgb.rules -o /etc/udev/rules.d/60-openrgb.rules
    sudo udevadm control --reload-rules && sudo udevadm trigger
fi

# 3. Danh sách các gói cấu hình (Thêm OpenRGB vào danh sách Stow)
PACKAGES=("niri" "waybar" "fuzzel" "openrgb")

# 4. Dọn dẹp và liên kết (Stow)
echo "🔗 Đang tiến hành tạo liên kết (Symlinks)..."

cd "$DOTFILES_DIR"

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
        echo "🔹 Đang xử lý: $pkg"
        
        # Xóa thư mục/file cũ để tránh xung đột
        rm -rf "$HOME/.config/$pkg"
        mkdir -p "$HOME/.config"
        
        # Chạy lệnh Stow
        stow "$pkg"
    else
        echo "⚠️ Cảnh báo: Không tìm thấy thư mục cấu hình cho $pkg"
    fi
done

echo "🎉 Chúc mừng! Mọi thứ đã được đồng bộ."
echo "Hãy nhấn Mod+Shift+R để reload Niri."
