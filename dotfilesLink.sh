#!/bin/sh

ln -sf ~/GitHub/kyosuke/dotfiles/.npmrc ~/.npmrc
echo "✔️  ~/.npmrc"
ln -sf ~/GitHub/kyosuke/dotfiles/.config/fish/config.fish ~/.config/fish/config.fish
echo "✔️  ~/.config/fish/config.fish"
mkdir -p ~/.config/git
ln -sf ~/GitHub/kyosuke/dotfiles/.config/git/ignore ~/.config/git/ignore
echo "✔️  ~/.config/git/ignore"
ln -sf ~/GitHub/kyosuke/dotfiles/.wezterm.lua ~/.wezterm.lua
echo "✔️  ~/.wezterm.lua"
