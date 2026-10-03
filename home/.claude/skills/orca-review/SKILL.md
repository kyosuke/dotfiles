---
name: orca-review
description: Orcaのターミナルで対話型のCodexを起動し、PRやブランチの差分をレビューさせる。ユーザーはOrcaの画面で進行を見られる。既定はgpt-6.1-sol・推論量high・read-only。「Orcaでレビューさせて」「Codexにレビューしてもらって」のような依頼で使う。
argument-hint: "[PR番号|ベースブランチ] [--model <model>] [--effort <effort>]"
allowed-tools: Bash(orca terminal *), Bash(orca worktree current*), Bash(gh pr view*), Bash(git diff*)
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

ユーザーが文章で「6.1 sol high」「astraのxhighで」のように指定したら、それも上書きとして扱う。モデル名は`grep -oE '"gpt-[^"]+"' ~/.codex/models_cache.json | sort -u`で確かめ、無い名前なら起動前にユーザーへ伝える。

PR番号なら`gh pr view <番号> --json baseRefName,headRefName,title,body`でベースとブランチを得る。PRのブランチが手元でチェックアウトされていなければ、ユーザーに伝えて止まる。

## 2. 依頼文を作る

Codexは会話の文脈を持たない。依頼文だけで成立するように、次を書く。

- 対象: ブランチ名と、差分を見るコマンド（`git diff <base>...HEAD`）
- 変更の目的と内容: 会話やPR本文から2〜3文で。何を意図して何を変えたか
- 重点: この変更で壊れやすい点を具体的に挙げる。たとえば移動なら参照の切れ、統合なら事実の欠落、公式仕様に基づく記述なら出典との食い違い
- 固定の指示: 「ファイルは変更しないこと」「指摘は重大度順に、ファイル:行と根拠つきで日本語で。問題がなければそう言って」
- 手元で実行済みの検査: テストやlintを実行済みなら、その旨と結果を書く。read-onlyのCodexはsandboxの昇格を求めて止まるため、再実行させない

## 3. 起動して依頼を送る

```sh
orca terminal create --worktree active --title "review <対象>" \
  --command 'codex --model <model> -c model_reasoning_effort="<effort>" -s read-only' --json
```

返ってきた`handle`を以後すべてに使う。起動直後に依頼を送ると、まだ立ち上がっていないTUIに入力されて失われる。`orca terminal read --terminal <handle> --screen`の出力に`Ask Codex`が現れるまで、5秒おきに最大60秒待つ。起動コマンドを送り直さない。遅れて起動したCLIに、2回目の送信がプロンプトとして入力されてしまう。

依頼文は`orca terminal send --terminal <handle> --text "<依頼文>" --enter --wait-submit 10 --json`で送り、`accepted: true`を確かめる。

## 4. 待って結果を読む

```sh
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 560000 --json
orca terminal read --terminal <handle> --screen
```

`satisfied: false`なら画面を読み、状況を判断する。

- 権限の確認（`Would you like to run the following command?`）で止まっている: `--text $'\e'`でEscを送って断る。続けて「検査は手元で実行済みなので不要。調査を続けて結果を報告して」と送り、もう一度待つ
- まだ作業中: もう一度待つ

最終報告が画面に収まっていなければ、`--screen`を外して`--limit 400`で読む。

## 5. 取り次ぐ

指摘をそのまま並べず、1件ずつ実物や出典と照合してから、妥当かどうかを添えて報告する。修正するかの判断は、会話で決まっている方針に従う。決まっていなければユーザーに聞く。

ターミナルは、ユーザーが画面で見ているので、報告のあと`orca terminal close --terminal <handle>`で閉じてよい。
