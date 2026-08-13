# サンドボックスのネットワークとローカルバインド

`listen EPERM: operation not permitted 127.0.0.1` を見たとき、またはテスト実行を委任できるか迷ったときに読む。結論は「config.toml では開けない。ループバックを要する検証が発注に含まれるなら、ペイン単位で開けて Codex 自身に走らせる。要らない発注では閉じたまま出す」。2026-07-30と2026-08-05の実測、および2026-08-09のユーザー指示で決めた。同じ検討を繰り返さないための記録である。

## 何が起きるか

Codex の workspace-write サンドボックスは既定でネットワークを閉じる。macOS の Seatbelt が `127.0.0.1` への bind まで拒否するため、`@cloudflare/vitest-pool-workers` の workers プール（workerd がループバックを listen する）と `wrangler dev` が動かない。

失敗の見え方が厄介である。vitest は起動できたプールの件数だけを passed として表示するので、workers プールが落ちても「Tests 36 passed」と出る。Codex はこれを成功として報告した。

ペイン経路でも既定は同じである（2026-08-05に `LISTEN_FAIL EPERM` と外向きの `ENOTFOUND` を実測）。

## 挙動が変わるのは network_access だけ

`sandbox_workspace_write.network_access = true` だけが実際に効く。`~/.codex/config.toml` に書けば全実行へ、CLI の `-c` で渡せばその実行だけへ届く。

| 設定 | `127.0.0.1` への listen | `npm test`（workers プール込み） | 外向き通信 |
|---|---|---|---|
| 既定（未設定） | `EPERM` | pool startup error、サマリ行なし | DNS 解決不可 |
| `network_access = true` | 成功 | 10ファイル / 121件 通過 | HTTP 200 |

ファイル変更を許した委任実行でも121件通過を確認した。技術的には解決する。

**config.toml へは書かない。** グローバルなので全 Codex 実行（TUI 含む、クライアント案件のリポジトリ含む）で外向きが開き、戻し忘れがそのまま恒久設定になる。開けるならペイン単位で開ける（下記）。

どちらの書き方でも、開いている間の代償は同じである。Codex は全ディスクの読み取りを持つため、1Password でマウント中の `.env` も読める。リポジトリ内容や取得ページ経由の prompt injection による持ち出し経路が増える。プロキシを併用しない限り通信先は制限されない。得るものは、Codex が自分でループバック依存のテストを走らせられること。ただしこの Skill は検収でディレクター側がフルスイートを独立に実行することを要求しており、Codex の自己検証は二重確認の片方でしかない。

## ループバックだけを開ける方法は無い（実測）

外向きを閉じたままローカルバインドだけ許す設定を探したが、0.145.0 には無い。

- `sandbox_workspace_write.allow_local_binds` は存在しないフィールドとして拒否される。
- `permissions.network.mode` / `.allow_local_binding` / `.domains` は config 検証を通るが、workspace-write の挙動を変えない（`allow_local_binding = true` を渡しても listen は `EPERM`、外向きもブロックされたまま）。`[permissions]` はプロファイルを選んで使う系統である。
- `features.network_proxy` は実在するフラグで、有効にすると実際に通信を遮断する（`curl: (56) CONNECT tunnel failed, response 403`）。ただし `network_access = true` と併用しても listen は `EPERM` のままだった。プロキシ経路にすると直接ソケットを失うため、必要なローカルバインドの方が消える。`permissions.network.domains` で許可したドメインも 403 になり、許可リストの表現も確立できなかった。

Seatbelt 側にはループバック限定のルール（`(allow network-inbound (local ip "localhost:*"))`）が存在し、`CODEX_NETWORK_ALLOW_LOCAL_BINDING` という環境変数も binary に含まれる。将来この組み合わせが設定から届くようになったら、外向きを閉じたまま有効化する価値がある。

## ペイン単位で開ける（実測で成立）

既定の委任経路である herdr のペイン（`herdr-execution.md`）では、`herdr agent start` の `--` 以降に `-c sandbox_workspace_write.network_access=true` を渡すと、**そのペインのセッションだけ**ネットワークが開く。2026-08-05に 0.146.0 で確認した（`LISTEN OK` と `OUTBOUND OK 200`。同じ時刻に config.toml 未設定のまま `codex exec` を既定で走らせると `EPERM` / `ENOTFOUND` のままだったので、効果はセッションに閉じている）。

config.toml のグローバル性に由来する事情はこれで消える。全 Codex 実行へ波及せず、戻し忘れも起きず、ペインを閉じれば効果も消える。ローカルバインドだけを開ける手段は無いままなので、外向きも同時に開く点は変わらない。

運用は次のとおり。

