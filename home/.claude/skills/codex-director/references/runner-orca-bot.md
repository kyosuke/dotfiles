# 委任ランナー: Orca bot

`ORCA_BOT_TOOLS_TOKEN` が空でないとき、つまり Orca の bot（`~/.orca/bots/<name>` で動く常駐エージェント）として動いているときに読む（判定の順は `../SKILL.md`）。トークンの値は表示も記録もしない。有無だけを `[ -n "${ORCA_BOT_TOOLS_TOKEN:-}" ]` で見る。

bot はユーザーの代わりに item（bot が持つ依頼の単位）を受けて動くので、発注前報告や `dev-max` の許可を会話で返事待ちにできない。そこで Codex の起動は `runner-orca.md` と同じくターミナルで行い、監督と報告の回収だけを Orca の Orchestration に任せる。

**次は `runner-orca.md` を読んで使う。** プロファイルを起動引数へ展開した表、`service_tier`・`approvals_reviewer` を明示する理由、`$ORCA_CODEX_HOME`、ネットワークの起動引数、`--base-branch` を付ける理由、承認待ちの見え方、`terminal close` の返り値。同じ内容をここへ写さない。Orchestration の操作そのものは公式ガイド（`orca skills get orchestration`、`--reference references/low-level-topology.md`）に従う。

## 対象外の作業

codex-director の対象はコードの調査・実装・検証である。文章の質が要る作業や Claude Code のスキルを使う作業は、Codex ではなく Claude の worker（通常の `orca orchestration worker-start --agent claude`）へ渡す。この Skill の手順は使わない。

## `runner-orca.md` と違うところ

`runner-orca.md` は Orchestration を使わない。`worker-start` の起動では Codex の起動引数を渡せないことと、報告が3文要約に縮むことが理由だった。bot ではどちらも次のように避ける。

- 起動は `terminal create --command` でプロファイルの起動引数ごと行い、できたターミナルを `worker-start --terminal` で監督下へ入れる（公式の low-level-topology の経路）。`--terminal` は `--model`・`--effort` と併用できないが、起動引数はすでに効いている。
- 報告の全文はファイルへ書かせ、`worker_done` の `--report-path` で受け取る。要約は `worker_done` の本文に載る。

完了の検知は Orca が `worker_done` で bot を起こすので、`tui-idle` で待たず、実行ログで終わったかを判定しない。

## 読み取り専用で起動しない

bot の経路では `-s read-only` を付けない。読み取り専用の Codex は `orca` CLI の呼び出しもサンドボックスで止められ、`worker_done` も `ask` も送れない。bot の chat から `dev-low` + `-s read-only` で試すと、worker は「`worker_done` が `runtime_access_denied` で拒否された」と出してターンを終え、Orca は `worker_done` の代わりに escalation（`stopReason: finished`）を bot へ送った（2026-11-22）。`runner-orca.md` の「読み取り専用で起動できる」は、報告を実行ログから取る経路の話で、ここには当てはまらない。

収集役やレビューを読み取りだけにしたいなら、依頼文で「ファイルを変更しない」と理由を添えて頼み、検収で `git -C <worktree> status --short` が空なのを確かめる。

## 起動する

起点を決めて worktree を作り、プロファイルの起動引数で Codex を立てる。ここまでの書き方と注意は `runner-orca.md` の「worktree を分けて起動する」「起動する」にある。

```bash
orca worktree create --name <タスク名> --no-parent --base-branch <起点> --setup skip --json
orca terminal create --worktree id:<result.worktree.id> --title <タスク名> --command '<プロファイルの codex 起動引数>' --json
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json
```

`--base-branch` はローカルの ref から作られる。`main` を渡したらローカルの `main` が起点になり、`origin/main` より古かった（2026-11-22）。最新から始めたいなら先に `git fetch` し、`origin/<ブランチ>` を渡す。

`tui-idle` が `satisfied: true` を返してから、依頼文を spec にして監督下へ入れる。

```bash
orca orchestration worker-start --environment local --spec-file <依頼文のファイル> --task-title <タスク名> --terminal <handle> --item <n> --json
```

