# 委任ランナー: Orca

`ORCA_TERMINAL_HANDLE` が空でないときに読む（判定の順は `../SKILL.md`）。Codex 側の運用（依頼文の渡し方、承認の境界、並列の可否、ネットワーク、スレッドの片付け）はランナーに依らないので `execution.md` にある。

**Orca の操作は本体が出すガイドに従う。** `orca skills get orca-cli` を実行して読む（バイナリが出力元なので本体の更新に追従する）。`~/.agents/skills/orca-cli` はこのガイドを呼び出すための案内だけで、Skill ツールには出てこない。ターミナルの作成・読み取り・送信・待機のフラグや、worktree のセレクタの書き方はガイドにあるので、ここには書かない。読まずに想像で補わない。

この Skill からの上書きと、ガイドに無い事実だけをここに置く。

## Orchestration を使わない

`orca orchestration worker-start` は監督付きの起動経路だが、委任には使わない。渡せるのが `--model` と `--effort` だけで、`service_tier`・サンドボックス・ネットワークを指定できない。完了も `worker_done` の3文要約で返す約束になっていて、報告を全文で回収する前提（`execution.md`）と合わない。`worktree create --agent codex` も Orca の既定ランチャーで起動するので、起動引数を渡せない。

Codex は `terminal create --command` で起動引数ごと立ち上げ、プロファイルの値を起動引数に展開して渡す。

## プロファイルを値で渡す

| プロファイル | `--command` に書く Codex の起動 |
|---|---|
| `dev-low` | `codex -m gpt-6-luna -c model_reasoning_effort=low -c service_tier=priority` |
| `dev-default` | `codex -m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority` |
| `dev-high` | `codex -m gpt-6-luna -c model_reasoning_effort=max -c service_tier=priority` |
| `dev-max` | `codex -m gpt-6-sol -c model_reasoning_effort=xhigh -c service_tier=default` |

プロファイルの定義は `../SKILL.md` の表にある。プロファイルが変わったらこの表を直す。