- ループバックを要する検証（workers プール、`wrangler dev`）が発注に含まれるなら、起動時に付ける。ユーザーの方針で、これは都度の確認を要しない（2026-08-09）。ループバックだけを開ける手段が無いので外向きも開くが、それを理由に付けるのをためらわない。
- ループバックが要らない発注には付けない。実装とサンドボックス内で完結する検査までを委任する形を崩さない。
- 開けたペインは検証が終わったら閉じる。同じ作業の続きでも、ネットワークが要らなくなったら開いたまま使い回さない。
- 露出を絞るなら専用 worktree のペインに限定する。
- 開けた事実は報告に書く。ログにも残す（`../SKILL.md` の試験運用の記録）。

なお、Codex へ「サンドボックス外への権限昇格を要求して」と指示する発注は Claude Code のclassifierに止められる。設定で開けるかどうかと、Codex に昇格を求めさせることは別の話で、後者は経路として使えない。

## 通常の運用

ローカルにポートを開く検証（workers プール、`wrangler dev`、通し実行）が発注に含まれるなら、ペイン起動時に `-c sandbox_workspace_write.network_access=true` を付けて Codex 自身に走らせる。付けないまま出すと、Codex は一度も実行できないテストを論理だけで書くことになり、差し戻しが増える。

**ネットワークを開けないことを理由に推論量やモデルを上げない。** これはユーザーからの明示的な指示である（2026-08-09）。テストを実行できないハンデは段を上げても埋まらず、開ければ消える。段の選択は `model-routing.md` の基準（依頼文に残る裁量）だけで決める。

付けなかった発注では、依頼文の `<verification>` にサンドボックスで完走するコマンドだけを書き（例: `npx vitest run --project node`）、フルスイートはディレクター側で実行すると明記する。いずれの場合も、テストを追加させたら件数はディレクター側で数える（`review-checklist.md`）。Codex 側の実行は二重確認の片方でしかない。

## 設定の状態を確かめる

疑わしいときは実測する。既定の運用では `LISTEN FAIL: EPERM` と `OUTBOUND FAIL: ENOTFOUND` が正しい。

**検証もペインで行う。`codex exec` でヘッドレスに走らせない。** `~/.codex/config.toml` の `approval_policy` が `on-request` だと、Codex は承認を求めた時点で答える相手を失い、標準出力に1バイトも出さないまま固まる（2026-08-12、27分放置して確認）。ペインなら同じ状況が `blocked` として見え、ユーザーが答えられる。委任経路をペインに限る理由がそのまま検証にも当てはまる。

```bash
cat > /tmp/net-test.mjs <<'EOF'
import net from "node:net";
const s = net.createServer();
s.on("error", (e) => { console.log("LISTEN FAIL:", e.code); outbound(); });
s.listen(0, "127.0.0.1", () => { console.log("LISTEN OK", s.address().port); s.close(); outbound(); });
async function outbound() {
  try {
    const r = await fetch("https://example.com", { signal: AbortSignal.timeout(8000) });
    console.log("OUTBOUND OK", r.status);
  } catch (e) {
    console.log("OUTBOUND FAIL:", e.cause?.code || e.code || e.name);
  }
}
EOF
herdr pane split --pane <エージェントのpane_id> --direction down --cwd "$PWD" --no-focus
herdr agent start net-test --kind codex --pane <返った pane_id> --timeout 60000 \
  -- -s workspace-write -m gpt-5.6-luna -c model_reasoning_effort=none \
     -c service_tier=priority --no-alt-screen
herdr agent prompt net-test "$(cat <scratchpad>/order.txt)" --wait --timeout 120000
```

依頼文には「`node /tmp/net-test.mjs` を1回だけ実行し、出力をそのまま報告する。ファイルは変更しない」とだけ書き、ファイルへ書いてから渡す（`herdr-execution.md`）。失敗しても回避策を試させない。失敗した事実が結果である。

起動時に `-c` を渡していないので、`LISTEN OK` が返ったら config.toml に `network_access = true` が残っている。ペインで開けたセッションのほうを確かめたいなら、`-c sandbox_workspace_write.network_access=true` を足して同じ手順を踏む。

設定キーが実在するかだけは、モデルを呼ばずに確かめられる。未知のキーなら `unknown configuration field`、実在するキーなら別のエラー（`no rollout found for thread id`）が返る。ターンを開始しないので承認も挟まらず、この形はヘッドレスのままでよい。

```bash
codex exec --strict-config resume 00000000-0000-0000-0000-000000000000 -c '<key>=<value>' "ok"
```

ただし、キーが受理されることは挙動が変わることを意味しない（`permissions.network.*` がその実例）。設定の効果は必ず上の listen テストで確かめる。

## 書き込み範囲

`workspace-write` が開けるのは作業ツリーだけではない。`/tmp` 配下も既定で書ける（`sandbox_workspace_write.exclude_slash_tmp` の既定が `false`。[`config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json)、2026-08-12参照）。ペインで実測し、作業ツリー外のスクラッチパッド（`/private/tmp` 配下）へ承認なしで書き込めた。

これを収集役の出力経路には使わない（`model-routing.md`）。書き込みを開けると同じ作業ツリーで並列に走らせられなくなり、調査のついでに repo を触る余地も残る。ここで確認したのは、開けた場合にどこまで届くかである。
