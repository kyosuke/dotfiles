---
name: orca-review
description: Orcaのターミナルで対話型のCodexを起動し、PRやブランチの差分をレビューさせる。ユーザーはOrcaの画面で進行を見られる。既定はgpt-6.1-sol・推論量high・read-only。「Orcaでレビューさせて」「Codexにレビューしてもらって」のような依頼で使う。
argument-hint: "[PR番号|ベースブランチ] [--model <model>] [--effort <effort>]"
allowed-tools: Bash(orca terminal *), Bash(gh pr view*), Bash(grep *), Bash(jq *), Bash(echo *)
---

# Orcaでのレビュー

Orcaのターミナルで対話型のCodexを起動し、レビューを依頼して結果を取り次ぐ。`codex exec`や`codex review`をBashで実行する方法は使わない。前者は許可されず、後者は独自のレビュー観点を受け付けない。ターミナルで動かせば、ユーザーがOrcaの画面で進行を見られる。

## 1. 引数を読む

`$ARGUMENTS`から次を取り出す。

| 引数 | 既定値 |
|---|---|
| `--model <model>` | `gpt-6.1-sol` |
| `--effort <effort>` | `high` |
| 対象（PR番号かベースブランチ） | 現在のブランチを`main`と比べる |

ユーザーが文章で「6.1 sol high」「astraのxhighで」のように指定したら、それも上書きとして扱う。モデル名は`grep -oE '"gpt-[^"]+"' "${ORCA_CODEX_HOME:-$HOME/Library/Application Support/orca/codex-runtime-home/home}/models_cache.json" | sort -u`で確かめ、無い名前なら起動前にユーザーへ伝える。OrcaのCodexは`~/.codex`ではなく、このOrca専用のホームを使う。

PR番号なら`gh pr view <番号> --json baseRefName,headRefName,title,body`でベースとブランチを得る。PRのブランチが手元でチェックアウトされていなければ、ユーザーに伝えて止まる。

## 2. 依頼文を作る

Codexは会話の文脈を持たない。依頼文だけで成立するように、次を書く。

- 対象: ブランチ名と、差分を見るコマンド（`git diff <base>...HEAD`）
- 変更の目的と内容: 会話やPR本文から2〜3文で。何を意図して何を変えたか
- 重点: この変更で壊れやすい点を具体的に挙げる。たとえば移動なら参照の切れ、統合なら事実の欠落、公式仕様に基づく記述なら出典との食い違い
- 固定の指示: 「ファイルは変更しないこと」「sandboxで実行できない検査は試さず、未検証として報告して」「指摘は重大度順に、ファイル:行と根拠つきで日本語で。問題がなければそう言って」
- 手元で実行済みの検査: テストやlintを実行済みなら、その旨と結果を書く。再実行させない
- 末尾に`review-id: <handle>`: 手順4で実行ログを探す目印にする

## 3. 起動して依頼を送る

```sh
orca terminal create --worktree active --title "review <対象>" \
  --command 'codex --model <model> -c model_reasoning_effort="<effort>" -s read-only -a never' --json
```

`-a never`で、sandboxの外で動かすコマンドは承認を求めずに失敗として返る。権限の確認で止まらなくなる。

マージ後にpost-merge-cleanupが閉じられるよう、レビューされる側のブランチ名（PRなら`headRefName`、それ以外は現在のブランチ）と`handle`を記録する。ベースブランチの名前を書かない。

```sh
echo "<ブランチ名> orca <handle>" >> "$(git rev-parse --git-common-dir)/review-terminals"
```

返ってきた`handle`を以後すべてに使う。起動直後に依頼を送ると、まだ立ち上がっていないTUIに入力されて失われる。`orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json`で待ち、`satisfied: true`を確かめてから送る。起動コマンドを送り直さない。遅れて起動したCLIに、2回目の送信がプロンプトとして入力されてしまう。

依頼文は引用符付きのヒアドキュメントで渡す。依頼文に入るバッククォートや`$`、`"`をシェルに解釈させないため。

```sh
orca terminal send --terminal <handle> --text "$(cat <<'EOF'
<依頼文>
EOF
)" --enter --wait-submit 10 --json
```

`result.send.prompt.stages`に`turn_started`があるかを確かめる。`accepted: true`は入力を受け付けたことしか示さない。`turn_started`が無ければ`--screen`で画面を読み、依頼文が入力欄に残っていれば`orca terminal send --terminal <handle> --enter`で送信する。

## 4. 待って結果を読む

完了は`tui-idle`で待つ。Bashツールの既定タイムアウト（120秒）を超えるので、Bashの`timeout`に`600000`を指定する。

```sh
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 560000 --json
```

報告はCodexの実行ログから読む。画面は収まる分しか読めず、`--screen`を外すと再描画の断片が混ざる。依頼文に入れた目印でログを探し、最後のターンを見る。完了していれば報告の全文が、そうでなければ`未完了: <状態>`が出る。

```sh
grep -rlF 'review-id: <handle>' "${ORCA_CODEX_HOME:-$HOME/Library/Application Support/orca/codex-runtime-home/home}/sessions"
jq -rs '[.[] | select(.type == "event_msg" and (.payload.type | IN("task_started", "task_complete", "turn_aborted")))] | last | .payload | if .type == "task_complete" then .last_agent_message else "未完了: " + .type end' "<ログのパス>"
```

- `未完了: task_started`: まだ作業中。もう一度`wait`で待つ
- `未完了: turn_aborted`: 中断された。`orca terminal read --terminal <handle> --screen`で画面を読み、状況をユーザーに伝える

## 5. 取り次ぐ

指摘をそのまま並べず、1件ずつ実物や出典と照合してから、妥当かどうかを添えて報告する。修正するかの判断は、会話で決まっている方針に従う。決まっていなければユーザーに聞く。

ターミナルは、ユーザーが画面でやり取りを読み返せるように閉じずに残す。マージ後はpost-merge-cleanupが手順3の記録から閉じる。それより前にユーザーに言われたら`orca terminal close --terminal <handle>`で閉じる。
