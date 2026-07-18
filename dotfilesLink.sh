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

link "$DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"
link "$DIR/.config/git/ignore" "$HOME/.config/git/ignore"
link "$DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
link "$DIR/.config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
link "$DIR/.config/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
link "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
link "$DIR/.zshenv" "$HOME/.zshenv"

link "$DIR/.codex/rules/command-policy.rules" "$HOME/.codex/rules/command-policy.rules"

link "$DIR/.claude/settings.json" "$HOME/.claude/settings.json"
link "$DIR/.claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
link "$DIR/.claude/skills/grill-me" "$HOME/.claude/skills/grill-me"
link "$DIR/.claude/skills/dual-review" "$HOME/.claude/skills/dual-review"
link "$DIR/.claude/skills/post-merge-cleanup" "$HOME/.claude/skills/post-merge-cleanup"
link "$DIR/.claude/skills/pr-review-fix" "$HOME/.claude/skills/pr-review-fix"
