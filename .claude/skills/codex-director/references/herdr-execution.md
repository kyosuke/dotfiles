# herdr のペインで Codex を動かす

唯一の委任経路。発注の前に通して読み、詰まったら各節の「詰まったとき」へ戻る。2026-08-05の実測で決めた。この経路を選ぶ理由は、動作がユーザーに見え、承認を求められても復旧でき、差し戻しが同じスレッドで続くこと。

`HERDR_ENV` が立っていなければ委任経路が無い。退避先は用意せず、委任せずユーザーへ伝えて止まる（`../SKILL.md`）。

## 先に herdr 公式スキルを読む

**herdr の操作は公式スキルに従う。** Skill ツールで `herdr` を呼ぶ。無ければ `herdr --skill` が同じ内容を出力する（バイナリが出力元なので、herdr本体の更新に追従する）。公式スキルの description は「ユーザーが herdr に言及したときだけ使う」と制限しているが、この委任経路は herdr のペイン操作そのものなので対象に入る。読むことをためらわない。

`HERDR_ENV` の確認とコマンドの調べ方、ID の扱い、ペイン分割とエージェント名の規則、`idle` / `done` / `blocked` / `unknown` の意味と `--wait` / `--until` の使い分け、読み取り源4種（`visible` / `recent` / `recent-unwrapped` / `detection`）と代替画面の制約、閉じてよいペインの範囲は、すべて公式スキルにある。ここには書かない。読まずに想像で補わない。

以下は、それを Codex への委任に当てはめた上書きと、実測で足りないと分かった点だけ。

## ペインを用意する

### 分割方向は右を優先する（公式スキルの上書き）

公式スキルは「横に広ければ右、縦に長ければ下」と書いているが、ユーザーの環境は横方向に余裕があり、左右に並べて見るほうが読みやすいという指定である。`--direction right` を既定にする。

分割後の幅が80桁を下回るなら `down` へ切り替える。80桁は実測の下限。ユーザーのタブ（325x98）で既に兄弟ペインがある状態から右へ割ると81桁になり、Codex のTUIは崩れず、237行規模の報告も欠落なく回収できた。単一ペインのタブなら162桁になる。

### 2つ目以降のエージェントは最初のエージェントペインへ積む

複数のエージェントを同時に立てる場合、右へ割り続けない。**最初に作ったエージェントペインを基準に下方向へ分割する。**

```bash
herdr pane split --pane <最初のエージェントのpane_id> --direction down --cwd "$PWD" --no-focus
```

ディレクターのペイン幅が削られず、エージェントが右の1列に縦に並ぶ。幅は最初の分割で決まった値のまま維持されるので、80桁の下限を割る心配も1回目の判断で済む。減るのは行数なので、TUIが窮屈になったらそれ以上積まず、別タブへ移す。

エージェントを複数立てること自体は歓迎する。判断が要るのは作業ツリーの共有だけで、下記の「待機中の判断」に従う。

## Codex を起動する

```bash
herdr agent start <名前> --kind codex --pane <pane_id> --timeout 60000 \
  -- --model <モデルID> -c model_reasoning_effort=<推論量> --no-alt-screen
```

`--` 以降が Codex のネイティブ引数になる。モデルと推論量はここで渡す。値の検証を挟む層がないので、Codex 本体が受理する値はそのまま使える（`max` を含む。`model-routing.md`）。

**`--no-alt-screen` を必ず付ける。** Codex の TUI を代替画面ではなくインラインで描くので、出力がターミナルのスクロールバックに残り、報告の回収が確実になる（下記）。付けても `blocked` の検知は働き、ユーザーから見た表示も崩れない（実測）。

ファイル変更にフラグは要らない。ユーザーの設定（`workspace-write`）で既定で書ける。調査だけを頼むなら `-s read-only` を付ける。

ネットワークは既定で閉じており、`127.0.0.1` への listen も拒否される。`-c sandbox_workspace_write.network_access=true` を `--` 以降に足すとそのペインのセッションだけ開く。workers プールや `wrangler dev` のようにループバックを要する検証が発注に含まれるなら、起動時に付ける。外向き通信も同時に開くが、ユーザーの方針で都度の確認は要らない。要らない発注には付けない（`sandbox-network.md`）。

承認方針は既定の `on-request` のまま起動する。`-a untrusted` は `codex --help` にある正式な値だが、trusted 集合（`ls`・`cat`・`sed` など）の外にあるコマンドをすべて承認へ上げる（`find` も対象になった）。ディレクターは承認できないので、そのペインでは作業が進まない（下記「承認を求められたとき」）。

### 起動しないとき

