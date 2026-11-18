---
name: things
description: Things 3 の ToDo を AppleScript で読み書きする。「今日のToDoを見せて」「Thingsに〜を追加して」「〜を完了にして」のように、Today リストの確認や ToDo の追加・完了を頼まれたときに使う。更新・削除にはまだ対応していない
---

# Things 3

同梱の AppleScript を osascript で実行し、出力をそのままユーザーへ取り次ぐ。

スクリプトは `scripts/` にある。以下の `$S` は `"$HOME/.agents/skills/things/scripts"` に置き換えて実行する。

## Today リストを見る

    osascript "$S/list-today.applescript"

1件ごとに `- 名前 [id: …]` の行と、あればプロジェクト（またはエリア）・期限・タグ・メモを字下げして出す。

## ToDo を追加する

    osascript "$S/add-todo.applescript" 名前 [メモ] [期限] [追加先]

- 名前だけが必須。途中の引数を飛ばすときは `""` を渡す（例: `osascript "$S/add-todo.applescript" "牛乳を買う" "" "" "今日"`）。
- 期限は `YYYY-MM-DD`。
- 追加先はプロジェクト名 → エリア名 → 組み込みリスト名の順に探す。組み込みリストは Things の表示言語の名前（日本語なら「今日」「いつか」など）。省略すると Inbox に入る。
- 追加先が見つからない・同じ名前の追加先が複数ある・期限が存在しない日付などのときは、ToDo を残さずにエラー終了する。メッセージをユーザーへ伝える。

## ToDo を完了にする

    osascript "$S/complete-todo.applescript" id

- id は「Today リストを見る」の出力にある `[id: …]` の値。名前しか分からないときは、先に Today リストを見て id を確かめる。
- id が見つからないときはエラー終了する。

## 権限

osascript から Things を操作するには、呼び出し元のアプリ（ターミナル、Claude Code、Codex など）に macOS のオートメーション権限（システム設定 → プライバシーとセキュリティ → オートメーション → Things3）が要る。初回は確認ダイアログが出て、許可されるまで止まる。拒否されていると `-1743` のエラーになるので、その旨をユーザーへ伝える。

Codex の sandbox の中では osascript が Things に接続できず、スクリプトの解釈で失敗する（`expressionがあるべきところですが“to”が見つかりました` など）。Codex から実行するときは、最初から sandbox 外での実行（権限の昇格）を求める。
