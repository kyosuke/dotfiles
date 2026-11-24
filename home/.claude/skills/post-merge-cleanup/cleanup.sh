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
dirty=$(git status --porcelain --untracked-files=all) || stop 2 "git status が失敗した"
if [ -n "$dirty" ]; then
  git status --short >&2
  stop 2 "未コミットの変更がある。stashは行わないので、コミットするか退避してから再実行してほしい"
fi
# rebaseやmergeの途中は、ファイル差分が空でもworktree固有の状態を持つ。切り替えや削除で失わないよう触らない
for f in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD sequencer BISECT_LOG; do
  [ -e "$(git rev-parse --git-path "$f")" ] && stop 2 "$f があり、rebase・merge・bisectなどの途中なので触らない"
done

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

# linked worktreeではデフォルトブランチが本体側でチェックアウト済みのため切り替えられない。
# 代わりに origin/<default> へdetachしてから -d し、ブランチが消えたらworktree自体を片付ける
linked=""
[ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ] && linked=1
# detached中に別ブランチを指定させると、detachし直したときに今のHEADにしかないコミットを失う
if [ -n "$linked" ] && [ -n "${1:-}" ] && [ "$1" != "$current" ]; then
  stop 2 "worktreeでは、そこでチェックアウトしているブランチだけを片付ける（引数なしで実行する）"
fi

# 3. 対象ブランチの決定。引数 > 現在のフィーチャーブランチ > まとめて片付け
target=${1:-}
if [ -z "$target" ]; then
  if [ -z "$current" ] && [ -z "$linked" ]; then
    stop 2 "detached HEADで、対象ブランチも指定されていない"
  elif [ "$current" != "$default" ]; then
    target=$current
  fi
fi

gone=""
if [ -n "$target" ]; then
  [ "$target" != "$default" ] \
    || stop 2 "対象がデフォルトブランチ $default 自身なので削除しない"
  # 手で先に消してあっても、記録が残っていれば止めずに戻る・pull・掃除を続ける。どちらにも無ければタイプミスとみなす
  if ! git show-ref --verify --quiet "refs/heads/$target"; then
    records_file="$(git rev-parse --git-common-dir)/review-terminals"
    [ -f "$records_file" ] && awk -v b="$target" '"" $1 == "" b { f = 1 } END { exit !f }' "$records_file" \
      || stop 2 "ローカルブランチ $target も、その記録も見つからない"
    gone=$target
  fi
fi

# 4. デフォルトブランチへ戻り、fast-forwardで取り込む。worktreeでは origin を取得するだけ
base=$default
if [ -n "$linked" ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git fetch --quiet origin "+refs/heads/$default:refs/remotes/origin/$default" \
      || stop 3 "origin の $default を取得できなかった。ブランチは削除していない"
    base=refs/remotes/origin/$default
  fi
  pulled="worktreeのため ${base#refs/remotes/} と比較"
elif [ "$current" != "$default" ]; then
  git checkout "$default" || stop 3 "$default への切り替えが失敗した"
fi

if [ -z "$linked" ]; then
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
  awk -v b="$branch" '"" $1 != "" b' "$records" > "$records.tmp" && mv "$records.tmp" "$records"
}

delete_if_merged() {
  local branch=$1

  # 決定表: 先祖なら取り込み済み。それ以外はsquash/rebaseマージの可能性をPRで確認する。
  if git merge-base --is-ancestor "$branch" "$base"; then
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

if [ -n "$gone" ]; then
  :
elif [ -n "$target" ]; then
  # worktreeでは自分がチェックアウトしていると -d できない。取り込み済みのときだけ base へdetachする
  if [ -n "$linked" ] && git merge-base --is-ancestor "$target" "$base"; then
    git checkout --quiet --detach "$base" || stop 3 "$base へのdetachが失敗した。ブランチは削除していない"
  fi
  delete_if_merged "$target"
  # 消せなかったらブランチへ戻し、worktreeも残す
  if [ -n "$linked" ] && git show-ref --verify --quiet "refs/heads/$target"; then
    git checkout --quiet "$target" || stop 3 "$target へ戻れなかった。ブランチとworktreeは残っている"
  fi
elif [ -z "$linked" ]; then
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

# 6b. ローカルにもどのリモート追跡参照にもないブランチの記録は役目を終えている。
# 先に -D した、別の場所でマージしたなどで上の経路を通らなかった分をここで閉じて消す
if [ -f "$records" ]; then
  for b in $(awk '{print $1}' "$records" | sort -u); do
    git show-ref --verify --quiet "refs/heads/$b" && continue
    [ -n "$(git for-each-ref --format=x "refs/remotes/*/$b")" ] && continue
    close_review_terminals "$b"
  done
fi

# 7. 報告
echo "ブランチ: ${default}（${pulled}）"
if [ -n "$deleted" ]; then
  printf '削除: %s\n' "$(printf '%b' "$deleted" | paste -sd ' ' -)"
else
  echo "削除: なし"
fi
[ -n "$gone" ] && echo "対象 $gone はローカルに既になかった"
[ -n "$closed" ] && echo "閉じたレビュー用ターミナル: ${closed% }"
[ -n "$unclosed" ] && echo "閉じられなかったレビュー用ターミナル（手動で閉じてほしい）: ${unclosed% }"
if [ -n "$skipped" ]; then
  printf '%b' "$skipped" | while IFS= read -r s; do
    [ -n "$s" ] && echo "未削除: $s"
  done
  [ -n "$linked" ] && echo "worktreeはブランチが残っているので削除しなかった"
  exit 4
fi

# 8. worktreeの削除。ブランチが消え、HEADが base に含まれ、作業ツリーがきれいなら失うものはない。
# Orcaのworktreeはこのセッションごと閉じられうるので、報告を出し終えてから最後に行う
if [ -n "$linked" ]; then
  [ -z "$(git symbolic-ref --quiet HEAD 2>/dev/null)" ] \
    || stop 4 "HEADがまだブランチを指しているのでworktreeは削除しなかった"
  git merge-base --is-ancestor HEAD "$base" \
    || stop 4 "HEADが $base に含まれないコミットなのでworktreeは削除しなかった"
  dirty=$(git status --porcelain --untracked-files=all) || stop 4 "git status が失敗したのでworktreeは削除しなかった"
  [ -z "$dirty" ] || stop 4 "作業ツリーに変更があるのでworktreeは削除しなかった"
  top=$(git rev-parse --show-toplevel)
  main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
  cd "$main" || stop 3 "本体のworktree $main へ移れなかった"
  if command -v orca >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
     && (cd "$top" && orca worktree current --json 2>/dev/null) \
       | jq -e --arg p "$top" '.result.worktree | .path == $p and .isMainWorktree == false' >/dev/null; then
    echo "worktreeを削除: ${top}（Orcaのワークスペースごと閉じる）"
    orca worktree rm --worktree "path:$top" >/dev/null || stop 3 "orca worktree rm が失敗した: $top（ブランチは削除済み、worktreeはdetachしたまま残っている）"
  else
    echo "worktreeを削除: $top"
    git worktree remove "$top" || stop 3 "git worktree remove が失敗した: $top（ブランチは削除済み、worktreeはdetachしたまま残っている）"
  fi
fi
exit 0
