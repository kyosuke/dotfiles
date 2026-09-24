# 詰まったときの復旧

起動・発注・完了検知・報告回収が期待どおりに動かないときに読む。症状を見て運用を想像で変える前に、実際を確認する。通常の運用は `execution.md`、ランナーごとのコマンドは `runner-paseo.md`・`runner-herdr.md`・`runner-orca.md`（使っているものだけ）。

## 起動しない

エージェントの起動が失敗するか、Codex が立ち上がらないとき。ランナー側の一覧コマンドで実際の状態を見てから切り分ける。

```bash
codex --version
```

- 指した対象が古い（すでに閉じたエージェントや画面を指している）。作り直す。
- モデルIDや設定キーが実在しない。Codex のネイティブ引数はランナーを素通りして本体へ届くので、`codex --help` と `~/.codex/models_cache.json` で確かめる。設定キーと値の出典は公式スキーマで、`models_cache.json` とは役割が違う（使っているランナーの reference）。
- ランナーがその引数を渡せない。通らない設定と代替は使っているランナーの reference にある。
- 報告を画面から読むランナーで、Codex をインライン描画で起動していない。回収で詰まるので、この時点で畳んで起動し直す（`runner-herdr.md`）。

## 発注が通らない

発注が届かない、または送っても状態が変わらないとき。

- 承認待ちのまま送っている。判定と復帰は `execution.md` の「承認を求められたとき」。
- 依頼文を直接埋め込んだかヒアドキュメントで渡した。ファイルへ書いてから渡す。
- 直前のタスクが走ったままである。同一作業ツリーで別の Codex を並走させない。走っているものを終わらせるか、畳んでから出し直す。

出力の冒頭に `command not found` が並ぶのは、依頼文がシェルに食われた状態である（バックティックがコマンド置換として実行された）。この Codex は欠落した依頼文を読んでいるので、続けさせずに畳み、依頼文をファイルへ書いてから出し直す。副作用で起動したプロセス（`wrangler dev` など）が残っていないかも確認する。

## 完了を検知できない

既定はランナーの待機コマンドが返す状態で判定する。それでも判定できないのは次の場合。

- 待機のタイムアウトが実作業より短い。所要時間の目安（`execution.md`）を見て取り直す。
- エージェントを消してしまった、またはランナー側の状態が失われた。この場合だけ Codex 自身の実行ログを使う。ログは `~/.codex/sessions/<年>/<月>/<日>/rollout-<時刻>-<セッションUUID>.jsonl` にあり、更新が続いていれば調査中で、正常な進行である。

**対象のセッションUUIDでファイルを特定する。** `ls -t | head -1` で最新を拾うと、別のタスクや他のリポジトリで走っている Codex のログを掴む。UUID は、ランナーが持つセッション情報、Codex が `/quit` 時に表示する `codex resume <UUID>`、起動時刻から絞ったファイル名のいずれかで得る。

```bash
U=<セッションUUID>
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*-"$U".jsonl | head -1)
date; ls -lT "$f"; grep -o '"command":\[[^]]*\]' "$f" | tail -20
```

UUID が分からないときだけ最新を拾う。その場合は `ls -lT` の時刻と `grep` で出たコマンド列が自分の依頼と噛み合うかを必ず確かめてから使う。

ログの更新停止をアイドル検知として使うこともできる。Bash ツールの `run_in_background: true` で回す。ツールの呼び出しごとにシェルは作り直されるので、`U` と `f` は毎回この中で解決する。

```bash
U=<セッションUUID>
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*-"$U".jsonl | head -1)
deadline=$(( $(date +%s) + 2400 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  m=$(stat -f %m "$f"); now=$(date +%s)
  if [ $(( now - m )) -ge 120 ]; then
    echo "codex idle 120s at $(date '+%H:%M:%S')"; exit 0
  fi
  sleep 20
done
echo "timed out waiting for codex"
```

これは heuristic である。閾値を短くすると長考中に誤検知し、長くすると待ちが延びる。macOS 前提（`stat -f %m`）でもある。ランナーの状態が読めるならこれに頼らない。対象ファイルの `md5 -q` を開始時と比較すると精度が上がる。

完了を待つ仕掛けを複数動かした場合、後から届く通知は既に検収済みのタスクのものかもしれない。最終報告後に通知が来たら、対象ファイルのチェックサムが検収時と一致するか確認し、変化がなければ追加対応は不要と判断する。

