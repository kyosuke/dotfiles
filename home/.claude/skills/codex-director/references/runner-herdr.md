# 委任ランナー: herdr

`HERDR_ENV` が 1 のときに読む。Codex 側の運用（依頼文の渡し方、承認の境界、並列の可否、ネットワーク、スレッドの片付け）はランナーに依らないので `execution.md` にある。

**herdr の操作は公式スキルに従う。** Skill ツールで `herdr` を呼ぶ（無ければ `herdr --skill` が同じ内容を出力する。バイナリが出力元なので本体の更新に追従する）。公式スキルの description は「ユーザーが herdr に言及したときだけ使う」と制限しているが、この委任経路は herdr のペイン操作そのものなので対象に入る。

ペインの分割、エージェントの起動と発注、状態の意味、読み取り源の選び方、閉じてよい範囲は公式スキルにある。ここには書かない。読まずに想像で補わない。

この Skill からの上書きは4点だけである。

- **Codex は `--no-alt-screen` で起動する。** 付けないと出力が代替画面から出てスクロールバックへ入らず、報告を回収できない（実測で0行）。公式スキルはこの状態のときファイル出力へ切り替える手を挙げるが、最初の依頼文でファイル出力を求めない。回収の失敗は起動フラグで消す。
- **分割方向は右を優先する。** 公式スキルは「横に広ければ右、縦に長ければ下」と書くが、ユーザーの環境は横方向に余裕があり、左右に並べるほうが読みやすいという指定である。分割後の幅が80桁を下回るなら下へ切り替える（81桁でも TUI は崩れず報告も欠落しなかった実測がある）。
- **2つ目以降のエージェントは、最初のエージェントペインを基準に下へ積む。** 右へ割り続けるとディレクターのペイン幅が削れる。幅は最初の分割で決まった値のまま維持されるので、80桁の判断は1回で済む。
- **書き込みを伴う委任を並列に出すときは worktree を作る。** 公式スキルは、ユーザーが明示しない限り worktree も別の作業ディレクトリも作らないとしているが、この Skill での並列化は worktree で行うとユーザーが指示している（2026-10-01）。分けてよい条件は `execution.md` にあり、当たらないなら公式スキルどおり同じタブに兄弟ペインを作る。

PRのブランチのために起動したペインを、マージまで残すことがあるなら記録する。マージ後に post-merge-cleanup が閉じる。`pane_id` は使い回されうるので、`herdr pane get <pane_id>` の `terminal_id` も一緒に書く。PRに関係しない調査では記録しない。

```bash
echo "<ブランチ名> herdr <pane_id> <terminal_id>" >> "$(git rev-parse --git-common-dir)/review-terminals"
```

Codex のネイティブ引数は `agent start` の `--` 以降から本体へ直接届く。プロファイルの値・`service_tier`・サンドボックスの設定はここで渡す。値を検証して弾く層が間に無いので、Codex が受理する値はそのまま使える。

## プロファイルを値で渡す

herdr にプロファイルの仕組みは無い。`../SKILL.md` で選んだプロファイルを、起動引数へ展開して渡す。

| プロファイル | herdr で渡す引数 |
|---|---|
| `dev-low` | `-m gpt-6-luna -c model_reasoning_effort=low -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-default` | `-m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-high` | `-m gpt-6.1-sol -c model_reasoning_effort=low -c service_tier=priority -c approvals_reviewer=auto_review` |
| `dev-xhigh` | `-m gpt-6.1-sol -c model_reasoning_effort=high -c service_tier=default -c approvals_reviewer=auto_review` |
| `dev-max` | `-m gpt-6-astra -c model_reasoning_effort=xhigh -c service_tier=default -c approvals_reviewer=auto_review` |

プロファイルの定義は `../SKILL.md` の表にある。プロファイルが変わったらこの表を直す。

表に無い推論量もそのまま渡せる。プロファイルから外れるときは理由を発注前報告へ書く（`ordering.md`）。

### `service_tier` の語彙

Fast は Codex の `service_tier` で、プロファイルの Fast 有りを `priority`、無しを `default` へ写す。値の語彙は [`codex-rs/core/config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json) にあり、オフを表す `default` はここにしか出てこない（`models_cache.json` は各モデルの対応ティア表で、語彙の一覧ではない）。オンに legacy の `fast` ではなく `priority` を渡す。対応ティアに無い値は警告つきでオフになるだけなので使わない。値を変えるならスキーマで語彙を確かめ、リクエスト本文まで読む（実測とその方法は `evidence.md`）。

`service_tier` は起動時に必ず明示する。TUI のトグルが `~/.codex/config.toml` へこのキーを書き戻すので、省くと対話セッションの状態が委任へ漏れる。

## worktree を分けて起動する

並列に出してよいかの判断、起点、依存物、検収、取り込みは `execution.md` にある。ここには herdr の手順だけを置く。

```bash
herdr worktree create --cwd "$PWD" --branch <タスク名> --base <起点> --label <タスク名> --no-focus
```

- `--base` は必ず付ける。省くと `HEAD` から作られる。ブランチ名が既存のローカルブランチと重なると、新しく作らずにそれをチェックアウトするので、タスクごとに新しい名前にする。
- 作られる場所は `worktrees.directory`（既定 `~/.herdr/worktrees`）配下の `<repo>/<branch-slug>`。
- worktree は元の repo の workspace とグループになった、新しい workspace として開く。エージェントは、返ってきた JSON の root pane で `agent start` する（ID は返り値から読み、予測しない）。そこは新しい workspace なので、上の分割方向の規則は当たらない。
- Git が repo の所有者を理由に拒んでも、`--trust-repository` で押し通さない（公式スキルの規則）。ユーザーへ伝える。

片付けは、エージェントを畳んでから、まず `--force` なしで行う（`execution.md`）。

```bash
herdr worktree remove --workspace <worktree の workspace ID>
git branch -d <タスク名>
```

変更が残っていると `worktree remove` は Git に拒まれて止まる。残った中身を `execution.md` の手順で確かめ、不要と判断できたときだけ `--force` を付けて消し直す。`worktree remove` は `git worktree remove` を呼ぶだけでブランチを残すので、消えたら続けてブランチを消す。worktree 側でコミットしていなければ、ブランチは起点と同じ位置にあるので `-d` で消える。`-d` が拒んだら、そのブランチに何か残っているので、`-D` に替えず中身を確かめる。`workspace close --group` は元の repo の workspace まで閉じるので使わない。

## ネットワークは起動時に開ける

`-c sandbox_workspace_write.network_access=true` を渡すと、**そのセッションだけ**ネットワークが通る。書き込み範囲は `workspace-write` のままなので、コマンド単位の昇格（サンドボックス外での実行）より露出が小さい。こちらを使い、昇格を既定にしない。

ループバックだけを開ける設定は無いので、外向きも同時に開く。運用の判断と `~/.codex/config.toml` を触らない理由は `execution.md`。

## 読み取り専用で起動できる

`-s read-only` が通る。調査だけを頼む発注と、収集役を同じ作業ツリーで並列に走らせる前提（`ordering.md`）はこのランナーで成立する。ネットワークは閉じるので、参照させたい一次資料は先にローカルへ落としてパスを渡す。
