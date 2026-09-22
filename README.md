# dotfiles

Personal dotfiles for macOS. Configs for my terminal, shell, multiplexer, and
AI coding tools (Claude Code, Codex), linked into place with
[mise dotfiles](https://mise.jdx.dev/dotfiles.html).

> These are tuned for my own machine and contain some hard-coded paths and
> personal choices. Read and borrow freely, but don't expect them to work as-is.

## What's inside

`home/` mirrors `~`: every tracked file under it is linked to the same path in
the home directory. `agent-skills/` holds skill directories for Codex and other
agents, each linked to `~/.agents/skills/<name>`.

| Path | Tool |
|------|------|
| `home/.config/fish/config.fish` | fish (interactive shell) |
| `home/.zshenv` | zsh (login shell, PATH setup) |
| `home/.wezterm.lua` | WezTerm terminal |
| `home/.config/ghostty/config` | Ghostty terminal |
| `home/.config/herdr/config.toml` | herdr (multiplexer) |
| `home/.config/zellij/config.kdl` | Zellij (multiplexer) |
| `home/.config/hunk/config.toml` | Hunk (diff review) |
| `home/.config/yazi/` | Yazi (file manager) |
| `home/.config/opencode/opencode.jsonc` | OpenCode |
| `home/.config/git/ignore` | Git global ignore |
| `home/.claude/` | Claude Code (settings, statusline, hooks, skills) |
| `home/.codex/rules/command-policy.rules` | Codex CLI command policy |
| `home/.codex/hooks.json` | Codex CLI hooks (Herdr summary) |
| `home/.codex/herdr-codex-summary.py` | Codex → Herdr summary hook |
| `agent-skills/post-merge-cleanup/` | Codex/agent skill |
| `scripts/check-codex-policy.sh` | Codex command-policy validation (run from this repo) |

## Requirements

macOS and [mise](https://mise.jdx.dev/). This repo only links config files and
skill directories; it does not install anything, so the tools above must be
installed separately. The terminal configs also expect the `PlemolJP35 Console`
font and the fish `Pure` prompt.

## Install

```sh
mise trust
mise dotfiles apply
```

Run these from this repo; the links are declared in its `mise.toml`. Edits you
make here take effect immediately. After adding or removing a file under
`home/` or `agent-skills/`, stage it with `git add` and run
`mise dotfiles apply` again: only files in the Git index are linked, and links
whose source has gone are removed. `mise dotfiles status` shows what is out of
date.

Files under `home/` are linked one by one, so directories such as
`~/.claude/skills/` can also hold skills installed by other tools. Codex skill
directories are linked as a whole so the required `SKILL.md` stays at the path
Codex scans: Codex does not load a skill whose `SKILL.md` is a file symlink.

Do not pass `--force` while a directory in `~` is a symlink into this repo
(for example `~/.claude/skills/<name>` from an older setup). mise writes the
file links through it and replaces the sources here with links to themselves.
Remove such a directory symlink first.

## Shell layout

zsh is the login shell and only sets up `PATH` (`.zshenv`); fish is the
interactive shell. Terminals start a login shell first so `PATH` is resolved,
then hand off to fish (WezTerm) or a multiplexer (Ghostty → herdr). Running the
login shell by name keeps the setup working on both Intel and Apple Silicon
without hard-coding install locations.

## Claude Code config is opt-in

`~/.claude/` collects session history, transcripts, caches, and credentials, so
this public repo ignores the directory by default and tracks only the files I
chose to share: `settings.json`, the statusline script, and a few skills. See
`home/.claude/.gitignore` for the allow-list; `agent-skills/.gitignore` works
the same way for agent skills. `.gitignore` files are excluded
from linking.

## Codex config scope

This repository manages the durable Codex command policy and the Herdr summary
hooks. It does not link `~/.codex/config.toml`: the Codex app updates that file
with machine-specific settings, plugin state, MCP configuration, project trust
entries, and other generated values.

The linked `hooks.json` preserves Herdr's session-identity hook and adds a
display-only summary hook. Codex may ask you to review and trust the new hook
entries from `/hooks` after the first install or change.

If the global configuration is ever split into a stable public profile, the
best candidates to manage are `approval_policy`, `approvals_reviewer`, and
`sandbox_mode`. Keep model/reasoning preferences, plugin and MCP settings,
project paths, notifications, desktop preferences, marketplaces, and hook
state machine-local. Use `scripts/check-codex-policy.sh` after changing the
command policy.
