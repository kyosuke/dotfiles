# 委任ランナー: Orca

`ORCA_TERMINAL_HANDLE` が空でないときに読む（判定順は `../SKILL.md`）。共通手順は `execution.md`。Orca の操作は **`orca skills get orca-cli`** で本体と同じ版のガイドを読み、従う。`~/.agents/skills/orca-cli` は呼び出し案内で、Skill ツールには出ない。

## Orchestration を使わない

Codex の委任に `orca orchestration worker-start` は使わない。`--model` と `--effort` しか渡せず、`service_tier`・サンドボックス・ネットワークを指定できないうえ、`worker_done` の3文要約では報告全文を取れない。dispatch された worker は `worker-start --terminal` で既存ターミナルを監督下に入れることもできない（`evidence.md`）。

Codex は `terminal create --command` で起動引数ごと立ち上げ、プロファイルの値を起動引数に展開して渡す。

## プロファイルを値で渡す

| プロファイル | `--command` に書く Codex の起動 |
|---|---|
| `dev-low` | `codex -m gpt-6-luna -c model_reasoning_effort=low -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-default` | `codex -m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-high` | `codex -m gpt-6.2-sol -c model_reasoning_effort=low -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-xhigh` | `codex -m gpt-6.2-sol -c model_reasoning_effort=high -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-max` | `codex -m gpt-6.2-astra -c model_reasoning_effort=xhigh -c service_tier=default -c approvals_reviewer=auto_review` |

プロファイルの定義は `../SKILL.md` の表にある。プロファイルが変わったらこの表を直す。

Fast の値の語彙は `execution.md`。

`service_tier` は必ず明示する。Orca から起動した Codex の設定は `~/.codex` ではなく `$ORCA_CODEX_HOME`（`~/Library/Application Support/orca/codex-runtime-home/home`）にあり、`config.toml` はリンクではなく独立した複製である。`execution.md` と `recovery.md` が `~/.codex/config.toml`・`~/.codex/models_cache.json` と書いている箇所は、このランナーでは `$ORCA_CODEX_HOME` 配下のファイルを指す。実行ログ（`sessions/`）は `$ORCA_CODEX_HOME` 側にも `~/.codex` 側にも書かれたことがあるので、両方を探す（下記）。`recovery.md` の `f=$(ls -t ~/.codex/sessions/…)` は、このランナーでは `f=$(find "${ORCA_CODEX_HOME:-$HOME/Library/Application Support/orca/codex-runtime-home/home}/sessions" "$HOME/.codex/sessions" -name "rollout-*-$U.jsonl" 2>/dev/null | head -1)` に読み替える。UUID でファイルは1つに決まる。ディレクターのシェルでは `ORCA_CODEX_HOME` が空のことがあり、そのときは上の既定パスを使う。書き換えないという規則もこちらの複製に同じく当てはまる。

**`approvals_reviewer=auto_review` を明示する。** 省くと承認が人へ上がる（`evidence.md`）。`approval_policy` は既定の `on-request`。

表に無い推論量もそのまま渡せる。プロファイルから外れるときは、理由を発注前報告へ書く（`ordering.md`）。

## 起動する

```bash
orca terminal create --worktree active --title <タスク名> \
  --command 'codex -m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority -c approvals_reviewer=auto_review' --json
```

返った `result.terminal.handle` を宛先に使い、ログ特定用に起動時刻を控える。dispatch された worker で discoverable の警告が出ても起動は成功しており、`orca terminal focus --terminal <handle>`（`terminal switch` の別名）で解消する（`evidence.md`）。

PRのブランチのために起動したターミナルを、マージまで残すことがあるなら記録する。マージ後に post-merge-cleanup が閉じる。PRに関係しない調査では記録しない。

```bash
echo "<ブランチ名> orca <handle>" >> "$(git rev-parse --git-common-dir)/review-terminals"
```

