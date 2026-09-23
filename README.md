# dotfiles

Personal dotfiles for macOS. Configs for my terminal, shell, multiplexer, and
AI coding tools (Claude Code, Codex), linked into place with
[mise dotfiles](https://mise.jdx.dev/dotfiles.html).

> These are tuned for my own machine and contain some hard-coded paths and
> personal choices. Read and borrow freely, but don't expect them to work as-is.

## Setting up a new Mac

`mise bootstrap` links the config files, installs Node.js, pnpm, fish, Codex,
OpenCode, herdr, Hunk, Yazi, gh, and the npm CLIs esa, SVGO, and Wrangler
(`home/.config/mise/config.toml`), installs Claude Code with its native
installer, sets up the fish plugins, installs the PlemolJP35 Console NF font
from its GitHub release, and turns the trackpad tracking speed and
key repeat rate up to their maximum (applied after logging out).
Everything else is installed without Homebrew: the official installer,
otherwise [webi](https://webinstall.dev/).

1. Install Git with the Command Line Tools: `xcode-select --install`
2. Install mise and run the bootstrap:

   ```sh
   curl https://mise.run | sh
   git clone https://github.com/kyosuke/dotfiles.git ~/GitHub/kyosuke/dotfiles
   cd ~/GitHub/kyosuke/dotfiles
   ~/.local/bin/mise trust
   ~/.local/bin/mise bootstrap
   ```

   It is safe to run again. The fish plugins come from
   `home/.config/fish/fish_plugins`; add more with `fisher install`, which
   writes through the link, so commit the change here.
3. Install the apps the configs refer to (Ghostty, WezTerm, and Orca) from
   their official sites, listed in
   [docs/apps.md](docs/apps.md).
4. Open WezTerm or Ghostty. `.zshenv` puts `~/.local/bin` and the mise shims on
   `PATH`, and the terminal starts fish (WezTerm) or herdr (Ghostty) through
   them.
5. Start Codex and trust the linked hooks from `/hooks`.

## What's inside

`home/` mirrors `~`: every tracked file under it is linked to the same path in
the home directory. `agent-skills/` holds skill directories for Codex and other
agents, each linked to `~/.agents/skills/<name>`.

| Path | Tool |
|------|------|
| `home/.zshenv` | zsh (login shell, PATH setup) |
| `home/.config/fish/config.fish`, `fish_plugins` | fish (interactive shell, fisher plugins) |
| `home/.config/mise/config.toml` | mise (Node.js, fish, and CLI versions) |
| `home/.wezterm.lua`, `home/.config/ghostty/config` | WezTerm, Ghostty |
| `home/.config/herdr/`, `hunk/`, `yazi/` | herdr, Hunk, Yazi |
| `home/.config/opencode/opencode.jsonc` | OpenCode |
| `home/.config/git/ignore` | Git global ignore |
| `home/.claude/` | Claude Code (settings, statusline, hooks, skills) |
| `home/.codex/` | Codex CLI (command policy, Herdr summary hooks) |
| `agent-skills/` | Skills for Codex and other agents |
| `scripts/check-codex-policy.sh` | Validates the Codex command policy |
| `scripts/install-fonts.sh` | Installs the terminal font (run by `mise bootstrap`) |
| `docs/apps.md` | Apps installed outside mise, with download links |

## Adding or removing files

Links are declared in `mise.toml` and point back into this repo, so edits here
take effect immediately. After adding or removing a file under `home/` or
`agent-skills/`, stage it with `git add` and run `mise dotfiles apply` again:
only files in the Git index are linked, and links whose source has gone are
removed. `mise dotfiles status` shows what is out of date.

Files under `home/` are linked one by one, so directories such as
`~/.claude/skills/` can also hold skills installed by other tools. Codex skill
directories are linked as a whole because Codex does not load a skill whose
`SKILL.md` is a file symlink.

Do not pass `--force` while a directory in `~` is a symlink into this repo
(for example `~/.claude/skills/<name>` from an older setup). mise writes the
file links through it and replaces the sources here with links to themselves.
Remove such a directory symlink first.

## Design notes

**Shell layout.** zsh is the login shell and only sets up `PATH`; fish is the
interactive shell. Terminals start a login shell first so `PATH` is resolved,
then hand off to fish (WezTerm) or herdr (Ghostty), so neither config
hard-codes where fish or herdr is installed. The login shell reaches fish
through the mise shims in `.zshenv`; fish then runs `mise activate` so
per-project tool versions apply.

**Node.js and fish from mise.** Node.js follows the current LTS
(`mise upgrade node`, then `mise prune` to drop old versions). `npm install -g`
writes into the active Node.js version under `~/.local/share/mise` without
`sudo`, and mise reshims afterwards, so no custom npm prefix is set. Those
globals do not carry over to a new version, so CLIs meant to stay are declared
as `npm:` tools in the mise config instead. Do not install the official
`.pkg` builds as well: macOS's `path_helper` puts `/usr/local/bin` ahead of the
shims in login shells, so those copies would win outside fish.

**Claude Code config is opt-in.** `~/.claude/` holds session history,
transcripts, caches, and credentials, so this public repo ignores it by default
and tracks only an allow-list (`home/.claude/.gitignore`).
`agent-skills/.gitignore` works the same way. `.gitignore` files themselves are
not linked.

**Codex config scope.** Only the command policy and hooks are managed.
`~/.codex/config.toml` is left machine-local because the Codex app rewrites it
with plugin state, MCP configuration, project trust entries, and other
generated values. If a stable public profile is ever split out, the candidates
are `approval_policy`, `approvals_reviewer`, and `sandbox_mode`. Run
`scripts/check-codex-policy.sh` after changing the command policy.
