# 委任ランナー

Codex を動かす経路ごとの差分。委任のたび、`../SKILL.md` で判定したランナーの節だけ読む。Codex 側の運用（承認の境界、並列の可否、ネットワーク、スレッドの片付け）はランナーに依らないので `execution.md` にある。

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

## Paseo

CLI は `$PASEO_CLI` にある（PATH には載っていない）。自分自身も Paseo のエージェントとして動いているので、ここで作る Codex は同じワークスペースのサブエージェントになる（Paseo が `PASEO_AGENT_ID` で親を判定する）。

手順は[公式のオーケストレーション例](https://paseo.sh/docs/cli)に従う。CLI に無い操作を自前で組まない。

```bash
P="$PASEO_CLI"

# 起動と発注（依頼文はファイルへ書いてから渡す。--quiet は ID だけを返す）
A=$("$P" run "$(cat <scratchpad>/order.txt)" \
  --provider codex/<モデルID> --thinking <推論量> --mode auto \
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

`run` の依頼文は位置引数なので `"$(cat <path>)"` で渡す。コマンド置換の出力はシェルに読み直されないため、バックティックを含む依頼文も欠けずに届く。差し戻しの `send` には `--prompt-file` がある。

**片付けは `archive`（ソフト削除）で行う。`delete` を使わない。** ハード削除したエージェントをアプリがタブで開いていると、アプリが消えたIDへ `update_agent_request` を約2秒おきに投げ続け、`Agent not found` で失敗し、タブが閉じられなくなる（2026-09-12、Paseo 0.8.0 で発生。アプリの再起動で復帰した）。公式ドキュメントが片付けとして挙げているのも `stop` と archive で、`delete` は勧めていない。

**作業を画面に出すのは `"$P" agent open <agentId>`。** タブとして開くだけで、置く位置は指定できない。Paseo の CLI にペインや分割を操作するコマンドは無いので、herdr のように右へ並べたいならユーザーがアプリ側で行う。開かなくても、サブエージェントは親の画面の Subagents track に出る。

**ユーザーが見る画面とディレクターが読むログは別経路である。** herdr はどちらも同じペインの画面を見ていたが、Paseo であなたが見るのはアプリのUI、ディレクターが読むのは `paseo logs` になる。`--quiet` や `--json` が変えるのは `run` の標準出力だけで、作業の見え方には影響しない。画面に出ていた内容を読んだつもりで報告しない。

**Codex のネイティブ引数を渡せない。** `paseo run` に `-c` 相当のフラグは無い。デーモンのAPIには `providerOptions` があり、Codex 向けに `approval_policy` / `sandbox_mode` / `sandbox_workspace_write.*` / `web_search` / `features.*` を受け付けるが（[providers.md](https://github.com/getpaseo/paseo/blob/main/docs/providers.md)）、CLI はこれを渡す口を持たない。スキーマは strict で `service_tier` を含まないので、Fast はどのみち指定できない。

**Fast は Paseo 側のトグルで、CLI からは触れない。** Paseo は Codex の Fast をエージェント単位の機能（`fast_mode`）として持ち、オンなら `service_tier` に `fast` を渡す（[codex-feature-definitions.ts](https://github.com/getpaseo/paseo/blob/main/packages/server/src/server/agent/providers/codex-feature-definitions.ts)）。ただし `paseo run` にも `agent update` にもこれを指定するフラグが無い。切り替えられるのはアプリの画面にいるユーザーだけである。

**依頼文へ `/fast` と書いても効かない。** Paseo が起動するのは `codex app-server` で、TUI のスラッシュコマンドを解釈しない。`/status` も `/fast` も普通のテキストとして読まれ、Codex は会話として返す（「高速モードです。」と答えたが何も切り替わらず、`~/.codex/config.toml` も変わらなかった。2026-09-12実測）。起動状態を見て送り込む手は使えない。

起動時の既定は `~/.codex/config.toml` の `service_tier` で、実測では `default`（オフ）のまま `luna` が動いた。`ordering.md` の「`luna` は Fast オン」はこのランナーでは自動的には効かない。config.toml は書き換えず、モデルと推論量だけを調整する（2026-09-11、ユーザーからの指示）。Fast が要る発注では、現状を発注前報告へ1行添え、アプリ側でトグルするかをユーザーに決めてもらう。

**推論量は `none` も通る。** `paseo provider models codex --json` の `thinkingOptionIds` は `low` 以上しか載せないが、CLI は値を検証せずに渡す。`--thinking none` で作ったエージェントは Codex のセッションへ `effort = "none"` として届いた（2026-09-12、rollout ログの `turn_context` で確認）。段の一覧（`ordering.md`）はそのまま使える。カタログに無いぶん Paseo のUIからは選べない。

**モードは3つで、読み取り専用が無い。** `auto`（Default Permissions）・`auto-review`・`full-access`。`--mode read-only` はデーモンが拒否する（`Invalid mode 'read-only' for provider 'codex'`）。調査だけを頼むときに書き込みを止める手段が依頼文の指示だけになるので、収集役を並列に走らせる前提（`ordering.md`）はこのランナーでは崩れる。同一作業ツリーで並列に走らせたいなら `--new-workspace worktree` で分ける。

**`--mode` は省かない。** プロバイダの既定は `auto-review` だが、エージェントの中から `paseo run` した実測では `auto` になった。どちらが効くかを起動時に確定させる。

**ネットワークは `--mode full-access` で開ける。** ただしこのモードは `approval_policy: never` と `sandbox_mode: danger-full-access` をまとめて当てる（[provider-manifest.ts](https://github.com/getpaseo/paseo/blob/main/packages/protocol/src/provider-manifest.ts)）。ネットワークだけを開ける粒度は無く、承認プロンプトも出なくなる。サーバー起動を伴う検証（workers プール、`wrangler dev`）が発注に含まれるときだけ使い、開けた事実は報告に書き、そのエージェントは検証が終わったら畳む。

**週次の残量は CLI から引けない。** Paseo のアプリ側には Codex の週次枠の表示があるが、CLI には出ていない。`sol` の許可を諮るときは、消費を `paseo inspect <agentId> --json` の `LastUsage`（`InputTokens` / `OutputTokens` / `CachedTokens`）で示し、残量はユーザーに見てもらう。

コマンドの形が食い違ったら想像で補わず `"$PASEO_CLI" <コマンド> --help` を引く（この節は 2026-09-11 / 09-12、Paseo 0.8.0 と Codex 0.153.4 で実測し、[公式ドキュメント](https://paseo.sh/docs/cli)と[リポジトリ](https://github.com/getpaseo/paseo)で裏を取った）。

## herdr

**herdr の操作は公式スキルに従う。** Skill ツールで `herdr` を呼ぶ（無ければ `herdr --skill` が同じ内容を出力する。バイナリが出力元なので本体の更新に追従する）。公式スキルの description は「ユーザーが herdr に言及したときだけ使う」と制限しているが、この委任経路は herdr のペイン操作そのものなので対象に入る。

ペインの分割、エージェントの起動と発注、状態の意味、読み取り源の選び方、閉じてよい範囲は公式スキルにある。ここには書かない。読まずに想像で補わない。

この Skill からの上書きは3点だけである。

- **Codex は `--no-alt-screen` で起動する。** 付けないと出力が代替画面から出てスクロールバックへ入らず、報告を回収できない（実測で0行）。公式スキルはこの状態のときファイル出力へ切り替える手を挙げるが、最初の依頼文でファイル出力を求めない。回収の失敗は起動フラグで消す。
- **分割方向は右を優先する。** 公式スキルは「横に広ければ右、縦に長ければ下」と書くが、ユーザーの環境は横方向に余裕があり、左右に並べるほうが読みやすいという指定である。分割後の幅が80桁を下回るなら下へ切り替える（81桁でも TUI は崩れず報告も欠落しなかった実測がある）。
- **2つ目以降のエージェントは、最初のエージェントペインを基準に下へ積む。** 右へ割り続けるとディレクターのペイン幅が削れる。幅は最初の分割で決まった値のまま維持されるので、80桁の判断は1回で済む。

Codex のネイティブ引数は `agent start` の `--` 以降から本体へ直接届く。段・`service_tier`・`-c sandbox_workspace_write.network_access=true` はここで渡す（`execution.md`）。
