#!/bin/sh
# WezTerm と Ghostty が使う PlemolJP35 Console NF を ~/Library/Fonts へ入れる。
# Homebrew の cask は Homebrew 本体が要るので使わず、GitHub のリリースから取る。
# zip は全書体入りで 150MB ほどあるため、入っていれば取りに行かない。

set -eu

FONTS="$HOME/Library/Fonts"
[ -e "$FONTS/PlemolJP35ConsoleNF-Regular.ttf" ] && exit 0

url=$(curl -fsSL https://api.github.com/repos/yuru7/PlemolJP/releases/latest |
  grep -o 'https://[^"]*/PlemolJP_NF_v[^"]*\.zip' | head -n 1)
[ -n "$url" ] || {
  printf '%s\n' 'PlemolJP_NF のリリースが見つからない' >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/plemoljp.zip" "$url"
mkdir -p "$FONTS"
unzip -q -j -o "$tmp/plemoljp.zip" '*/PlemolJP35Console_NF/*.ttf' -d "$FONTS"
