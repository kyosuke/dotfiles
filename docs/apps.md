# Apps installed outside mise

`mise bootstrap` does not install these apps: 1Password, which holds the
credentials needed once the Mac is set up, and the apps the configs in `home/`
refer to. Download each from its official site. The apps update
themselves, except WezTerm, so reinstall WezTerm from the same page.

mise can install Homebrew casks without Homebrew, but it creates `/opt/homebrew`
with `sudo`, and a third-party tap such as Orca's needs Ruby 3 before the tools
phase has run. The apps that update themselves gain nothing from it after the
first install. Fonts are installed by `mise bootstrap` from GitHub
instead (`scripts/install-fonts.sh`).

| App | Download | Notes |
|-----|----------|-------|
| [1Password](https://1password.com/) | <https://1password.com/downloads/mac> | Install first: little else works until it is signed in |
| [Ghostty](https://ghostty.org/) | <https://ghostty.org/download> | Config: `home/.config/ghostty/config` |
| [WezTerm](https://wezterm.org/) | <https://wezterm.org/install/macos.html> | Config: `home/.wezterm.lua` |
| [Orca](https://www.onorca.dev/) | <https://github.com/stablyai/orca/releases/latest> (`orca-macos-arm64.dmg`) | See below |

`jq` and `python3`, which the Claude Code statusline and hooks use, come with
macOS and the Command Line Tools, so they need no separate install.

## Orca

Orca writes its agent hooks into `~/.claude/settings.json` and
`~/.codex/hooks.json` when it starts. Both are links into this repo, and
`home/.claude/settings.json` already holds the hook string Orca writes, so
nothing should change. After the first launch, run `git status` here: a diff
means this Orca version writes a different string. Commit it, or match the
other Mac's Orca version.

Orca registers the `orca` CLI at `/usr/local/bin/orca` from its in-app
"Install CLI" action.
