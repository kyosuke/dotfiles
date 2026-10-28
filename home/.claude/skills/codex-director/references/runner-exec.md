# 委任ランナー: codex exec（見えない代替）

herdr も Orca も無いとき（Codex アプリ内のターミナルなど）に読む（判定の順は `../SKILL.md`）。Codex 側の運用（依頼文の渡し方、並列の可否、ネットワーク、スレッドの分割）はランナーに依らないので `execution.md` にある。

`codex exec` をバックグラウンドで走らせる。ランナーに求める4条件のうち「動作がユーザーに見える」と「承認が人へ届く」を欠く。それを承知でユーザーが用意させた代替経路である（2026-10-28）。発注前報告で、このランナーで出すこと（画面に出ない、承認は auto-reviewer だけが判断する）を1行添える。

## 承認で固まらせない

`approval_policy=on-request` でも、承認を auto-reviewer へ回せば固まらない。**`-c approvals_reviewer=auto_review` を必ず付ける。** 省くと承認が人へ上がり、答える相手がいないまま固まる（`evidence.md`）。auto-reviewer が却下した操作は失敗として Codex へ返る。

`--approve-for-me` も同じ設定（`on-request` + `auto_review`）になるが、サンドボックスを `workspace-write` に固定し、`exec resume` には無い。起動と再開で同じ形にするため `-c` で渡す。

## プロファイルを値で渡す

| プロファイル | 起動引数 |
|---|---|
| `dev-low` | `-c model=gpt-6-luna -c model_reasoning_effort=low -c service_tier=priority` |
| `dev-default` | `-c model=gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority` |
| `dev-high` | `-c model=gpt-6.1-sol -c model_reasoning_effort=low -c service_tier=priority` |
| `dev-xhigh` | `-c model=gpt-6.1-sol -c model_reasoning_effort=high -c service_tier=priority` |
| `dev-max` | `-c model=gpt-6-astra -c model_reasoning_effort=xhigh -c service_tier=default` |

どれにも共通で次を足す。以下では、プロファイルの引数にこれを足したものを「起動引数」と呼ぶ。

```
-c approval_policy=on-request -c approvals_reviewer=auto_review -c sandbox_mode=<workspace-write|read-only>
```

プロファイルの定義は `../SKILL.md` の表にある。`service_tier` の語彙は `runner-orca.md` と同じ。

- 読み取りだけの依頼は `sandbox_mode=read-only` にする。`-s` は `exec resume` に無いので使わない。
- ネットワークが要る依頼は `-c sandbox_workspace_write.network_access=true` を足す（`execution.md`）。

## 発注する

依頼文は Write でファイルへ書き（`execution.md`）、標準入力から渡す。報告は `-o` でファイルへ、イベントは `--json` で別ファイルへ落とす。実装を伴う依頼は Bash の上限の10分を超えるので、`run_in_background: true` で投げて完了通知を待つ。

```bash
cd <作業ディレクトリ> && codex exec <起動引数> --json \
  -o <scratchpad>/<タスク名>.report.md - \
  < <scratchpad>/<タスク名>.order.md \
  > <scratchpad>/<タスク名>.events.jsonl 2> <scratchpad>/<タスク名>.stderr
```

完了したら `<タスク名>.report.md` が最終報告である（最後の `agent_message` だけが入る）。空なら `.stderr` と `.events.jsonl` の末尾を読む。待機中の進み具合は `.events.jsonl` を見る。`item.completed` の `command_execution` に、コマンドと `exit_code` が出る。ユーザーに見せたいときは `tail -f` を案内する。

**報告だけで実行の有無を判断しない。** 推論量 `low` では、何も実行せずに「列挙します」とだけ返して終わったことがある（2026-10-28）。`.events.jsonl` に `command_execution` があるかを見る。

## 差し戻す

`.events.jsonl` の1行目（`thread.started`）にある `thread_id` を控え、同じスレッドへ送る。

```bash
cd <作業ディレクトリ> && codex exec resume <thread_id> <起動引数> --json \
  -o <scratchpad>/<タスク名>.report2.md - \
  < <scratchpad>/<タスク名>.fix.md \
  > <scratchpad>/<タスク名>.events2.jsonl 2> <scratchpad>/<タスク名>.stderr2
```

- **起動引数は再開時も全部渡す。** 省いた設定は `~/.codex/config.toml` の既定に戻る。read-only で起動したスレッドでも、再開時に指定しなかったら `workspace-write` になった（2026-10-28）。
- `exec resume` には `-C` が無く、セッションの検索も cwd で絞られる。起動と同じディレクトリへ `cd` してから実行する。
- `--last` は使わない。直近のセッションは別のリポジトリや用途のことがある。

## 片付け

プロセスは終われば消えるので、畳む操作は無い。並列化で worktree が要るなら、`git worktree add` で作って `execution.md` の手順で取り込み、まず `--force` なしで `git worktree remove` する。このランナーには公式の手順が無いので、これに限り直接叩く。`--worktree` フラグ（Codex 管理の worktree）は未検証なので使わない。
