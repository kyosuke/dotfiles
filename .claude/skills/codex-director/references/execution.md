# herdr 経路の復旧手順

委任経路は herdr のペインだけである（`herdr-pane.md`）。このファイルは、その経路が期待どおりに動かないときに読む。Codex が起動しない、発注が通らない、`blocked` から進まない、完了を検知できない、報告を回収できない、の5つを扱う。

前提として、`HERDR_ENV` が立っていなければ復旧の対象ではない。委任せずユーザーへ伝えて止まる（`../SKILL.md`）。

## Codex が起動しない

`herdr agent start` が失敗するか、ペインに Codex のTUIが出ないときは、想像で運用を変える前に実際を確認する。

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
codex --version
```

`--workspace` を省くと他のワークスペースのペインまで並ぶ。ペインIDはワークスペース修飾（`w3:pJ`）なので、取り違えると別のタブを操作する。

- ペインIDが古い（閉じたペインを指している）。`pane split` からやり直す。
- モデルIDや `-c` のキーが実在しない。`--` 以降は Codex のネイティブ引数なので、`codex --help` と `~/.codex/models_cache.json` で確かめる（`model-routing.md`）。
- 起動はしたが `--no-alt-screen` を付け忘れた。報告の回収で詰まるので、この時点で `/quit` して起動し直す。

## 発注が通らない

`herdr agent prompt` が通らない、または送っても状態が変わらないとき。

- `agent_status` が `blocked` のまま送っている。`blocked` は承認か質問のUIで、送っても直前の承認と区別できない。先に「承認を求められたとき」（`herdr-pane.md`）へ従い、`state_change_seq` が進んだかで判定する。
- 依頼文を直接埋め込んだかヒアドキュメントで渡した。Claude Code のclassifierが止めることがあり、止まらなくてもバックティックがコマンド置換として実行される。Write ツールでファイルへ書いてから `"$(cat <path>)"` で渡す。
- 直前のタスクが走ったままである。同一作業ツリーで別の Codex を並走させない。走っているものを終わらせるか、`/quit` してから出し直す。

## 出力の冒頭に `command not found` が並ぶ

依頼文がシェルに食われている（バックティックがコマンド置換として実行された）。この状態の Codex は欠落した依頼文を読んでいるので、続けさせずに `/quit` し、依頼文をファイルへ書いてから出し直す。副作用で起動したプロセス（`wrangler dev` など）が残っていないかも確認する。

## 完了を検知できない

既定は `agent prompt --wait` が返す状態で判定する。`agent get` を自分でポーリングしない。それでも判定できないのは次の場合。

- `--wait` の `--timeout` が実作業より短い。実装を伴う依頼は20分を超えることがある。Bash ツールの上限は10分なので、`run_in_background: true` で投げて完了通知を受けてから読む。
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

これは heuristic である。閾値を短くすると長考中に誤検知し、長くすると待ちが延びる。macOS 前提（`stat -f %m`）でもある。herdr の状態が読めるならこれに頼らない。ファイル変更の有無を併せて見ると精度が上がる（対象ファイルの `md5 -q` を開始時と比較する）。

**ファイルが未変更でも失敗と判断しない。** Codex は数分から十数分を調査に使ってから書き始める。

## 報告を回収できない

まず `herdr agent read <名前> --source recent-unwrapped --lines 600` を試す。0行が返る、または報告の先頭が欠けるときの原因と対処は `herdr-pane.md` の「`--no-alt-screen` を付け忘れたときの症状」にある。

ペインを閉じたあとなど、herdr から読めなくなった場合は、実行ログから Codex の最終メッセージを抽出する。回収できた報告も、そのまま信用せず実際の差分と突き合わせる。

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

## スレッドへ戻る

ペインを閉じたあとでも、セッションUUIDがあれば同じスレッドを続けられる。**素の shell で `codex resume <UUID>` を叩かない。** herdr がエージェントとして認識しないので、`agent prompt` も `agent read` も `blocked` の検知も効かず、復旧したはずのスレッドが管理外に出る。新しいペインを作り、`agent start` の Codex ネイティブ引数として `resume` を渡す。

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr agent start <名前> --kind codex --pane <pane_id> --timeout 60000 \
  -- resume <セッションUUID> --model <モデルID> -c model_reasoning_effort=<推論量> --no-alt-screen
```

2026-08-09 に herdr 0.8.0 / Codex 0.146.0 で確認した。`agent start` は `--` 以降を素の argv として渡すので `codex resume <UUID> …` が起動し、前のスレッドの内容を保った状態で `agent_status: idle` になる。以後は通常どおり `agent prompt` で続けられる。

UUID を省いて `--last` を使わない。直近のセッションはリポジトリも用途も違うことがある。UUID が分からないなら、rollout ログのファイル名から拾う（上記）。

モデルと推論量は再開時にも明示する。省くと `~/.codex/config.toml` の既定が効き、元のスレッドと違う段で動く（2026-08-09 時点の既定は `gpt-5.6-luna` + `max`）。

## 注意

- 完了を待つ仕掛けを複数動かした場合、後から届く通知は既に検収済みのタスクのものかもしれない。最終報告後に通知が来たら、対象ファイルのチェックサムが検収時と一致するか確認し、変化がなければ追加対応は不要と判断する。
- ログの中身は Codex の内部状態であり、成果物ではない。進行状況の把握と報告の復旧にだけ使い、検収は必ず実際の差分で行う（`review-checklist.md`）。
