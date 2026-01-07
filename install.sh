#!/bin/bash

echo "🚀 Đang thiết lập Dotfiles bằng GNU Stow cho Niri và Waybar..."

# 1. Cài đặt Stow
sudo pacman -S --needed stow -y

# 2. Xóa các thư mục config mặc định (để tránh xung đột khi Stow tạo link)
echo "🧹 Đang dọn dẹp các thư mục cấu hình cũ..."
rm -rf ~/.config/niri
rm -rf ~/.config/waybar

# 3. Sử dụng Stow để tạo liên kết
# Lệnh này sẽ tạo link cho mọi thứ bên trong folder niri và waybar vào $HOME
echo "🔗 Đang tạo Symlinks..."
stow niri
stow waybar

echo "✅ Xong! Cấu hình Niri và Waybar đã được áp dụng."
