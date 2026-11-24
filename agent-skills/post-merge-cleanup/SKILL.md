---
name: post-merge-cleanup
description: PRマージ後の後処理。デフォルトブランチに戻してpullし、マージ済みなら不要になったローカルブランチを削除する。未マージなら削除せずユーザーに知らせる
---

# マージ後の後処理

cleanup.sh を実行し、出力をユーザーへ取り次ぐ。判断は全てスクリプト側にあるので、Codexは実行と報告だけを担う。

対象ブランチの指定がある場合は、次のように引数として渡す。指定がなければ、スクリプトが現在のフィーチャーブランチを対象にする。本体のworktreeでデフォルトブランチ上にいて引数もない場合は、マージ済みのローカルブランチをまとめて片付ける。

    bash "$HOME/.agents/skills/post-merge-cleanup/cleanup.sh" [対象ブランチ]

角括弧は記法上のプレースホルダーなので、対象ブランチがない場合は省略する。

## なぜスクリプトなのか

マージ判定、squash/rebaseマージの見分け、upstream先行で -d が拒否るケースの切り分けは分岐が細かい。外したときの損失が未pushコミットの消失なので、指示の遵守に委ねず決定表をスクリプトへ置いた。-D（強制削除）と stash はスクリプトに存在しないため、そもそも実行され得ない。

## worktreeで実行したとき

linked worktreeではデフォルトブランチへ切り替えられないので、`origin` をfetchして `origin/<default>` と比べる。取り込み済みなら `origin/<default>` へdetachして `-d` し、消せたらworktreeも削除する（Orcaが管理するworktreeは `orca worktree rm` で、そのワークスペースと中のセッションごと閉じる）。報告はその前に出し終える。本体側のデフォルトブランチはpullしない。

次のときはworktreeを残して止まる: ブランチを消せなかった（未マージ、squash/rebaseマージ、upstreamへ未push）、HEADが `origin/<default>` に含まれない、作業ツリーに変更がある、rebase・merge・bisectなどの途中。worktreeでは、そこでチェックアウトしているブランチ以外は引数で指定できない。`-d` を拒否されたときは元のブランチへ戻す。git管理外でも、ignoredのファイル（`node_modules`、`.env` など）はworktreeと一緒に消える。ブランチを付けずにdetachしたまま作ったコミットも、worktreeのreflogにしか残っていなければ一緒に消える。

squash/rebaseマージで `-D` の許可を得たら、worktree内で `git checkout --detach origin/<default>` → `git branch -D <ブランチ>` を実行し、引数なしでスクリプトを再実行するとworktreeが削除される。

## レビュー用ターミナルの片付け

PRのためにOrcaのターミナルやherdrのペインを開いた側は、`$(git rev-parse --git-common-dir)/review-terminals` に1行追記する。

    <ブランチ> orca <handle>
    <ブランチ> herdr <pane_id> <terminal_id>

スクリプトは、マージを確認できたブランチの行と、ローカルにもリモート追跡参照（prune後）にもないブランチの行（先に手で消した等）を読み、まだ生きているものを閉じて行を消す。herdrの `pane_id` は使い回されうるので、`terminal_id` も一致したときだけ閉じる。閉じたものは「閉じたレビュー用ターミナル」の行で報告される。記録の形を変えるときは、追記する側（orca-review、codex-directorのランナー）も直す。

## 終了コードの扱い

| コード | 意味 | Codexの動き |
|---|---|---|
| 0 | 完了 | 出力をそのまま報告する |
| 2 | 前提を満たさず着手しなかった（作業ツリーが汚れている、対象のブランチも記録も見つからない等） | stderrの理由を伝え、指示を仰ぐ |
| 3 | 途中で失敗した（切り替え、--ff-only の失敗など） | stderrの理由を伝えて止まる。ブランチは削除されていない（worktreeの削除だけが失敗したときは、ブランチは削除済みでworktreeがdetachしたまま残る） |
| 4 | 削除しなかったブランチがある。対象が未マージ（PRがMERGEDでもない）なら、デフォルトブランチへ切り替えずに元のブランチのまま止まる（worktreeでは、worktreeを削除しなかった場合も） | 出力の「未削除」の行をそのまま伝える。worktreeを削除しなかった理由はstderrの `STOP:` 行に出るので、それも伝える |

-D が要る状況（squash/rebaseマージ）は終了コード4で報告される。Codexが代わりに -D を打たない。ユーザーへ可否を尋ね、明示的な指示があったときだけ実行する。
