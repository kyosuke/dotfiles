#!/bin/bash
# home/.claude/hooks/pr-merge-gate.py の判定を確かめる。gh はスタブに差し替え、
# カレントのリポジトリを ディレクトリ名 snow / other で切り替える。

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/home/.claude/hooks/pr-merge-gate.py"
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
    PATH="$tmp/bin:$PATH" python3 "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision')
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

check ask   snow  'cd x && gh pr merge 1 --merge'
check ask   snow  'for i in 1 2; do gh pr merge $i --auto --merge; done'
check ask   snow  'sudo gh pr merge 12 --auto --merge'
check ask   snow  'bash -c "gh pr merge 12 --auto --merge"'
check ask   snow  'echo 12 | xargs gh pr merge --auto --merge'
check ask   snow  'echo "$(gh pr merge 12 --auto --merge)"'
check ask   snow  'echo `gh pr merge 12`'
check ask   snow  'cat <(gh pr merge 12)'
check ask   snow  'bash <<EOF
gh pr merge 12 --auto --merge
EOF'
check ask   snow  '/opt/homebrew/bin/gh pr merge 12 --auto --merge'

check none  snow  'gh pr view 12'
check none  snow  'git merge main'
check none  snow  'echo "gh pr merge 12"'
check none  snow  'git commit -m "gh pr merge を許可する"'
# 2026-11-22 に誤検知した例
check none  snow  'sed -i '"''"' '"'"'27a\ ...'"'"' SOUL.md && for id in a b; do orca automations edit $id --prompt "PR は gh pr merge --auto --merge で出す"; done'
check none  snow  'sed -i '"''"' '"'"'s/- `gh pr merge` の許可は ... /&\n.../'"'"' memory/snowcation-ops.md'
