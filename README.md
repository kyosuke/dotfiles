# dotfiles

Personal dotfiles for macOS. Configs for my terminal, shell, multiplexer, and
AI coding tools (Claude Code, Codex), linked into place with a small shell
script.

> These are tuned for my own machine and contain some hard-coded paths and
> personal choices. Read and borrow freely, but don't expect them to work as-is.

## What's inside

| Path | Tool | Linked to |
|------|------|-----------|
| `.config/fish/config.fish` | fish (interactive shell) | `~/.config/fish/config.fish` |
| `.zshenv` | zsh (login shell, PATH setup) | `~/.zshenv` |
| `.wezterm.lua` | WezTerm terminal | `~/.wezterm.lua` |
| `.config/ghostty/config` | Ghostty terminal | `~/.config/ghostty/config` |
| `.config/herdr/config.toml` | herdr (multiplexer) | `~/.config/herdr/config.toml` |
| `.config/zellij/config.kdl` | Zellij (multiplexer) | `~/.config/zellij/config.kdl` |
| `.config/git/ignore` | Git global ignore | `~/.config/git/ignore` |
| `.claude/` | Claude Code (settings, statusline, skills) | `~/.claude/…` |
| `.codex/rules/command-policy.rules` | Codex CLI command policy | `~/.codex/rules/…` |

## Requirements

macOS. This repo only links config files; it does not install anything, so the
tools above must be installed separately. The terminal configs also expect the
`PlemolJP35 Console` font and the fish `Pure` prompt.

## Install

```sh
chmod u+x dotfilesLink.sh
./dotfilesLink.sh
```

The script symlinks the files from this repo into your home directory, so edits
you make here take effect immediately. A missing source file is skipped with a
warning instead of failing the whole run.

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
`.claude/.gitignore` for the allow-list.
