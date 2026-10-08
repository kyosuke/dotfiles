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
| `dev-low` | `codex -m gpt-6-luna -c model_reasoning_effort=low -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-default` | `codex -m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-high` | `codex -m gpt-6.1-sol -c model_reasoning_effort=low -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-xhigh` | `codex -m gpt-6.1-sol -c model_reasoning_effort=high -c service_tier=default -c approvals_reviewer=auto_review` |
| `dev-max` | `codex -m gpt-6-astra -c model_reasoning_effort=xhigh -c service_tier=default -c approvals_reviewer=auto_review` |

プロファイルの定義は `../SKILL.md` の表にある。プロファイルが変わったらこの表を直す。

Fast は Codex の `service_tier` で、プロファイルの Fast 有りを `priority`、無しを `default` へ写す。値の語彙は [`codex-rs/core/config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json) にあり、オフを表す `default` はここにしか出てこない（`models_cache.json` は各モデルの対応ティア表で、語彙の一覧ではない）。オンに legacy の `fast` ではなく `priority` を渡す。対応ティアに無い値は警告つきでオフになるだけなので使わない（実測は `evidence.md`）。

`service_tier` は必ず明示する。Orca から起動した Codex の設定は `~/.codex` ではなく `$ORCA_CODEX_HOME`（`~/Library/Application Support/orca/codex-runtime-home/home`）にあり、`config.toml` はリンクではなく独立した複製である。`execution.md` と `recovery.md` が `~/.codex/config.toml`・`~/.codex/models_cache.json`・`~/.codex/sessions` と書いている箇所は、このランナーでは `$ORCA_CODEX_HOME` 配下のファイルを指す。書き換えないという規則もこちらの複製に同じく当てはまる。

`approvals_reviewer=auto_review` も必ず明示する。どちらの `config.toml` にも指定が無く、省くと `turn_context.approvals_reviewer` が `user` になり、承認がすべて人へ上がる（2026-09-29 実測）。`approval_policy` は既定の `on-request` のまま変えない。

表に無い推論量もそのまま渡せる。プロファイルから外れるときは、理由を発注前報告へ書く（`ordering.md`）。

## 起動する

```bash
orca terminal create --worktree active --title <タスク名> \
  --command 'codex -m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority -c approvals_reviewer=auto_review' --json
```

返ってきた `result.terminal.handle` を以降の宛先に使う。起動時刻も控えておき、実行ログの特定に使う（下記）。

- **読み取り専用で起動できる。** `-s read-only` を付けると、実行ログの `turn_context.sandbox_policy` が `read-only` になった。収集役を同じ作業ツリーで並列に走らせる前提（`ordering.md`）は、このランナーでも成立する。
- **ネットワークは起動時に開ける。** `-c sandbox_workspace_write.network_access=true` を渡すと、そのセッションだけネットワークが通る。書き込み範囲は `workspace-write` のままなので、コマンド単位の昇格（サンドボックス外での実行）より露出が小さい。こちらを使い、昇格を既定にしない。ループバックだけを開ける設定は無く、外向きも同時に開く（運用は `execution.md`）。
- `--no-alt-screen` は付けなくてよい。報告は画面から読まない（下記）ので、効き目が無い。

## worktree を分けて起動する

並列に出してよいかの判断、起点、依存物、検収、取り込みは `execution.md` にある。ここには Orca の手順だけを置く。ガイドの「Worktrees」の節も読む。

```bash
orca worktree create --name <タスク名> --no-parent --base-branch <起点> --setup skip --json
```

- **`--agent codex` は使わない。** Orca の既定ランチャーで起動するので、プロファイルの起動引数を渡せない。作ってから、返ってきた `result.worktree.id` を丸ごと `--worktree id:<…>` に渡して `terminal create` する。`id` は `<repoId>::<パス>` の形で、repo の ID だけに縮めない。
- **`--base-branch` は必ず付ける。** 省くと repo の既定ブランチから作られ、今いるブランチではなかった（2026-10-01、`main` から作られた）。
- **`--setup` は repo の `orca.yaml` に setup フックがあるかで決める。** あれば `run` で依存物を入れさせ、無ければ `skip` にして、インストールは依頼文で Codex に頼む（`execution.md`）。
- **最初に空のシェルが1つできる。** `startupTerminal` は `null` で返り、`terminal list` に fish のターミナルが1つ載っていた。`terminal list` で使われていないと確かめてから閉じる。
- 作られる場所は `~/orca/workspaces/<repo>/<タスク名>`、ブランチは `<ユーザーのプレフィックス>/<タスク名>` だった。パスとブランチは決め打ちにせず、返り値の `result.worktree.path` / `branch` を使う。

片付けは、その worktree のターミナルを閉じてから、まず `--force` なしで行う（`execution.md`）。

```bash
orca worktree rm --worktree id:<repoId>::<パス> --json
```

未コミットの変更が残っていると `runtime_error`（`Failed to delete worktree …`）で止まる。残った中身を `execution.md` の手順で確かめ、不要と判断できたときだけ `--force` を付けて消し直す。消えるとディレクトリとブランチの両方が消える（2026-10-01）。

## 依頼文を送る

最初の送信の前に、`terminal wait --for tui-idle` で入力待ちになったことを確かめる。`satisfied: true` が返ってから送る。起動中の TUI へ打ち込んだ依頼文は失われる。

```bash
orca terminal send --terminal <handle> --text "$(cat <scratchpad>/order.txt)" --enter --wait-submit 20 --json
```

`result.send.prompt.stages` に `turn_started` が載っていれば、ターンが始まっている。載っていなくても送り直さない（ガイドの規則）。差し戻しも同じハンドルへ同じ形で送れば、同じスレッドが続く。

## 完了を待つ

**完了は `tui-idle` で待つ。** ガイドの規則どおりで、ターンが終わるまで返らない（Orca 1.4.219 で2回確かめた）。待機は Bash ツールの既定タイムアウト（120秒）を超えるので、`timeout` に `600000` を指定する。

```bash
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 560000 --json
```

`satisfied: true` なら、実行ログで最後のターンの状態を見る（下記）。`satisfied: false` で `blockedReason` が `agent-interactive-prompt` なら承認を待っている（次の節）。それ以外の `false` と、`satisfied: null`（2026-10-07 の時間切れはこちらで返った）は時間切れで、もう一度待つ。

実行ログは、終わったことの確かめと報告の回収に使う。ログは `$ORCA_CODEX_HOME/sessions/<年>/<月>/<日>/rollout-*.jsonl` にあり、ターンが始まると `event_msg` の `task_started` が、終わると `task_complete` が、却下や中断で終わると `turn_aborted` が1行ずつ足される。

**ログは依頼文の本文で特定する。** 最新のファイルを拾うと、並列に走っている別の Codex のログを掴む。依頼文の先頭行を含むファイルのうち、`turn_context.model` が `codex-auto-review` でないもので、名前（起動時刻が入っている）が最も新しいものを選ぶ。auto-reviewer は依頼文を含む自分のログを同じ起動時刻で書くので、名前だけで選ぶとそちらを掴む（2026-10-07、`task_complete` が審査結果の JSON だった）。同じ依頼文を出し直したときも、これで新しいほうに当たる。依頼文が書き込まれるのは送信の後なので、探すのは `tui-idle` が返ってからにする。ファイル名の UUID は `codex resume` にそのまま使える（`recovery.md`）。Bash の変数は呼び出しをまたいで残らないので、出たパスを以後のコマンドへそのまま書く。パスに空白が入るので、必ず引用符で囲む。

```bash
KEY=$(head -1 <scratchpad>/order.txt | cut -c1-60)
grep -lF "$KEY" "$ORCA_CODEX_HOME/sessions/$(date +%Y/%m/%d)"/rollout-*.jsonl | sort | while read -r f; do
  jq -e -s 'map(select(.type=="turn_context")) | last | .payload.model != "codex-auto-review"' "$f" >/dev/null && echo "$f"
done | tail -1
```

**最後のターンの状態で判定する。** ターンが始まるたびに `task_started` が足されるので、3種の行のうち最後のものを見れば、初回でも差し戻しでも今のターンの状態が分かる。数を数えて送信の前後で比べる必要はない。

```bash
jq -rs '[.[] | select(.type == "event_msg" and (.payload.type | IN("task_started", "task_complete", "turn_aborted")))] | last | .payload.type' "<ログのパス>"
```

- `task_complete`: 終わった。報告を回収する（下記）
- `task_started`: まだ作業中。もう一度 `tui-idle` で待つ
- `turn_aborted`: 却下か中断で終わった。報告は回収しない。ログに残る最後の `task_complete` は前のターンの報告である

## 承認を求められたとき

承認を待っている間は、`terminal show --json` の `title` が `[ ! ] Action Required | …` に変わり、`agentWait.reason` が `agent-interactive-prompt` になる。何を求められているかは `terminal read` の末尾に出る（コマンド、理由、選択肢）。承認はユーザーが Orca の画面で答える。ディレクターは代行しない（`execution.md`）。

却下は `terminal send --text $'\e'` で送れる。実行ログには `turn_aborted` が残る。**却下の後も `agentWait` は立ったまま残った。** 承認待ちかどうかは `title` と画面の末尾で判断し、`agentWait` が消えたかどうかでは判断しない。

## 報告を回収する

**報告は画面から読まず、実行ログから取る。** `terminal read` は既定で PTY の生の出力を返し、TUI の再描画の断片（`WorkWorkWork…`、プロンプト行の繰り返し）が報告の行に混ざる。`--screen` を付ければ描画された画面を読めるが、画面に収まる分しか取れない。実行ログの `task_complete.last_agent_message` は、Codex の最終メッセージを改行を保ったまま全文で持っている。

```bash
jq -rs 'map(select(.payload.type=="task_complete")) | last | .payload.last_agent_message' "<ログのパス>"
```

差し戻しを重ねたスレッドでは `task_complete` が複数行になるので、上の例のとおり最後のものを読む。読むのは、最後のターンの状態が `task_complete` だったときだけである。報告の中身を信用しないこと、検収は `git diff` で行うことは他のランナーと同じである（`execution.md`・`review.md`）。

**起動引数が効いたかも実行ログで確かめる。** `turn_context` に、実際に当たった `model`・`effort`・`approval_policy`・`approvals_reviewer`・`sandbox_policy` が載る。消費は `token_count` の `info.total_token_usage` で見る。週次の残量は TUI の `/status` で見る。

## 片付ける

終わったら、自分が作ったターミナルだけを `terminal close --terminal <handle>` で閉じる。**`ok: false`（`terminal_stop_unverifiable`）が返っても、タブは消えていて、プロセスも終わっていた**（3回とも同じ）。閉じ直したり、別のホストに向けて再試行したりしない。`terminal list` から消えたことと、`pgrep -f` で起動コマンドが残っていないことを確かめて終える。

この文書の挙動は Orca 1.4.210 / Codex 0.156.1 で実測した（`evidence.md`）。worktree の手順は Orca 1.4.217、`tui-idle` での完了待ちは Orca 1.4.219 で確かめた。
