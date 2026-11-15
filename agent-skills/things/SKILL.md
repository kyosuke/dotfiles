---
name: things
description: Things 3 の ToDo を AppleScript で読み書きする。「今日のToDoを見せて」「Thingsに〜を追加して」のように、Today リストの確認や ToDo の追加を頼まれたときに使う。完了・更新・削除にはまだ対応していない
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
- 追加先が見つからない、期限の形式が違うなどのときは、ToDo を残さずにエラー終了する。メッセージをユーザーへ伝える。

## 権限

osascript から Things を操作するには、呼び出し元のアプリ（ターミナル、Claude Code、Codex など）に macOS のオートメーション権限（システム設定 → プライバシーとセキュリティ → オートメーション → Things3）が要る。初回は確認ダイアログが出て、許可されるまで止まる。拒否されていると `-1743` のエラーになるので、その旨をユーザーへ伝える。