## 報告が回収できない

まずランナー側の制約を疑う。画面から読むランナーで Codex を代替画面のまま起動していると、出力がスクロールバックへ入らず、行数を増やしても報告の先頭は戻らない（`runner-herdr.md`）。0行が返るのは失敗ではなく「まだ流れていない」状態のこともある。この状態で先頭が要るなら、報告をMarkdownでファイルへ書いてパスだけを返すよう依頼し直して読む。最初の依頼文でファイル出力を求めない。

ランナーから読めなくなった場合は、実行ログから Codex の最終メッセージを抽出する。回収できた報告も、そのまま信用せず実際の差分と突き合わせる。

```bash
U=<セッションUUID>
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*-"$U".jsonl | head -1)
python3 - "$f" <<'PY'
import json, sys
texts = []
def walk(x):
    if isinstance(x, dict):
        if x.get("type") in ("output_text", "text") and isinstance(x.get("text"), str):
            texts.append(x["text"])
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: walk(json.loads(line))
    except Exception: continue
out = [t for t in texts if len(t) > 200]
print(out[-1][:8000] if out else "(no long text found)")
PY
```

## 畳んだあとにスレッドへ戻る

**素の shell で `codex resume <UUID>` を叩かない。** ランナーがエージェントとして認識しないので、発注も報告回収も承認の検知も効かず、復旧したはずのスレッドが管理外に出る。ランナーの起動経路からセッションを引き継ぐ。

- Codex のネイティブ引数を渡せるランナーでは、起動引数として `resume <セッションUUID>` を渡す。前のスレッドの内容を保った状態で待機に入る（2026-08-09、herdr 0.8.0 / Codex 0.146.0 で確認）。
- 引数を渡せないランナーでは、既存のプロバイダセッションを取り込む経路を使う（Paseo は `paseo import <セッションID> --provider codex --cwd <作業ツリー>`。`runner-paseo.md`）。

UUID を省いて `--last` に当たる指定を使わない。直近のセッションはリポジトリも用途も違うことがある。UUID が分からないなら、rollout ログのファイル名から拾う（上記）。

モデルと推論量、`service_tier` は再開時にも明示する。省くと `~/.codex/config.toml` の既定が効き、元のスレッドと違うプロファイルで動く。

## `listen EPERM` を見たとき

運用の判断は `execution.md` の「ネットワークとローカルバインド」にある。設定の状態が疑わしいときだけ実測する。サンドボックス内では `LISTEN FAIL: EPERM` と `OUTBOUND FAIL: ENOTFOUND` が正しい。ネットワークが要る発注でこれを見たなら、依頼文で昇格を許していないか、Codex が要求しないまま失敗を報告している。依頼文を直して出し直す。

**検証もランナー越しに行う。`codex exec` でヘッドレスに走らせない。** `~/.codex/config.toml` の `approval_policy` が `on-request` だと、Codex は承認を求めた時点で答える相手を失い、標準出力に1バイトも出さないまま固まる（実測は `evidence.md`）。ランナー越しなら同じ状況が承認待ちとして見え、ユーザーが答えられる。

```bash
cat > /tmp/net-test.mjs <<'JS'
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
JS
```

`luna` + 最小の推論量でエージェントを立て、依頼文には「`node /tmp/net-test.mjs` を1回だけ実行し、出力をそのまま報告する。ファイルは変更しない」とだけ書いて、ファイルへ書いてから渡す。失敗しても回避策を試させない。失敗した事実が結果である。

昇格していないのに `LISTEN OK` が返ったら、config.toml に `network_access = true` が残っている。

設定キーが実在するかは、モデルを呼ばずに確かめられる。`--strict-config` を付けて起動すると、未知のキーなら Codex は起動せずに終わる（実測: `Error loading config.toml: unknown configuration field 'bogus_key_xyz' in -c/--config override`）。理由は画面かログで読む。実在するキーなら普通に起動するので、そのまま畳む。ネイティブ引数を渡せないランナーではこの確認ができないので、確かめたい設定があるならランナーを変えるか、`codex --help` とスキーマで済ませる。

ただし、キーが受理されることは挙動が変わることを意味しない（`permissions.network.*` がその実例。`evidence.md`）。設定の効果は必ず上の listen テストで確かめる。
