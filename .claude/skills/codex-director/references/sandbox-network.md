# サンドボックスのネットワークとローカルバインド

`listen EPERM: operation not permitted 127.0.0.1` を見たとき、またはテスト実行を委任できるか迷ったときに読む。結論は「既定のまま（閉じたまま）運用し、ローカルにポートを開く検証はディレクター側で実行する」。この判断は2026-07-30に実測して決めた。同じ検討を繰り返さないための記録である。

## 何が起きるか

Codex の workspace-write サンドボックスは既定でネットワークを閉じる。macOS の Seatbelt が `127.0.0.1` への bind まで拒否するため、ローカルにポートを開くツールが動かない。実際に止まったもの。

- `@cloudflare/vitest-pool-workers` の workers プール（workerd がループバックを listen する）
- `wrangler dev`

失敗の見え方が厄介である。vitest は起動できたプールの件数だけを passed として表示するので、workers プールが落ちても「Tests 36 passed」と出る。Codex はこれを成功として報告した。

## 唯一挙動が変わる設定と、採らない理由

`~/.codex/config.toml` の `[sandbox_workspace_write] network_access = true` だけが実際に効く。companion はこの設定を素通しする（`codex app-server` を追加フラグなしで起動し、thread へはサンドボックスのモード文字列だけを渡すため、network の可否は config.toml から解決される）。

| 設定 | `127.0.0.1` への listen | `npm test`（workers プール込み） | 外向き通信 |
|---|---|---|---|
| 既定（未設定） | `EPERM` | pool startup error、サマリ行なし | DNS 解決不可 |
| `network_access = true` | 成功 | 10ファイル / 121件 通過 | HTTP 200 |

委任経路（companion の `task --write`）でも121件通過を確認した。つまり技術的には解決する。

それでも既定を閉じたままにするのは、得るものと払うものが釣り合わないからである。

- 払うもの: config.toml はグローバルなので、全 Codex 実行（TUI 含む、クライアント案件のリポジトリ含む）で外向き通信が開く。Codex は全ディスクの読み取りを持つため、1Password でマウント中の `.env` も読める。リポジトリ内容や取得ページ経由の prompt injection による持ち出し経路が増える。プロキシを併用しない限り通信先は制限されない。
- 得るもの: Codex が自分でループバック依存のテストを走らせられること。ただしこの Skill は検収でディレクター側がフルスイートを独立に実行することを要求している。Codex の自己検証は二重確認の片方でしかない。

## ループバックだけを開ける方法は無い（実測）

外向きを閉じたままローカルバインドだけ許す設定を探したが、0.145.0 には無い。

- `sandbox_workspace_write.allow_local_binds` は存在しないフィールドとして拒否される。
- `permissions.network.mode` / `.allow_local_binding` / `.domains` は config 検証を通る。しかし workspace-write の挙動を変えない（`allow_local_binding = true` を渡しても listen は `EPERM` のまま、外向きもブロックされたまま）。`[permissions]` はプロファイルを選んで使う系統で、companion からは選べない。
- `features.network_proxy` は実在するフラグで、有効にすると実際に通信を遮断する（`curl: (56) CONNECT tunnel failed, response 403`）。ただし `network_access = true` と併用しても listen は `EPERM` のままだった。プロキシ経路にすると直接ソケットを失うため、必要なローカルバインドの方が消える。`permissions.network.domains` で許可したドメインも 403 になり、許可リストの表現も確立できなかった。

Seatbelt 側にはループバック限定のルール（`(allow network-inbound (local ip "localhost:*"))`）が存在し、`CODEX_NETWORK_ALLOW_LOCAL_BINDING` という環境変数も binary に含まれる。将来この組み合わせが設定から届くようになったら、そのときは外向きを閉じたまま有効化する価値がある。

## セッション単位の有効化は companion 経路では効かない

