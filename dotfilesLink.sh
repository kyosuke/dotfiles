#!/bin/sh

# このスクリプト自身のディレクトリを取得
dir="$(cd "$(dirname "$0")" && pwd)"

ln -sf "$dir/.npmrc" ~/.npmrc
echo "✔️  ~/.npmrc"
ln -sf "$dir/.config/fish/config.fish" ~/.config/fish/config.fish
echo "✔️  ~/.config/fish/config.fish"
mkdir -p ~/.config/git
ln -sf "$dir/.config/git/ignore" ~/.config/git/ignore
echo "✔️  ~/.config/git/ignore"
mkdir -p ~/.config/ghostty
ln -sf "$dir/.config/ghostty/config" ~/.config/ghostty/config
echo "✔️  ~/.config/ghostty/config"
ln -sf "$dir/.wezterm.lua" ~/.wezterm.lua
echo "✔️  ~/.wezterm.lua"