Fast は Codex の `service_tier` で、プロファイルの `fast_mode: true` を `priority`、無しを `default` へ写す。値の語彙は [`codex-rs/core/config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json) にあり、オフを表す `default` はここにしか出てこない（`models_cache.json` は各モデルの対応ティア表で、語彙の一覧ではない）。オンに legacy の `fast` ではなく `priority` を渡す。対応ティアに無い値は警告つきでオフになるだけなので使わない（実測は `evidence.md`）。

`service_tier` は必ず明示する。Orca から起動した Codex の設定は `~/.codex` ではなく `$ORCA_CODEX_HOME`（`~/Library/Application Support/orca/codex-runtime-home/home`）にあり、`config.toml` はリンクではなく独立した複製である。`execution.md` と `recovery.md` が `~/.codex/config.toml`・`~/.codex/models_cache.json`・`~/.codex/sessions` と書いている箇所は、このランナーでは `$ORCA_CODEX_HOME` 配下のファイルを指す。書き換えないという規則もこちらの複製に同じく当てはまる。

中間の推論量もそのまま渡せる。プロファイルから外れるときは、理由を発注前報告へ書く（`ordering.md`）。

## 起動する

```bash
orca terminal create --worktree active --title <タスク名> \
  --command 'codex -m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority' --json
```

返ってきた `result.terminal.handle` を以降の宛先に使う。起動時刻も控えておき、実行ログの特定に使う（下記）。

- **書き込みを伴う委任を並列に走らせるなら、worktree を分ける。** `orca worktree create --name <タスク名> --no-parent --json` で作り、`--worktree id:<返ってきた worktree.id>` を付けて `terminal create` する。この順だと最初に空のシェルができる。閉じるのは `terminal list` で使われていないと確かめてから。
- **読み取り専用で起動できる。** `-s read-only` を付けると、実行ログの `turn_context.sandbox_policy` が `read-only` になった。収集役を同じ作業ツリーで並列に走らせる前提（`ordering.md`）は、このランナーでも成立する。
- **ネットワークは起動時に開ける。** `-c sandbox_workspace_write.network_access=true` を渡すと、そのセッションだけネットワークが通る。書き込み範囲は `workspace-write` のままなので、コマンド単位の昇格（サンドボックス外での実行）より露出が小さい。こちらを使い、昇格を既定にしない。ループバックだけを開ける設定は無く、外向きも同時に開く（運用は `execution.md`）。
- `--no-alt-screen` は付けなくてよい。報告は画面から読まない（下記）ので、効き目が無い。

## 依頼文を送る

最初の送信の前に、`terminal wait --for tui-idle` で入力待ちになったことを確かめる。`satisfied: true` が返ってから送る。起動中の TUI へ打ち込んだ依頼文は失われる。

```bash
orca terminal send --terminal <handle> --text "$(cat <scratchpad>/order.txt)" --enter --wait-submit 20 --json
```

`result.send.prompt.stages` に `turn_started` が載っていれば、ターンが始まっている。載っていなくても送り直さない（ガイドの規則）。差し戻しも同じハンドルへ同じ形で送れば、同じスレッドが続く。

## 完了を待つ

**`tui-idle` を完了の判定に使わない。** ターンの開始後に待つと、Codex がまだ作業中なのに1〜2秒で `satisfied: true` を返した（2回とも同じ）。この条件が使えるのは、起動直後の入力待ちの確認だけである。

完了は Codex の実行ログで判定する。ログは `$ORCA_CODEX_HOME/sessions/<年>/<月>/<日>/rollout-*.jsonl` にあり、ターンが終わると `event_msg` の `task_complete` が、却下や中断で終わると `turn_aborted` が1行足される。

**ログは依頼文の本文で特定する。** 最新のファイルを拾うと、並列に走っている別の Codex のログを掴む。依頼文の先頭行を含むファイルのうち、名前（起動時刻が入っている）が最も新しいものを選ぶ。同じ依頼文を出し直したときも、これで新しいほうに当たる。ファイル名の UUID は `codex resume` にそのまま使える（`recovery.md`）。パスに空白が入るので、必ず引用符で囲む。

```bash
H="$ORCA_CODEX_HOME/sessions/$(date +%Y/%m/%d)"
KEY=$(head -1 <scratchpad>/order.txt | cut -c1-60)
R=$(grep -lF "$KEY" "$H"/rollout-*.jsonl | sort | tail -1)
```

待つには、終わりの行が増えるまで回す `until` ループを Bash の `run_in_background: true` で投げ、完了通知を受けてから読む。

```bash
N=$(grep -cE '"type":"(task_complete|turn_aborted)"' "$R")
until [ "$(grep -cE '"type":"(task_complete|turn_aborted)"' "$R")" -gt "$N" ]; do sleep 15; done
```

差し戻しのときは、送る直前に `N` を数え直す。待つ間に承認を求められても、ループは終わらない。承認待ちは次の節の方法で見る。

## 承認を求められたとき

承認を待っている間は、`terminal show --json` の `title` が `[ ! ] Action Required | …` に変わり、`agentWait.reason` が `agent-interactive-prompt` になる。何を求められているかは `terminal read` の末尾に出る（コマンド、理由、選択肢）。承認はユーザーが Orca の画面で答える。ディレクターは代行しない（`execution.md`）。

却下は `terminal send --text $'\e'` で送れる。実行ログには `turn_aborted` が残る。**却下の後も `agentWait` は立ったまま残った。** 承認待ちかどうかは `title` と画面の末尾で判断し、`agentWait` が消えたかどうかでは判断しない。

## 報告を回収する

**報告は画面から読まず、実行ログから取る。** `terminal read` が返すのは PTY の生の出力で、TUI の再描画の断片（`WorkWorkWork…`、プロンプト行の繰り返し）が報告の行に混ざる。`--no-alt-screen` を付けても付けなくても同じだった。実行ログの `task_complete.last_agent_message` は、Codex の最終メッセージを改行を保ったまま全文で持っている。

```bash
jq -rs 'map(select(.payload.type=="task_complete")) | last | .payload.last_agent_message' "$R"
```

差し戻しを重ねたスレッドでは `task_complete` が複数行になるので、上の例のとおり最後のものを読む。報告の中身を信用しないこと、検収は `git diff` で行うことは他のランナーと同じである（`execution.md`・`review.md`）。

**起動引数が効いたかも実行ログで確かめる。** `turn_context` に、実際に当たった `model`・`effort`・`approval_policy`・`sandbox_policy` が載る。消費は `token_count` の `info.total_token_usage` で見る。週次の残量は TUI の `/status` で見る。

## 片付ける

終わったら、自分が作ったターミナルだけを `terminal close --terminal <handle>` で閉じる。**`ok: false`（`terminal_stop_unverifiable`）が返っても、タブは消えていて、プロセスも終わっていた**（3回とも同じ）。閉じ直したり、別のホストに向けて再試行したりしない。`terminal list` から消えたことと、`pgrep -f` で起動コマンドが残っていないことを確かめて終える。

この文書の挙動は Orca 1.4.210 / Codex 0.156.1 で実測した（`evidence.md`）。
