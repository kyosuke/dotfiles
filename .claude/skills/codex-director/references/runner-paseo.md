# 委任ランナー: Paseo

`PASEO_CLI` が空でないときに読む。herdr で動いているなら `runner-herdr.md` を読み、このファイルは開かない。Codex 側の運用（承認の境界、並列の可否、スレッドの片付け）はランナーに依らないので `execution.md` にある。

## 操作の対応

ランナーが違っても骨格は同じで、満たすべき条件も変わらない。

| 操作 | 満たすこと |
|---|---|
| 起動 | モデルと推論量を明示し、作業ツリーを指定する。既定値へ落とさない |
| 発注 | 依頼文をファイル経由で渡す。シェルに評価させない |
| 完了待ち | ランナーが返す状態で判定する。自前のポーリングを既定にしない |
| 報告回収 | 報告の全文を取る。画面に見えた範囲で済ませない |
| 承認 | 代行せず、何を求められているかをユーザーへ伝える |
| 片付け | 自分が作ったエージェントだけ畳む |

CLI は `$PASEO_CLI` にある（PATH には載っていない）。自分自身も Paseo のエージェントとして動いているので、ここで作る Codex は同じワークスペースのサブエージェントになる（Paseo が `PASEO_AGENT_ID` で親を判定する）。

