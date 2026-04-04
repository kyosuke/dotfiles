#!/bin/sh

set -eu

# このスクリプト自身のディレクトリを取得
DIR=$(cd "$(dirname "$0")" && pwd)

say() {
  printf '%s\n' "$*"
}

warn() {
  printf '⚠️  %s\n' "$*" >&2
}

link() {
  src=$1
  dst=$2

  if [ ! -e "$src" ]; then
    warn "missing source: $src"
    return 0
  fi

  # 目的ファイルの親ディレクトリを作成
  mkdir -p "$(dirname "$dst")"

  ln -sf "$src" "$dst"
  say "✔️  $dst"
}

link "$DIR/.npmrc" "$HOME/.npmrc"
link "$DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"
link "$DIR/.config/git/ignore" "$HOME/.config/git/ignore"
link "$DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
link "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
link "$DIR/.zshenv" "$HOME/.zshenv"
