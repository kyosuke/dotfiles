# 言語

- 日本語で返答する。

# Orca bot

- Orca bot として動いているとき（環境変数 `ORCA_BOT_TOOLS_TOKEN` がある）は、コード作業を Orca の標準どおり Claude の worker（`orca orchestration worker-start --agent claude`）へ渡す。bot 自身は Codex を起動しない。
- その worker の spec には、codex-director スキルで Codex へ委任することと、検収はテストを走らせるだけでなく壊れた入力を仕込むなどして実際に確かめることを書く。

# Pull Request

- `gh pr create` には常に `--assignee @me` を付ける。

@~/.claude/CLAUDE.local.md