`codex -c 'sandbox_workspace_write.network_access=true'` は対話TUIには効くが、companion 経由の委任には効かない。companion は `codex app-server` をフラグなしで起動するため（`scripts/lib/app-server.mjs`）、CLI の `-c` は届かない。プラグイン側は更新で上書きされるので手を入れない。

companion 経路でどうしても1タスクだけ必要なら、config.toml を編集して発注し、終了後に戻す。実作業は20分を超えることがあるため、その間は全 Codex 実行で外向きが開く。戻し忘れると恒久設定と同じになる。使うなら、発注と同じターン内で戻すところまでを1セットとして扱う。

## ペイン経路での見直し候補（未検証・保留中）

既定の委任経路は herdr のペインに移った（`herdr-pane.md`）。ペインの Codex は対話TUIそのものなので、`herdr agent start` の `--` 以降に `-c sandbox_workspace_write.network_access=true` を渡せば、**そのペインのセッションだけ**ネットワークが開く見込みがある。2026-08-05時点で未検証であり、ユーザーの指示で保留にしている。実行する前に必ず確認を取る。

これが成立すると、上で「払うもの」として挙げた事情のうち、config.toml がグローバルであることに由来するものが消える。全 Codex 実行（TUI・クライアント案件のリポジトリ）へ波及せず、戻し忘れも起きず、ペインを閉じれば効果も消える。`workers` プールや `wrangler dev` を伴う検証を委任できるようになる。

残る払うものは消えない。Codex は全ディスクの読み取りを持つため、開いたペインでは1Passwordでマウント中の `.env` も読める。prompt injection による持ち出し経路は開いている間だけ増える。通信先はプロキシを併用しない限り制限されない。

検証するなら、ペインで起動した Codex に `EPERM` の実測（末尾の listen テスト）をさせるのが最短である。あわせて、露出範囲を絞るために専用 worktree のペインに限定する運用も選択肢になる。

なお、Codex へ「サンドボックス外への権限昇格を要求して」と指示する発注は Claude Code のclassifierに止められる。設定で開けるかどうかと、Codex に昇格を求めさせることは別の話である。後者は経路として使えない。

## 通常の運用

- ローカルにポートを開く検証（workers プール、`wrangler dev`、通し実行）は委任しない。実装とサンドボックス内で完結する検査までを委任し、これらはディレクター側で実行する。
- 依頼文の `<verification>` には、サンドボックスで完走するコマンドだけを書く。workers プールを含むリポジトリなら `npm test` ではなく `npx vitest run --project node` を指定し、フルスイートはディレクター側で実行すると明記する。
- テストを追加させたら件数を数える（`review-checklist.md`）。

## 設定の状態を確かめる

疑わしいときは実測する。

```bash
cat > /tmp/listen-test.mjs <<'EOF'
import net from "node:net";
const s = net.createServer();
s.on("error", (e) => { console.log("LISTEN FAIL:", e.code); process.exit(1); });
s.listen(0, "127.0.0.1", () => { console.log("LISTEN OK", s.address().port); s.close(); process.exit(0); });
EOF
codex exec -s workspace-write -m gpt-5.6-luna -c model_reasoning_effort=none \
  "Run exactly this once: node /tmp/listen-test.mjs — then reply with its output verbatim. Do not modify any files."
```

既定の運用では `LISTEN FAIL: EPERM` が正しい。`LISTEN OK` が返ったら config.toml に `network_access = true` が残っている。

設定キーが実在するかを確かめたいときは、モデルを呼ばずに検証できる。未知のキーなら `unknown configuration field`、実在するキーなら別のエラー（`no rollout found for thread id`）が返る。

```bash
codex exec --strict-config resume 00000000-0000-0000-0000-000000000000 -c '<key>=<value>' "ok"
```

ただし、キーが受理されることは挙動が変わることを意味しない。`permissions.network.*` がその実例である。設定の効果は必ず上の listen テストで確かめる。