手順は[公式のオーケストレーション例](https://paseo.sh/docs/cli)に従う。CLI に無い操作を自前で組まない。

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

**プロファイルは MCP 経由でしかそのまま渡せない。** Paseo の MCP ツールが見えているなら、`list_profiles` で読んで `create_agent` へ材料化する。操作の詳細は Paseo 公式の `paseo` スキルにある（Skill ツールの `paseo`）。

| プロファイルの項目 | `create_agent` での渡し先 |
|---|---|
| `provider` + `model` | `provider`（`codex/gpt-5.6-luna`） |
| `modeId` | `settings.modeId` |
| `thinkingOptionId` | `settings.thinkingOptionId` |
| `featureValues` | `settings.features` |

`create_agent` に `profile` パラメータは無い。MCP ツールが見えないセッション（`daemon.mcp.injectIntoAgents` を有効にする前に起動したもの）では下記の CLI を使い、Fast が落ちることを発注前報告へ書く。

`run` の依頼文は位置引数なので `"$(cat <path>)"` で渡す。コマンド置換の出力はシェルに読み直されないため、バックティックを含む依頼文も欠けずに届く。差し戻しの `send` には `--prompt-file` がある。

**片付けは `archive`（ソフト削除）で行う。`delete` を使わない。** ハード削除したエージェントをアプリがタブで開いていると、アプリが消えたIDへ `update_agent_request` を約2秒おきに投げ続け、`Agent not found` で失敗し、タブが閉じられなくなる（2026-09-12、Paseo 0.8.0 で発生。アプリの再起動で復帰した）。公式ドキュメントが片付けとして挙げているのも `stop` と archive で、`delete` は勧めていない。

**作業を画面に出すのは `"$P" agent open <agentId>`。** タブとして開くだけで、置く位置は指定できない。Paseo の CLI にペインや分割を操作するコマンドは無いので、herdr のように右へ並べたいならユーザーがアプリ側で行う。開かなくても、サブエージェントは親の画面の Subagents track に出る。

**ユーザーが見る画面とディレクターが読むログは別経路である。** herdr はどちらも同じペインの画面を見ていたが、Paseo であなたが見るのはアプリのUI、ディレクターが読むのは `paseo logs` になる。`--quiet` や `--json` が変えるのは `run` の標準出力だけで、作業の見え方には影響しない。画面に出ていた内容を読んだつもりで報告しない。

**Codex のネイティブ引数を渡せない。** `paseo run` に `-c` 相当のフラグは無い。デーモンのAPIには `providerOptions` があり、Codex 向けに `approval_policy` / `sandbox_mode` / `sandbox_workspace_write.*` / `web_search` / `features.*` を受け付けるが（[providers.md](https://github.com/getpaseo/paseo/blob/main/docs/providers.md)）、CLI はこれを渡す口を持たない。スキーマは strict で `service_tier` を含まないので、Fast はどのみち指定できない。

`providerOptions` を渡せるのは TypeScript SDK の `agents.create` だけである（[provider options](https://paseo.sh/docs/sdk/provider-options)）。渡すとモードのプリセットを上書きし、`sandbox_mode: "workspace-write"` + `sandbox_workspace_write.network_access: true` のように権限を刻める。ただしこの経路は使わない。ネットワークはコマンド単位の昇格で取れるので（下記）、SDK ラッパーを挟む理由が無い。

**Fast は `fast_mode` という機能値で、CLI からは触れない。** Paseo は Codex の Fast をエージェント単位の機能として持つ（[codex-feature-definitions.ts](https://github.com/getpaseo/paseo/blob/main/packages/server/src/server/agent/providers/codex-feature-definitions.ts)。Codex 側の機能定義は `fast_mode` と `plan_mode` の2つだけで、ネットワークやサンドボックスはここに無い）。`paseo run` にも `agent update` にもこれを指定するフラグが無いので、CLI で出すと `~/.codex/config.toml` の `service_tier` が効く。渡せるのは MCP の `create_agent`（`settings.features`）とアプリの画面である。

**依頼文へ `/fast` と書いても効かない。** Paseo が起動するのは `codex app-server` で、TUI のスラッシュコマンドを解釈しない。`/status` も `/fast` も普通のテキストとして読まれ、Codex は会話として返す（「高速モードです。」と答えたが何も切り替わらず、`~/.codex/config.toml` も変わらなかった。2026-09-12実測）。起動状態を見て送り込む手は使えない。

起動時の既定は `~/.codex/config.toml` の `service_tier` で、実測では `default`（オフ）のまま `luna` が動いた。`ordering.md` の「`luna` は Fast オン」はこのランナーでは自動的には効かない。config.toml は書き換えず、モデルと推論量だけを調整する（2026-09-11、ユーザーからの指示）。Fast が要る発注では、現状を発注前報告へ1行添え、アプリ側でトグルするかをユーザーに決めてもらう。

**推論量は `none` も通る。** `paseo provider models codex --json` の `thinkingOptionIds` は `low` 以上しか載せないが、CLI は値を検証せずに渡す。`--thinking none` で作ったエージェントは Codex のセッションへ `effort = "none"` として届いた（2026-09-12、rollout ログの `turn_context` で確認）。段の一覧（`ordering.md`）はそのまま使える。カタログに無いぶん Paseo のUIからは選べない。

**モードは3つで、読み取り専用が無い。** 当たる値はデーモンの `MODE_PRESETS` にある（Paseo 0.8.0 のバンドルで確認）。

| `--mode` | `approval_policy` | `sandbox_mode` | 備考 |
|---|---|---|---|
| `auto` | `on-request` | `workspace-write` | |
| `auto-review` | `on-request` | `workspace-write` | `approvals_reviewer: auto_review` が付く。プロファイルの既定 |
| `full-access` | `never` | `danger-full-access` | 使わない（下記） |

`read-only` のプリセットは内部に存在するが（`on-request` + `read-only`）、マニフェストの公開モード3つと照合する検証で弾かれる（`Invalid mode 'read-only' for provider 'codex'`）。調査だけを頼むときに書き込みを止める手段が依頼文の指示だけになるので、収集役を並列に走らせる前提（`ordering.md`）はこのランナーでは崩れる。同一作業ツリーで並列に走らせたいなら `--new-workspace worktree` で分ける。

**`--mode` は省かない。** プロバイダの既定は `auto-review` だが、エージェントの中から `paseo run` した実測では `auto` になった。どちらが効くかを起動時に確定させる。

**ネットワークは昇格で取る。`--mode full-access` は使わない。** `auto-review` のまま、依頼文で `sandbox_permissions: require_escalated` の要求を許せば、そのコマンドだけがサンドボックス外で走る。可否は `approvals_reviewer: auto_review` のサブエージェントが決め、`paseo permit` にもアプリにも出ない。auto-reviewer に任せ、承認を人へ上げ直す設定変更は提案しない。

`full-access` を選ばないのは、ネットワークのついでに作業ツリー外への書き込みが開き、承認の判断が一度も入らなくなるからである。実測値は `evidence.md`。

**週次の残量は CLI から引けない。** Paseo のアプリ側には Codex の週次枠の表示があるが、CLI には出ていない。`dev-max` の許可を諮るときは、消費を `paseo inspect <agentId> --json` の `LastUsage`（`InputTokens` / `OutputTokens` / `CachedTokens`）で示し、残量はユーザーに見てもらう。

コマンドの形が食い違ったら想像で補わず `"$PASEO_CLI" <コマンド> --help` を引く（この節は 2026-09-11 / 09-12、Paseo 0.8.0 と Codex 0.153.4 で実測し、[公式ドキュメント](https://paseo.sh/docs/cli)と[リポジトリ](https://github.com/getpaseo/paseo)で裏を取った）。
