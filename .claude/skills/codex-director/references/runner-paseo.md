# 委任ランナー: Paseo

`PASEO_CLI` が空でないときに読む。herdr で動いているなら `runner-herdr.md` を読み、このファイルは開かない。Codex 側の運用（依頼文の渡し方、承認の境界、並列の可否、ネットワーク、スレッドの片付け）はランナーに依らないので `execution.md` にある。

自分自身も Paseo のエージェントとして動いているので、ここで作る Codex は同じワークスペースのサブエージェントになる（Paseo が `PASEO_AGENT_ID` で親を判定する）。サブエージェントは親の画面の Subagents track に出る。

経路は2つあり、**MCP ツールが見えているなら MCP を使う。** プロファイルの値（とくに Fast）をそのまま渡せる唯一の経路である。CLI は MCP ツールが見えないセッション（`daemon.mcp.injectIntoAgents` を有効にする前に起動したもの）の代替で、Fast が落ちる。

## MCP で委任する

操作の詳細は Paseo 公式の `paseo` スキル（Skill ツールの `paseo`）にある。ここには対応だけを置く。

| 操作 | ツール | 備考 |
|---|---|---|
| プロファイルを読む | `list_profiles` | `notes` を見て選ぶ。`create_agent` に `profile` パラメータは無いので、値を写す |
| 起動と発注 | `create_agent` | `provider` に `codex/<model>`、`settings.modeId` / `settings.thinkingOptionId` / `settings.features` にプロファイルの `modeId` / `thinkingOptionId` / `featureValues`。`initialPrompt` に依頼文の全文。`workspaceId` を省くと自分のワークスペースのサブエージェントになる |
| 完了待ち | 完了通知（`notifyOnFinish`、既定で有効） | 完了・エラー・承認待ちのいずれかで届く。待たずに自分でポーリングしない |
| 状態の確認 | `get_agent_status` | 通知が来ないときや、差し戻し前に待機状態かを確かめるとき |
| 報告回収 | `get_agent_activity` | 最新の活動から返るので `limit` を報告の長さに合わせて取る |
| 差し戻し | `send_agent_prompt` | 同じスレッドが続く。`background` は既定の `true` のままにし、完了通知を待つ |
| 承認要求の確認 | `list_pending_permissions` | 何を求められているかを読んでユーザーへ伝える。`respond_to_permission` で allow を送らない（`execution.md`） |
| 片付け | `archive_agent` | ソフト削除。ハード削除は使わない（下記） |

依頼文はファイルへ書いてから、その内容を `initialPrompt` へ入れる（理由は `execution.md`）。

## CLI で委任する（MCP が見えないとき）

CLI は `$PASEO_CLI` にある（PATH には載っていない）。手順は[公式のオーケストレーション例](https://paseo.sh/docs/cli)に従い、CLI に無い操作を自前で組まない。

```bash
P="$PASEO_CLI"

# 起動と発注（依頼文はファイルへ書いてから渡す。--quiet は ID だけを返す）
A=$("$P" run "$(cat <scratchpad>/order.txt)" \
  --provider codex/<モデルID> --thinking <推論量> --mode auto-review \
  --cwd "$PWD" --background --quiet)

# 完了待ちと報告回収
"$P" wait "$A" --timeout 1800 --json
"$P" logs "$A" --filter text --tail 50

# 差し戻し（同じスレッドが続く。既定で完了まで待つ）
"$P" send "$A" --prompt-file <scratchpad>/order-2.txt --json

# 承認要求の確認（allow は代行しない）
"$P" permit ls

# 片付け
"$P" archive "$A" --json
```

`run` の依頼文は位置引数なので `"$(cat <path>)"` で渡す。コマンド置換の出力はシェルに読み直されないため、バックティックを含む依頼文も欠けずに届く。

**CLI では Fast を指定できない。** `paseo run` にも `agent update` にも `fast_mode` を触るフラグが無く、`~/.codex/config.toml` の `service_tier` が効く（実測では `default` = オフ）。依頼文に `/fast` と書いても効かない（Paseo が起動するのは `codex app-server` で、スラッシュコマンドを解釈しない）。CLI で出す発注では、Fast が落ちることを発注前報告へ1行添える。Codex のネイティブ引数（`-c` 相当）も渡せない。経緯と退けた代替（SDK の `providerOptions`）は `evidence.md`。

**推論量は `none` も通る。** `paseo provider models codex --json` の `thinkingOptionIds` は `low` 以上しか載せないが、CLI は値を検証せずに渡す。

**`--mode` は省かない。** プロバイダの既定は `auto-review` だが、エージェントの中から `paseo run` した実測では `auto` になった。

**週次の残量は CLI から引けない。** `dev-max` の許可を諮るときは、消費を `paseo inspect <agentId> --json` の `LastUsage` で示し、残量はユーザーにアプリで見てもらう。

コマンドの形が食い違ったら想像で補わず `"$PASEO_CLI" <コマンド> --help` を引く。

## 両経路に共通する制約

**モードは3つで、読み取り専用が無い。** 当たる値はデーモンの `MODE_PRESETS` にある。

| モード | `approval_policy` | `sandbox_mode` | 備考 |
|---|---|---|---|
| `auto` | `on-request` | `workspace-write` | |
| `auto-review` | `on-request` | `workspace-write` | `approvals_reviewer: auto_review` が付く。プロファイルの既定 |
| `full-access` | `never` | `danger-full-access` | 使わない（`execution.md`） |

`read-only` のプリセットは内部に存在するが公開されておらず、指定すると弾かれる（`Invalid mode 'read-only' for provider 'codex'`）。調査だけを頼むときに書き込みを止める手段が依頼文の指示だけになるので、収集役を同一作業ツリーで並列に走らせる前提（`ordering.md`）はこのランナーでは崩れる。並列に走らせたいなら worktree で分ける（CLI は `--new-workspace worktree`、MCP は `create_workspace`）。

**ネットワークは昇格で取る。** `auto-review` のまま、依頼文で `sandbox_permissions: require_escalated` の要求を許せば、そのコマンドだけがサンドボックス外で走る。可否は auto-reviewer が決め、`paseo permit` にもアプリにも出ない（運用は `execution.md`）。

**片付けはソフト削除で行う。ハード削除（CLI の `delete`）を使わない。** アプリがタブで開いているエージェントをハード削除すると、アプリが消えたIDへ更新要求を投げ続けてタブが閉じられなくなる（Paseo 0.8.0 で発生、再起動で復帰）。公式ドキュメントが片付けとして挙げているのも `stop` と archive である。

**画面への出し方。** CLI の `agent open <agentId>` はタブとして開くだけで、置く位置は指定できない。ペインや分割を操作するコマンドは無い。

**ユーザーが見る画面とディレクターが読むログは別経路である。** ユーザーが見るのはアプリのUI、ディレクターが読むのは `get_agent_activity` か `paseo logs` になる。画面に出ていた内容を読んだつもりで報告しない。

この節は Paseo 0.8.0 と Codex 0.153.4 / 0.154.0 で実測し、[公式ドキュメント](https://paseo.sh/docs/cli)と[リポジトリ](https://github.com/getpaseo/paseo)で裏を取った（`evidence.md`）。