`herdr agent start` が失敗するか、ペインに Codex のTUIが出ないときは、想像で運用を変える前に実際を確認する。

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
codex --version
```

`--workspace` を省くと他のワークスペースのペインまで並ぶ。ペインIDはワークスペース修飾（`w3:pJ`）なので、取り違えると別のタブを操作する。

- ペインIDが古い（閉じたペインを指している）。`pane split` からやり直す。
- モデルIDや `-c` のキーが実在しない。`--` 以降は Codex のネイティブ引数なので、`codex --help` と `~/.codex/models_cache.json` で確かめる（`model-routing.md`）。`-c` のキーと取りうる値の出典は [`codex-rs/core/config.schema.json`](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json) で、`models_cache.json` はモデル側が何に対応しているかの表にすぎない。両方を混同して片方だけ見ない。
- 起動はしたが `--no-alt-screen` を付け忘れた。報告の回収で詰まるので、この時点で `/quit` して起動し直す。

## 発注する

依頼文は Write ツールでファイルへ書いてから渡す。ヒアドキュメントは使わない。理由は2つ。文中のバックティックがコマンド置換として実行される（実運用で `` `wrangler dev` `` が起動してサーバーとして残り、`type: "RATE_LIMITED"` のような仕様の核が欠落した依頼文が渡った）。加えて、サンドボックスや権限に触れる文言を含むヒアドキュメントは Claude Code のclassifierに止められることがある。

```bash
herdr agent prompt <名前> "$(cat <scratchpad>/order.txt)" --wait --timeout 300000
```

戻った `agent_status` で分岐する。`agent get` を自分でポーリングしない。`idle` と `done` は区別せず、どちらも完了として報告を回収し検収へ進む。`blocked` は下記「承認を求められたとき」へ。

実測の所要時間は、読み取りだけの小さな依頼で12〜40秒。実装を伴う依頼は20分を超えることがある。Bashツールの上限は10分なので、長い依頼は `run_in_background: true` で投げ、完了通知を受けてから読む。

モデル名・推論量・オプションがこのファイルの記述と食い違ったら、想像で補わず `herdr agent`・`codex --help`・`~/.codex/models_cache.json` で実際を確認する。

### 発注が通らないとき

`herdr agent prompt` が通らない、または送っても状態が変わらないとき。

- `agent_status` が `blocked` のまま送っている。判定と復帰は下記「差し戻す」。
- 依頼文を直接埋め込んだかヒアドキュメントで渡した。上記のとおりファイルへ書いてから `"$(cat <path>)"` で渡す。
- 直前のタスクが走ったままである。同一作業ツリーで別の Codex を並走させない。走っているものを終わらせるか、`/quit` してから出し直す。

出力の冒頭に `command not found` が並ぶのは、依頼文がシェルに食われた状態である（バックティックがコマンド置換として実行された）。この Codex は欠落した依頼文を読んでいるので、続けさせずに `/quit` し、依頼文をファイルへ書いてから出し直す。副作用で起動したプロセス（`wrangler dev` など）が残っていないかも確認する。

## 待機中の判断

- **ファイルが未変更でも失敗と判断しない。** Codex は数分から十数分を調査に使ってから書き始める（実運用では開始3分後はまだ調査中だった）。
- 完了通知を受け取る前に、検収と最終報告を終えない。
- 待機中は同じ作業ツリーを触らない。**書き込みを伴う委任を同一作業ツリーで並列実行しない。** ペインを分けても作業ツリーは共有されるので、ペインの分離は並列化の根拠にならない。書かせる並列化には別の worktree / workspace を使い、`--cwd` をそちらへ向ける。
- 読み取りだけの委任（`-s read-only` で起動した調査・レビュー）は同じ作業ツリーで並走してよい。互いの結果を突き合わせたい調査は、むしろ分けて同時に走らせる。

### 完了を検知できないとき

既定は `agent prompt --wait` が返す状態で判定する。それでも判定できないのは次の場合。

- `--wait` の `--timeout` が実作業より短い。上記の所要時間を見て取り直す。
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

完了を待つ仕掛けを複数動かした場合、後から届く通知は既に検収済みのタスクのものかもしれない。最終報告後に通知が来たら、対象ファイルのチェックサムが検収時と一致するか確認し、変化がなければ追加対応は不要と判断する。

## 報告を回収する

```bash
herdr agent read <名前> --source recent-unwrapped --lines 600
```

`--no-alt-screen` で起動していれば、セッション開始時のバナーまで遡って読める（実測: 262行、対象5ファイル全項目、冒頭のマーカーも残る）。幅は精度に影響しない（`recent-unwrapped` がソフトラップを繋ぎ直す）。81桁のペインでも213行を全項目そろって回収できた。

**終端マーカーを依頼文に入れない。** 完了の検知は herdr の仕事で、`--wait` が状態として返すので判定が二重になる。取りこぼしの検出にも使えない。読み取りは常に下端が基準なので、失われるのは先頭である（実測: 500行の出力を `--lines 10` で読むと 493〜500 が返り、1〜10 は返らない）。終端マーカーは報告の冒頭が切れていても必ず読めるため、検出したい失敗をすり抜ける。機械的に判定したいならマーカーは報告の**先頭**へ置く。

### `--no-alt-screen` を付け忘れたときの症状

代替画面のままだと2つ起きる。どちらも起動フラグで消えるので、症状を見たら運用を変える前に起動コマンドを確認する。

- 出力が画面に収まっている間はスクロールバックが空で、`recent` と `recent-unwrapped` が終了コード0で0行を返す（`visible` と `detection` は読める）。同じフラグ構成で長い報告を出させると `recent-unwrapped` は213行を返したので、0行は失敗ではなく「まだ流れていない」状態。同じ依頼を `--no-alt-screen` 付きで実行したときは、短い応答でも40行返った。
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

## ペインの記録は証拠ではない

ペインに見えるのは Codex が描いた画面であり、コマンドの生出力ではない。Codex はツール出力を `… +464 lines` のように畳むので、畳まれた部分は読めない。

これは実害を出した。listen の可否を調べさせたとき、最終報告は `EPERM` と書いていたが、画面に見えていたのは `TIMEOUT` と `SERVER_CLOSED` で、畳まれた行に本当の出力があった。追試すると `EPERM` が事実で、`TIMEOUT` は Codex 自身のスクリプトに残ったタイマーの出力だった。報告と画面が食い違ったら、どちらも信じずに、出力が短くなる形で追試させる。

実行ログの中身も同じで、Codex の内部状態であって成果物ではない。進行状況の把握と報告の復旧にだけ使う。検収は画面でもログでもなく `git diff` で行う（`review-checklist.md`）。

## 承認を求められたとき

`blocked` が返ったら、`agent get` と `agent read --source detection` で何を聞かれているか読む。

ここに境界がある。**ディレクターは承認を代行しない。** Claude Code のclassifierが `send-keys` による承認の代理入力を止める。実際に止められた操作は3つ。

- Codex へ「サンドボックス外への権限昇格を要求して」と指示する発注
- Codex の承認プロンプトへ `send-keys y` で承認を入力する操作
- 権限昇格の文言を含むヒアドキュメント

却下は通る。`herdr agent send-keys <名前> esc` で却下でき、実測ではファイルは作られなかった。したがって承認が必要な場面は、見えているペインでユーザーが押す。ディレクターは何を求められているかをユーザーへ伝えて待つ。ペイン経路は動作が見えるので、この運用が噛み合う。

却下した直後は Codex が「どうするか指示して」で待つため、`agent_status` は `blocked` のままである。通常の `agent prompt` を送ると `idle` に戻る。

## 差し戻す

同じ名前へ `agent prompt` を送るだけで同じスレッドが続く。スレッドを明示的に再開する操作は要らない。実測では前のターンの内容（「先ほど要約した5ファイル」）を理解して続けた。

送る前に `agent_status` が `idle` か `done` であることを確認する。`blocked` のまま送ると、返ってきた `blocked` が新しい承認か直前の承認かを区別できない。`state_change_seq` が進んだかで判定する。

## スレッドIDと後片付け

`agent_session.value` が Codex のセッションIDで、`/quit` 時に Codex が表示する `codex resume <UUID>` と一致する。ペインを閉じたあとでも同じスレッドへ戻れるので、長い作業では記録しておく。

終わったら `/quit` を送り、自分が作ったペインだけを閉じる。

### ペインを閉じたあとにスレッドへ戻る

**素の shell で `codex resume <UUID>` を叩かない。** herdr がエージェントとして認識しないので、`agent prompt` も `agent read` も `blocked` の検知も効かず、復旧したはずのスレッドが管理外に出る。新しいペインを作り、`agent start` の Codex ネイティブ引数として `resume` を渡す。

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr agent start <名前> --kind codex --pane <pane_id> --timeout 60000 \
  -- resume <セッションUUID> --model <モデルID> -c model_reasoning_effort=<推論量> \
     -c service_tier=<luna なら priority / sol なら default> --no-alt-screen
```

2026-08-09 に herdr 0.8.0 / Codex 0.146.0 で確認した。`agent start` は `--` 以降を素の argv として渡すので `codex resume <UUID> …` が起動し、前のスレッドの内容を保った状態で `agent_status: idle` になる。以後は通常どおり `agent prompt` で続けられる。

UUID を省いて `--last` を使わない。直近のセッションはリポジトリも用途も違うことがある。UUID が分からないなら、rollout ログのファイル名から拾う（上記「完了を検知できないとき」）。

モデルと推論量、`service_tier` は再開時にも明示する。省くと `~/.codex/config.toml` の既定が効き、元のスレッドと違う段で動く（2026-08-09 時点の既定は `gpt-5.6-luna` + `max`、`service_tier = "fast"`）。`service_tier` の値の決め方は `model-routing.md`。