- **読み取りだけの調査・並列収集は `-s read-only`。** 実行ログの `turn_context.sandbox_policy` で確認できる（`evidence.md`）。
- **ネットワークは `-c sandbox_workspace_write.network_access=true`。** 外向きとループバックが同時に開く。書き込み範囲と昇格の扱いは `execution.md`。
- `--no-alt-screen` は付けなくてよい。報告は画面から読まない（下記）ので、効き目が無い。

## worktree を分けて起動する

並列に出してよいかの判断、起点、依存物、検収、取り込みは `execution.md` にある。ここには Orca の手順だけを置く。ガイドの「Worktrees」の節も読む。

```bash
orca worktree create --name <タスク名> --no-parent --base-branch <起点> --setup skip --json
```

- **`--agent codex` は使わない。** Orca の既定ランチャーで起動するので、プロファイルの起動引数を渡せない。作ってから、返ってきた `result.worktree.id` を丸ごと `--worktree id:<…>` に渡して `terminal create` する。`id` は `<repoId>::<パス>` の形で、repo の ID だけに縮めない。
- **`--base-branch` は必ず付ける。** 省くと repo の既定ブランチから作られる。渡した名前はローカルの ref として解決する。最新から始めるなら先に `git fetch` し、`origin/<ブランチ>` を渡す（`evidence.md`）。
- **`--setup` は repo の `orca.yaml` に setup フックがあるかで決める。** あれば `run` で依存物を入れさせ、無ければ `skip` にして、インストールは依頼文で Codex に頼む（`execution.md`）。
- **最初に空のシェルが1つできる。** `startupTerminal` は `null` で返り、`terminal list` に fish のターミナルが1つ載っていた。`terminal list` で使われていないと確かめてから閉じる。
- 作られる場所は `~/orca/workspaces/<repo>/<タスク名>`、ブランチは `<ユーザーのプレフィックス>/<タスク名>` だった。パスとブランチは決め打ちにせず、返り値の `result.worktree.path` / `branch` を使う。

片付けは、その worktree のターミナルを閉じてから、まず `--force` なしで行う（`execution.md`）。

```bash
orca worktree rm --worktree id:<repoId>::<パス> --json
```

未コミットの変更が残ると `runtime_error`（`Failed to delete worktree …`）で止まる。`execution.md` に従い、不要と判断できたときだけ `--force` を付ける。削除後はブランチが残っていないか `git branch --list` で見る（`evidence.md`）。

## 依頼文を送る

最初の送信の前に、`terminal wait --for tui-idle` で入力待ちになったことを確かめる。`result.wait.satisfied: true` が返ってから送る。起動中の TUI へ打ち込んだ依頼文は失われる。

```bash
orca terminal send --terminal <handle> --text "$(cat <scratchpad>/order.txt)" --enter --wait-submit 20 --json
```

`result.send.prompt.stages` に `turn_started` が載っていれば、ターンが始まっている。載っていなくても送り直さない（ガイドの規則）。差し戻しも同じハンドルへ同じ形で送れば、同じスレッドが続く。

## 完了を待つ

**完了は `tui-idle` で待つ。** Bash の既定タイムアウト（120秒）を超えるため、`run_in_background: true` で待つ。複数ターミナルは以下のように待ち、総待機時間が40分を超えたら残りを待たない。

```bash
deadline=$(( $(date +%s) + 2400 ))
for h in handle1 handle2; do
  while :; do
    if [ "$(date +%s)" -ge "$deadline" ]; then echo "$h timeout"; break; fi
    out=$(orca terminal wait --terminal "$h" --for tui-idle --timeout-ms 560000 --json)  # ok:false は終了コード1
    state=$(printf '%s\n' "$out" | jq -er '
      if .ok == false and .error.code == "timeout" then "retry"
      elif .ok == false and (.error.code | type == "string") then "error " + .error.code
      elif .ok == true and .result.wait.satisfied == true then "idle"
      elif .ok == true and (.result.wait.blockedReason | type == "string") then "blocked " + .result.wait.blockedReason
      else empty end
    ' 2>/dev/null) || state=bad-output
    case "$state" in
      retry) continue ;;
      *) echo "$h $state"; break ;;
    esac
  done
done
```

