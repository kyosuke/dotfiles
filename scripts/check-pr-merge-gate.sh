#!/bin/bash
# home/.claude/hooks/pr-merge-gate.sh の判定を確かめる。gh はスタブに差し替え、
# カレントのリポジトリを ディレクトリ名 snow / other で切り替える。

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/home/.claude/hooks/pr-merge-gate.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/snow" "$tmp/other"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
case $PWD in */snow) echo kyosuke/snowcation ;; *) echo kyosuke/other ;; esac
EOF
chmod +x "$tmp/bin/gh"

check() {
  expected=$1 dir=$2 cmd=$3
  actual=$(jq -nc --arg c "$cmd" --arg d "$tmp/$dir" '{tool_input: {command: $c}, cwd: $d}' |
    PATH="$tmp/bin:$PATH" bash "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision')
  actual=${actual:-none}
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: expected %s, got %s: [%s] %s\n' "$expected" "$actual" "$dir" "$cmd" >&2
    exit 1
  fi
  printf 'ok: %-5s [%s] %s\n' "$actual" "$dir" "$cmd"
}

check allow snow  'gh pr merge 12 --auto --merge'
check allow snow  'gh pr merge --auto --merge -d'
check allow snow  'gh pr merge 12 --auto --merge -R kyosuke/snowcation'
check allow snow  'gh pr merge 12 --auto --merge --repo=kyosuke/snowcation'

check ask   other 'gh pr merge 12 --auto --merge'
check ask   snow  'gh pr merge 12 --merge'
check ask   snow  'gh pr merge 12 --auto --squash'
check ask   snow  'gh pr merge 12 --auto --merge --admin'
check ask   snow  'gh pr merge 12 --auto --merge -R kyosuke/other'
check ask   snow  'gh pr merge https://github.com/kyosuke/other/pull/1 --auto --merge'
check ask   snow  'gh pr merge 12 --auto --merge && gh pr merge 13'
check ask   snow  'cd ../other; gh pr merge 12 --auto --merge'
check ask   snow  'GH_REPO=kyosuke/other gh pr merge 12 --auto --merge'
check ask   snow  'gh pr merge 12 --auto --merge --subject "x"'
check ask   snow  'gh pr merge 12 --auto --merge -R'

check none  snow  'gh pr view 12'
check none  snow  'git merge main'
