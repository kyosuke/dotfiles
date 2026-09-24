# 委任ランナー: herdr

`HERDR_ENV` が 1 のときに読む。Codex 側の運用（依頼文の渡し方、承認の境界、並列の可否、ネットワーク、スレッドの片付け）はランナーに依らないので `execution.md` にある。

**herdr の操作は公式スキルに従う。** Skill ツールで `herdr` を呼ぶ（無ければ `herdr --skill` が同じ内容を出力する。バイナリが出力元なので本体の更新に追従する）。公式スキルの description は「ユーザーが herdr に言及したときだけ使う」と制限しているが、この委任経路は herdr のペイン操作そのものなので対象に入る。

ペインの分割、エージェントの起動と発注、状態の意味、読み取り源の選び方、閉じてよい範囲は公式スキルにある。ここには書かない。読まずに想像で補わない。

この Skill からの上書きは3点だけである。

- **Codex は `--no-alt-screen` で起動する。** 付けないと出力が代替画面から出てスクロールバックへ入らず、報告を回収できない（実測で0行）。公式スキルはこの状態のときファイル出力へ切り替える手を挙げるが、最初の依頼文でファイル出力を求めない。回収の失敗は起動フラグで消す。
- **分割方向は右を優先する。** 公式スキルは「横に広ければ右、縦に長ければ下」と書くが、ユーザーの環境は横方向に余裕があり、左右に並べるほうが読みやすいという指定である。分割後の幅が80桁を下回るなら下へ切り替える（81桁でも TUI は崩れず報告も欠落しなかった実測がある）。
- **2つ目以降のエージェントは、最初のエージェントペインを基準に下へ積む。** 右へ割り続けるとディレクターのペイン幅が削れる。幅は最初の分割で決まった値のまま維持されるので、80桁の判断は1回で済む。

Codex のネイティブ引数は `agent start` の `--` 以降から本体へ直接届く。プロファイルの値・`service_tier`・サンドボックスの設定はここで渡す。値を検証して弾く層が間に無いので、Codex が受理する値はそのまま使える。

## プロファイルを値で渡す

herdr にプロファイルの仕組みは無い。`../SKILL.md` で選んだプロファイルを、起動引数へ展開して渡す。

| プロファイル | herdr で渡す引数 |
|---|---|
| `dev-low` | `-m gpt-6-luna -c model_reasoning_effort=low -c service_tier=priority` |
| `dev-default` | `-m gpt-6-luna -c model_reasoning_effort=high -c service_tier=priority` |
| `dev-high` | `-m gpt-6-luna -c model_reasoning_effort=max -c service_tier=priority` |
| `dev-max` | `-m gpt-6-sol -c model_reasoning_effort=xhigh -c service_tier=default` |

プロファイルの定義は `../SKILL.md` の表にある。プロファイルが変わったらこの表を直す。

中間の推論量（`none` / `medium` / `xhigh`）もそのまま渡せる。プロファイルから外れるときは理由を発注前報告へ書く（`ordering.md`）。

### `service_tier` の語彙

Fast は Codex の `service_tier` で、プロファイルの `fast_mode: true` を `priority`、無しを `default` へ写す。値の語彙は [`codex-rs/core/config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json) にあり、オフを表す `default` はここにしか出てこない（`models_cache.json` は各モデルの対応ティア表で、語彙の一覧ではない）。オンに legacy の `fast` ではなく `priority` を渡す。対応ティアに無い値は警告つきでオフになるだけなので使わない。値を変えるならスキーマで語彙を確かめ、リクエスト本文まで読む（実測とその方法は `evidence.md`）。

`service_tier` は起動時に必ず明示する。TUI のトグルが `~/.codex/config.toml` へこのキーを書き戻すので、省くと対話セッションの状態が委任へ漏れる。

## ネットワークは起動時に開ける

`-c sandbox_workspace_write.network_access=true` を渡すと、**そのセッションだけ**ネットワークが通る。書き込み範囲は `workspace-write` のままなので、コマンド単位の昇格（サンドボックス外での実行）より露出が小さい。こちらを使い、昇格を既定にしない。

ループバックだけを開ける設定は無いので、外向きも同時に開く。運用の判断と `~/.codex/config.toml` を触らない理由は `execution.md`。

## 読み取り専用で起動できる

`-s read-only` が通る。調査だけを頼む発注と、収集役を同じ作業ツリーで並列に走らせる前提（`ordering.md`）はこのランナーで成立する。ネットワークは閉じるので、参照させたい一次資料は先にローカルへ落としてパスを渡す。
