# companion 経路と実行トラブルの復旧

既定は herdr のペイン経路である（`herdr-pane.md`）。このファイルは、`HERDR_ENV` が立っておらず herdr の外にいるとき、companion 経路で発注が通らないとき、報告を回収できないとき、またはユーザーが `/codex:rescue` の使用を明示したときに読む。

## companion 経路（herdr の外にいるとき）

公式プラグイン（`codex@openai-codex`）の companion スクリプトを Bash から直接呼び、`run_in_background: true` で実行する。プラグインのパスはバージョンを含むので動的に解決する。依頼文は Write ツールでファイルへ書いてから渡す。差し戻しは `--resume-last` を足す（リポジトリ単位で直近スレッドを解決する）。

```bash
P=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ | sort -V | tail -1)
ORDER=<scratchpad>/order.txt
node "$P/scripts/codex-companion.mjs" task --write --model <モデルID> --effort <推論量> "$(cat "$ORDER")"
```

- **`--write` を必ず付ける**。付けないと sandbox が `read-only` になり、Codex はファイルを変更できない。調査のみを頼むときは意図して外す。
- フォアグラウンド実行はしない。Bash の上限は10分だが実作業は20分を超えることがある。
- 委任中にマシンを再起動するとジョブ記録ごと作業が失われる。
- `/codex:rescue` を Skill ツール経由で呼ぶ方法は使わない（下記）。

ペイン経路と比べて失うものは、動作の可視性と承認への復旧である。companion は非対話で走るため、承認が必要な操作は失敗として返る。

## 発注が即失敗する

`Task <id> is still running. Use /codex:status before continuing it.` で止まったら、中断したジョブの記録が `running` のまま残っている。ハーネス側で止めても companion の状態は更新されない。

```bash
node "$P/scripts/codex-companion.mjs" status --all
node "$P/scripts/codex-companion.mjs" cancel <job-id>
```

cancel 後の `--resume-last` は、まず `completed` のジョブ記録を探す。見つからなければ Codex のスレッド一覧を更新時刻順に辿るため、cancel したスレッドを再開することがある。中断分を捨てて出し直すなら `--resume-last` を外して新規タスクとして発注する。

## 出力の冒頭に `command not found` が並ぶ

依頼文がシェルに食われている（バックティックがコマンド置換として実行された）。Codex を止め、依頼文をファイルへ書いてから渡す方式で出し直す。副作用で起動したプロセスが残っていないかも確認する。

## なぜ Skill 経由を使わないか

`/codex:rescue` の `rescue.md` は frontmatter に `context: fork` を持つ。Skill ツールから呼ぶとフォーク実行になり、`--wait` を渡してもディレクター側は待たずに戻る。2026-07-26 の実運用では、subagent が Codex 本体の完了前に `completed` を返し、その時点の作業ツリーは未変更だった。報告も回収できず、下記の復旧手順が必要になった。

Bash 直接実行にはこの層がない。プロセス終了が Codex の完了で、stdout 末尾に最終報告が入る。`--resume-last` はリポジトリ単位でスレッドを解決するため、Claude のセッション状態にも依存しない。ペイン経路では herdr が完了を状態として返すので、この問題自体が起きない。

## Skill 経由で呼んでしまった場合の復旧

### 1. 進行中か完了かを見分ける

Codex の実行ログは `~/.codex/sessions/<年>/<月>/<日>/rollout-<時刻>-<セッションUUID>.jsonl` にある。作業ツリーが未変更でも、このファイルが更新され続けていれば調査中で、正常な進行である。最後に実行されたコマンド列を見れば、いま何をしているかが分かる。

```bash
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head -1)
date; ls -lT "$f"; grep -o '"command":\[[^]]*\]' "$f" | tail -20
```

### 2. 完了を検知する

ハーネスの完了通知が期待できないので、ログの更新停止をアイドル検知として使う。Bash ツールの `run_in_background: true` で回す。

```bash
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head -1)
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

これは heuristic である。閾値を短くすると長考中に誤検知し、長くすると待ちが延びる。macOS 前提（`stat -f %m`）でもある。既定経路が使えるならこれに頼らない。ファイル変更の有無を併せて見ると精度が上がる（対象ファイルの `md5 -q` を開始時と比較する）。

### 3. 報告を回収する

Skill 経由で報告を取り逃した場合、ログから Codex の最終メッセージを抽出する。回収できた報告も、そのまま信用せず実際の差分と突き合わせる。

```bash
f=$(ls -t ~/.codex/sessions/*/*/*/rollout-*.jsonl | head -1)
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

## 注意

- 完了を待つ仕掛けを複数動かした場合、後から届く通知は既に検収済みのタスクのものかもしれない。最終報告後に通知が来たら、対象ファイルのチェックサムが検収時と一致するか確認し、変化がなければ追加対応は不要と判断する。
- ログの中身は Codex の内部状態であり、成果物ではない。進行状況の把握と報告の復旧にだけ使い、検収は必ず実際の差分で行う。
