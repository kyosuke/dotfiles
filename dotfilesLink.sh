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

relink_skill() {
  name=$1
  legacy="$HOME/.claude/skills/$name"
  # 旧構成ではスキルのディレクトリ自体をシンボリックリンクにしていた。
  # 残っているとファイル単位の ln が親リンクを辿り、リポジトリ側の実体を壊すので先に外す
  if [ -L "$legacy" ]; then
    rm "$legacy"
  fi
  link "$DIR/.claude/skills/$name/SKILL.md" "$legacy/SKILL.md"
}

link "$DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"
link "$DIR/.config/git/ignore" "$HOME/.config/git/ignore"
link "$DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
link "$DIR/.config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
link "$DIR/.config/hunk/config.toml" "$HOME/.config/hunk/config.toml"
link "$DIR/.config/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
link "$DIR/.config/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"
link "$DIR/.config/yazi/theme.toml" "$HOME/.config/yazi/theme.toml"
link "$DIR/.config/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
link "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
link "$DIR/.zshenv" "$HOME/.zshenv"

link "$DIR/.codex/rules/command-policy.rules" "$HOME/.codex/rules/command-policy.rules"
link "$DIR/.codex/hooks.json" "$HOME/.codex/hooks.json"
link "$DIR/.codex/herdr-codex-summary.py" "$HOME/.codex/herdr-codex-summary.py"

link "$DIR/.claude/settings.json" "$HOME/.claude/settings.json"
link "$DIR/.claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
# herdr が管理する herdr-agent-state.sh とは別ファイル。integration の再インストールで消えない。
link "$DIR/.claude/hooks/herdr-claude-summary.sh" "$HOME/.claude/hooks/herdr-claude-summary.sh"
relink_skill grill-me
relink_skill dual-review
relink_skill post-merge-cleanup
relink_skill pr-review-fix
