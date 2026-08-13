# 詰まったときの復旧

起動・発注・完了検知・報告回収が期待どおりに動かないときに読む。症状を見て運用を想像で変える前に、実際を確認する。通常の運用は `execution.md`。

## 起動しない

`herdr agent start` が失敗するか、ペインに Codex の TUI が出ないとき。

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
codex --version
```

`--workspace` を省くと他のワークスペースのペインまで並ぶ。ペインIDはワークスペース修飾（`w3:pJ`）なので、取り違えると別のタブを操作する。

- ペインIDが古い（閉じたペインを指している）。`pane split` からやり直す。
- モデルIDや `-c` のキーが実在しない。`--` 以降は Codex のネイティブ引数なので、`codex --help` と `~/.codex/models_cache.json` で確かめる。`-c` のキーと値の出典は公式スキーマで、`models_cache.json` とは役割が違う（`ordering.md`）。
- 起動はしたが `--no-alt-screen` を付け忘れた。報告の回収で詰まるので、この時点で `/quit` して起動し直す。

## 発注が通らない

`herdr agent prompt` が通らない、または送っても状態が変わらないとき。

- `agent_status` が `blocked` のまま送っている。判定と復帰は `execution.md` の「承認を求められたとき」。
- 依頼文を直接埋め込んだかヒアドキュメントで渡した。ファイルへ書いてから `"$(cat <path>)"` で渡す。
- 直前のタスクが走ったままである。同一作業ツリーで別の Codex を並走させない。走っているものを終わらせるか、`/quit` してから出し直す。

出力の冒頭に `command not found` が並ぶのは、依頼文がシェルに食われた状態である（バックティックがコマンド置換として実行された）。この Codex は欠落した依頼文を読んでいるので、続けさせずに `/quit` し、依頼文をファイルへ書いてから出し直す。副作用で起動したプロセス（`wrangler dev` など）が残っていないかも確認する。

## 完了を検知できない

既定は `agent prompt --wait` が返す状態で判定する。それでも判定できないのは次の場合。

- `--wait` の `--timeout` が実作業より短い。所要時間の目安（`execution.md`）を見て取り直す。
- ペインを閉じてしまった、または herdr 側の状態が失われた。この場合だけ Codex 自身の実行ログを使う。ログは `~/.codex/sessions/<年>/<月>/<日>/rollout-<時刻>-<セッションUUID>.jsonl` にあり、更新が続いていれば調査中で、正常な進行である。

**対象のセッションUUIDでファイルを特定する。** `ls -t | head -1` で最新を拾うと、別のタスクや他のリポジトリで走っている Codex のログを掴む。UUID は `agent_session.value`、Codex が `/quit` 時に表示する `codex resume <UUID>`、起動時刻から絞ったファイル名のいずれかで得る。

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

これは heuristic である。閾値を短くすると長考中に誤検知し、長くすると待ちが延びる。macOS 前提（`stat -f %m`）でもある。herdr の状態が読めるならこれに頼らない。対象ファイルの `md5 -q` を開始時と比較すると精度が上がる。

完了を待つ仕掛けを複数動かした場合、後から届く通知は既に検収済みのタスクのものかもしれない。最終報告後に通知が来たら、対象ファイルのチェックサムが検収時と一致するか確認し、変化がなければ追加対応は不要と判断する。

## 報告が回収できない

### `--no-alt-screen` を付け忘れたとき

代替画面のままだと2つ起きる。どちらも起動フラグで消えるので、症状を見たら運用を変える前に起動コマンドを確認する。

- 出力が画面に収まっている間はスクロールバックが空で、`recent` と `recent-unwrapped` が終了コード0で0行を返す（`visible` と `detection` は読める）。0行は失敗ではなく「まだ流れていない」状態である。
- 代替画面から出た行はスクロールバックへ入らないので、`--lines` を増やしても報告の先頭は戻らない。この状態で先頭が要るなら、報告をMarkdownでファイルへ書いてパスだけを返すよう依頼し直して読む。最初の依頼文でファイル出力を求めない。

### herdr から読めなくなったとき

ペインを閉じたあとなど、`agent read` が使えない場合は、実行ログから Codex の最終メッセージを抽出する。回収できた報告も、そのまま信用せず実際の差分と突き合わせる。

```bash
U=<セッションUUID>
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*-"$U".jsonl | head -1)
python3 - "$f" <<'EOF'
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
EOF
```

## ペインを閉じたあとにスレッドへ戻る

**素の shell で `codex resume <UUID>` を叩かない。** herdr がエージェントとして認識しないので、`agent prompt` も `agent read` も `blocked` の検知も効かず、復旧したはずのスレッドが管理外に出る。新しいペインを作り、`agent start` の Codex ネイティブ引数として `resume` を渡す。

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr agent start <名前> --kind codex --pane <pane_id> --timeout 60000 \
  -- resume <セッションUUID> --model <モデルID> -c model_reasoning_effort=<推論量> \
     -c service_tier=<luna なら priority / sol なら default> --no-alt-screen
```

`agent start` は `--` 以降を素の argv として渡すので `codex resume <UUID> …` が起動し、前のスレッドの内容を保った状態で `agent_status: idle` になる（2026-08-09、herdr 0.8.0 / Codex 0.146.0 で確認）。以後は通常どおり `agent prompt` で続けられる。

UUID を省いて `--last` を使わない。直近のセッションはリポジトリも用途も違うことがある。UUID が分からないなら、rollout ログのファイル名から拾う（上記）。

モデルと推論量、`service_tier` は再開時にも明示する。省くと `~/.codex/config.toml` の既定が効き、元のスレッドと違う段で動く。

## `listen EPERM` を見たとき

運用の判断は `execution.md` の「ネットワークとローカルバインド」にある。設定の状態が疑わしいときだけ実測する。既定の運用では `LISTEN FAIL: EPERM` と `OUTBOUND FAIL: ENOTFOUND` が正しい。

**検証もペインで行う。`codex exec` でヘッドレスに走らせない。** `~/.codex/config.toml` の `approval_policy` が `on-request` だと、Codex は承認を求めた時点で答える相手を失い、標準出力に1バイトも出さないまま固まる（2026-08-12、27分放置して確認）。ペインなら同じ状況が `blocked` として見え、ユーザーが答えられる。

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

依頼文には「`node /tmp/net-test.mjs` を1回だけ実行し、出力をそのまま報告する。ファイルは変更しない」とだけ書き、ファイルへ書いてから渡す。失敗しても回避策を試させない。失敗した事実が結果である。

起動時に `-c` を渡していないので、`LISTEN OK` が返ったら config.toml に `network_access = true` が残っている。ペインで開けたセッションのほうを確かめたいなら、`-c sandbox_workspace_write.network_access=true` を足して同じ手順を踏む。

設定キーが実在するかは、モデルを呼ばずに確かめられる。ペインで `--strict-config` を付けて起動すると、未知のキーなら Codex は起動せずに終わる。

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr agent start strict-test --kind codex --pane <返った pane_id> --timeout 45000 \
  -- --strict-config -c '<key>=<value>' -m gpt-5.6-luna --no-alt-screen
```

`agent start` は起動待ちのタイムアウトを返すので、理由はペインを読んで確かめる（実測: `Error loading config.toml: unknown configuration field 'bogus_key_xyz' in -c/--config override`）。実在するキーなら普通に起動するので、そのまま `/quit` して畳む。

ただし、キーが受理されることは挙動が変わることを意味しない（`permissions.network.*` がその実例。`evidence.md`）。設定の効果は必ず上の listen テストで確かめる。