`satisfied` と `blockedReason` は `result.wait` の下にある。`idle` なら実行ログで最後のターンを確認する。`blocked agent-interactive-prompt` は承認待ち（該当節）、`blocked agent-trust-workspace` は初回起動時のフォルダ信頼確認で、ユーザーに伝えて画面での回答を待ち、代行しない。待ち直すのは `ok: false` の `error.code: timeout` だけであり、`error terminal_exited` は `terminal read` または実行ログで最後のターンを確認し、`task_complete` なら報告回収へ進み、それ以外は状況を報告する。他の `error`、総待機時間の `timeout`、`bad-output` も状況を報告する。Bash ツールでは `run_in_background: true` で実行し、出力各行の `idle` は実行ログ確認、`blocked` は承認待ち/信頼確認、`error` は上記の確認、`timeout` は状況報告へ進む。

実行ログは、終わったことの確かめと報告の回収に使う。ログは `$ORCA_CODEX_HOME/sessions/<年>/<月>/<日>/rollout-*.jsonl` か `~/.codex/sessions/<年>/<月>/<日>/rollout-*.jsonl` にあり、ターンが始まると `event_msg` の `task_started` が、終わると `task_complete` が、却下や中断で終わると `turn_aborted` が1行ずつ足される。

**ログは依頼文の本文で特定する。** 最新のファイルを拾うと、並列に走っている別の Codex のログを掴む。依頼文の先頭行を含むファイルのうち、`turn_context.model` が `codex-auto-review` でないもので、名前（起動時刻が入っている）が最も新しいものを選ぶ。auto-reviewer は依頼文を含む自分のログを同じ起動時刻で書くので、名前だけで選ぶとそちらを掴む（2026-10-07、`task_complete` が審査結果の JSON だった）。同じ依頼文を出し直したときも、これで新しいほうに当たる。2か所を合わせて名前で比べるため、並べ替えはファイル名だけで行う。依頼文が書き込まれるのは送信の後なので、探すのは `tui-idle` が返ってからにする。ファイル名の UUID は `codex resume` にそのまま使える（`recovery.md`）。Bash の変数は呼び出しをまたいで残らないので、出たパスを以後のコマンドへそのまま書く。パスに空白が入るので、必ず引用符で囲む。

```bash
KEY=$(head -1 <scratchpad>/order.txt | cut -c1-60)
D=$(date +%Y/%m/%d)
find "${ORCA_CODEX_HOME:-$HOME/Library/Application Support/orca/codex-runtime-home/home}/sessions/$D" "$HOME/.codex/sessions/$D" \
  -name 'rollout-*.jsonl' -exec grep -lF "$KEY" {} + 2>/dev/null |
  awk -F/ '{print $NF "\t" $0}' | sort | cut -f2- | while read -r f; do
  jq -e -s 'map(select(.type=="turn_context")) | last | .payload.model != "codex-auto-review"' "$f" >/dev/null && echo "$f"
done | tail -1
```

**最後のターンの状態で判定する。** 初回も差し戻しも、3種のイベントの最後の1件を読む。

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

最後のターンが `task_complete` のときだけ、上の例で最新の報告を取る。検収は `review.md` に従う。

**起動引数が効いたかも実行ログで確かめる。** `turn_context` に、実際に当たった `model`・`effort`・`approval_policy`・`approvals_reviewer`・`sandbox_policy` が載る。消費は `token_count` の `info.total_token_usage` で見る。週次の残量は TUI の `/status` で見る。

## 片付ける

自分が作ったターミナルだけを `terminal close --terminal <handle>` で閉じる。`ok: false`（`terminal_stop_unverifiable`）でも閉じられていることがある（`evidence.md`）。閉じ直したり別ホストで再試行したりせず、`terminal list` と `pgrep -f` でタブと起動コマンドが消えたことを確かめる。