- **`--task` も `task-create` も要らない。** `--spec-file`（または `--spec`）と `--terminal` だけで通り、Task と Run が作られて bot に結び付いた（返り値に `taskId`・`runId`・`runCreated: true`・`dispatchId`）。`task-create` 済みの Task を渡すなら `--task <id>` を使う。
- **依頼文は spec に書く。** Orca が worker 用の前置き（`ask`・`worker_done` の使い方）を付けて Codex へ送る。依頼文の組み方は `ordering.md` のまま。終わったら全文を worktree 内のファイルへ書き、そのパスを `--report-path` に付けて `worker_done` を送るよう依頼文の最後に書く。
- **`--item <n>` で bot の item に結び付く。** bot の chat から `--terminal` と併用して通り、`bot item show` で item に `dispatch:<id> · <タイトル> · working` として載り、item が In progress になり、イベントに `linked dispatch:<id>` が残った（2026-11-22）。bot 以外から付けると「Only a bot writes items」で拒否される。
- 返り値の `dispatchId` を控える。差し戻しの宛先になる。
- dispatch された worker（自分が worker として動いているとき）からは `--terminal` は拒否される（「A worker starts helpers in a new agent on this host」）。bot は coordinator なので当たらない。

起動したらターンを終える。待たない、ポーリングしない。Orca が `worker_done` か質問で bot を起こす。

## 質問と承認

worker からの質問は `question` として bot に届く。依頼文と item の内容から答えられるなら `orca orchestration reply --id <message_id> --body "<答え>"` で返す。答えられないなら item を Needs you にしてオーナーに聞き、返事を `reply` で渡す。

Codex の承認待ちは `runner-orca.md` の「承認を求められたとき」と同じに見える。代行しないことも同じで（`execution.md`）、item を Needs you にしてオーナーへ Orca の画面で答えてもらう。

## 報告を回収する

`worker_done` は本文（要約）と payload を持つ。`check` の表示は次のとおりで、`reportPath` はパスだけが載り、ファイルの中身は展開されない（2026-11-22）。

```text
msg_… worker_done from term_…
  <subject>
  <body>
  payload: taskId=… dispatchId=… outcome=succeeded reportPath=/…/report.md
```

全文はそのパスのファイルを bot が読む。`inbox --json` の簡易表示では payload から `outcome` と `reportPath` が落ち、`--full` を付けると載る。報告の中身を信用しないことは他のランナーと同じである。

## 検収と差し戻し

検収は bot が worktree で実際の差分とテストを読んで行う（`review.md`、パスの読み替えは `execution.md` の「worktree で並列に走らせる」）。

差し戻しは dispatch へ送る。

```bash
orca orchestration send --to dispatch:<dispatchId> --subject "<差し戻しの要点>" --body-file <差し戻し文のファイル>
```

終わった worker へ送ると follow-up の Task になり、新しい `dispatchId` が返る（`delivery: follow_up`）。同じターミナルの同じ Codex スレッドで続き、実行ログに2つ目のターンが足された（2026-11-22）。次の差し戻しは新しい `dispatchId` へ送る。修正依頼は2回までで、上限の扱いは `review.md`。

## 2段階で進める

1. **実装**: 上の手順で発注し、検収する。
2. **commit と PR**: 合格したら、同じ dispatch へ commit と PR 作成を指示する（`gh pr create --assignee @me`）。PR を出した worker がマージ可能になるまで（checks、レビュー対応）面倒を見るのは Orca の規約どおりである。

合格前に commit・PR を指示しない。

## オーナーとのやり取りは item に書く

- **発注前報告**（`../SKILL.md` のワークフロー4）と**最終報告**（同7）は item に書く。
- **`dev-max`** はオーナーの許可を item の Needs you で取ってから発注する。許可を諮る材料は `ordering.md`。

## 片付ける

外から渡したターミナルは、worker が終わっても閉じない（`terminalState: retained`）。`worker-release` も閉じなかった（`reason: external_terminal`、`processAction: none`）。途中で止めたいときも `worker-stop` では止まらず、`stop_unknown`（「The worker terminal is external; no terminal was closed.」）が返る。止めるのも閉じるのも `terminal close` で行う。PR を見届けたら `terminal close` で閉じ、worktree を消す（`runner-orca.md`）。`worktree rm` の後にブランチが残ることがあったので、`git branch --list` で確かめる（2026-11-22）。

この文書の挙動は Orca 1.4.269 / `gpt-6-luna` + `low` で実測した（`evidence.md`）。`--item` は bot の Home chat から確かめた。
