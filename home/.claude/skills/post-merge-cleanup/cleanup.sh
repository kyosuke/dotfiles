#!/usr/bin/env bash
#
# post-merge-cleanup: PRマージ後にデフォルトブランチへ戻り、役目を終えたブランチを片付ける。
#
# Why not: 判断の分岐（マージ判定・squashマージの見分け・upstream先行での -d 拒否）を
# エージェントの指示遵守に委ねなかったのは、外したときの損失が未pushコミットの消失で、
# 節約できるトークンと釣り合わないため。決定表をここへ置き、-D と stash は存在させない。
#
# 使い方: cleanup.sh [対象ブランチ]
# 終了コード: 0=完了 / 1=想定外 / 2以降=停止条件（理由をstderrへ出す）

set -uo pipefail

stop() {
  local code=$1
  shift
  printf 'STOP: %s\n' "$*" >&2
  exit "$code"
}

# --- git ---------------------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || stop 2 "gitリポジトリではない"

# 1. 作業ツリーの確認。汚れていたら触らない（pullや切り替えで失う恐れがあるため）
if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  stop 2 "未コミットの変更がある。stashは行わないので、コミットするか退避してから再実行してほしい"
fi

# 2. デフォルトブランチの判定
default=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$default" ]; then
  for b in main master; do
    if git show-ref --verify --quiet "refs/heads/$b"; then
      default=$b
      break
    fi
  done
fi
[ -n "$default" ] || stop 2 "デフォルトブランチを判定できなかった"

current=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)

# 3. 対象ブランチの決定。引数 > 現在のフィーチャーブランチ > まとめて片付け
target=${1:-}
if [ -z "$target" ]; then
  if [ -z "$current" ]; then
    stop 2 "detached HEADで、対象ブランチも指定されていない"
  elif [ "$current" != "$default" ]; then
    target=$current
  fi
fi

if [ -n "$target" ]; then
  git show-ref --verify --quiet "refs/heads/$target" \
    || stop 2 "ローカルブランチ $target が見つからない"
  [ "$target" != "$default" ] \
    || stop 2 "対象がデフォルトブランチ $default 自身なので削除しない"
fi

# 4. デフォルトブランチへ戻り、fast-forwardで取り込む
if [ "$current" != "$default" ]; then
  git checkout "$default" || stop 3 "$default への切り替えが失敗した"
fi

before=$(git rev-parse HEAD)
if git remote get-url origin >/dev/null 2>&1; then
  git pull --ff-only \
    || stop 3 "git pull --ff-only が失敗した。ローカルとリモートが分岐している可能性がある。ブランチは削除していない"
fi

if [ "$before" != "$(git rev-parse HEAD)" ]; then
  pulled="取り込んだ変更あり"
else
  pulled="取り込む変更なし"
fi

# 5. 削除
deleted=""
skipped=""
closed=""
unclosed=""

# レビュー用に開いたターミナルの記録。1行 = "<ブランチ> orca <handle>" か "<ブランチ> herdr <pane_id> <terminal_id>"。
# 開いた側（orca-review、codex-director）が追記し、マージを確認できたブランチの分だけここで閉じて消す。
records="$(git rev-parse --git-common-dir)/review-terminals"

orca_alive() {
  orca terminal list --json 2>/dev/null \
    | jq -e --arg h "$1" '.result.terminals[] | select(.handle == $h)' >/dev/null
}

close_review_terminals() {
  local branch=$1 b kind id tid
  [ -f "$records" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # ループ内のorca/herdrが標準入力を読まないよう、記録はfd 3から読む
  while read -r b kind id tid <&3; do
    [ "$b" = "$branch" ] || continue
    case $kind in
      orca)
        # handleはUUIDで使い回されないので、生きていれば本人。closeは閉じても ok:false を返すことがあるため、消えたかをlistで確かめる
        orca_alive "$id" || continue
        orca terminal close --terminal "$id" >/dev/null 2>&1 || true
        if orca_alive "$id"; then
          unclosed="${unclosed}${kind}:${id} "
          continue
        fi
        ;;
      herdr)
        # pane_idは使い回されうるので、terminal_idも一致したときだけ閉じる
        herdr pane list 2>/dev/null \
          | jq -e --arg p "$id" --arg t "$tid" '.result.panes[] | select(.pane_id == $p and .terminal_id == $t)' >/dev/null || continue
        if ! herdr pane close "$id" >/dev/null 2>&1; then
          unclosed="${unclosed}${kind}:${id} "
          continue
        fi
        ;;
      *) continue ;;
    esac
    closed="${closed}${kind}:${id} "
  done 3< "$records"
  awk -v b="$branch" '$1 != b' "$records" > "$records.tmp" && mv "$records.tmp" "$records"
}

delete_if_merged() {
  local branch=$1

  # 決定表: 先祖なら取り込み済み。それ以外はsquash/rebaseマージの可能性をPRで確認する。
  if git merge-base --is-ancestor "$branch" "$default"; then
    close_review_terminals "$branch"
    if git branch -d "$branch" >/dev/null 2>&1; then
      deleted="${deleted}${branch}
"
    else
      # -d はupstream追跡があると origin/<同名> と比較するため、
      # デフォルトブランチへ入っていてもローカルが未pushだと拒否する。強制はしない。
      skipped="${skipped}${branch}: $default には入っているが、-d が拒否した（origin/$branch へ未pushのコミットがある可能性）。-D は使わないので手動で確認してほしい
"
    fi
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    local state
    state=$(gh pr view "$branch" --json state --jq '.state' 2>/dev/null || true)
    if [ "$state" = "MERGED" ]; then
      close_review_terminals "$branch"
      skipped="${skipped}${branch}: PRはMERGEDだがsquash/rebaseマージのため先祖にならず、-d では消せない。-D で消してよいか確認が要る
"
      return
    fi
    if [ -n "$state" ]; then
      skipped="${skipped}${branch}: PRが $state で $default に未取り込みのため削除しなかった
"
      return
    fi
  fi

  skipped="${skipped}${branch}: $default に未取り込みで、PRの状態も確認できなかったため削除しなかった
"
}

if [ -n "$target" ]; then
  delete_if_merged "$target"
else
  # まとめて片付け: デフォルトブランチから到達できるものだけが挙がる
  while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    delete_if_merged "$branch"
  done < <(git branch --merged "$default" --format='%(refname:short)' \
             | grep -vxE "$default|main|master" || true)
fi

# 6. 消えたリモートブランチへの追跡参照を掃除
if git remote get-url origin >/dev/null 2>&1; then
  git remote prune origin >/dev/null 2>&1 || true
fi

# 7. 報告
echo "ブランチ: ${default}（${pulled}）"
if [ -n "$deleted" ]; then
  printf '削除: %s\n' "$(printf '%b' "$deleted" | paste -sd ' ' -)"
else
  echo "削除: なし"
fi
[ -n "$closed" ] && echo "閉じたレビュー用ターミナル: ${closed% }"
[ -n "$unclosed" ] && echo "閉じられなかったレビュー用ターミナル（手動で閉じてほしい）: ${unclosed% }"
if [ -n "$skipped" ]; then
  printf '%b' "$skipped" | while IFS= read -r s; do
    [ -n "$s" ] && echo "未削除: $s"
  done
  exit 4
fi
exit 0
