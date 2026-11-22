#!/bin/bash
# PreToolUse(Bash): gh pr merge の確認を決める。
# kyosuke/snowcation で、単独の `gh pr merge [番号] --auto --merge [-d]` だけを確認なしで通し、
# それ以外の gh pr merge は全て確認に回す。マージそのものの条件（必須チェック・競合）は GitHub 側が持つ。
# 判定のテストは scripts/check-pr-merge-gate.sh。

set -u

REPO=kyosuke/snowcation

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

decide() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# gh pr merge に関係しないコマンドは何も返さず、通常の権限判定に任せる。
grep -Eq '(^|[^[:alnum:]_-])gh([^[:alnum:]_-]|$)' <<<"$cmd" && grep -Eq '(^|[^[:alnum:]_-])merge([^[:alnum:]_-]|$)' <<<"$cmd" || exit 0

# 改行・連結・置換・リダイレクト・引用符を含むものは、中身を確かめきれないので確認に回す。
case $cmd in
  *$'\n'* | *[\;\&\|\$\`\<\>\(\)\"\'\\]*) decide ask "gh pr merge: 単独のコマンドではない" ;;
esac

read -r -a w <<<"$cmd"
[ "${#w[@]}" -ge 3 ] && [ "${w[0]}" = gh ] && [ "${w[1]}" = pr ] && [ "${w[2]}" = merge ] ||
  decide ask "gh pr merge: 形が想定外"

auto=0 merge=0 i=3
while [ "$i" -lt "${#w[@]}" ]; do
  t=${w[$i]}
  case $t in
    --auto) auto=1 ;;
    --merge) merge=1 ;;
    -d | --delete-branch) ;;
    -R | --repo)
      i=$((i + 1))
      [ "${w[$i]:-}" = "$REPO" ] || decide ask "gh pr merge: $REPO 以外を指している" ;;
    --repo=*) [ "${t#--repo=}" = "$REPO" ] || decide ask "gh pr merge: $REPO 以外を指している" ;;
    # 番号以外（URL・ブランチ名）は別リポジトリを指せるので通さない。--admin などの他フラグもここで落ちる。
    *) [[ $t =~ ^[0-9]+$ ]] || decide ask "gh pr merge: 想定外の引数 $t" ;;
  esac
  i=$((i + 1))
done
[ "$auto" = 1 ] && [ "$merge" = 1 ] || decide ask "gh pr merge: --auto --merge ではない"

actual=$(cd "$cwd" 2>/dev/null && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
[ "$actual" = "$REPO" ] || decide ask "gh pr merge: カレントが $REPO ではない"

decide allow "gh pr merge: $REPO の auto-merge"
