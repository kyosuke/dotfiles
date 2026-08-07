#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RULES="$ROOT/.codex/rules/command-policy.rules"

command -v codex >/dev/null 2>&1 || {
  printf '%s\n' 'codex is required to validate the command policy' >&2
  exit 127
}
command -v jq >/dev/null 2>&1 || {
  printf '%s\n' 'jq is required to validate the command policy' >&2
  exit 127
}

check() {
  expected=$1
  shift
  actual=$(codex execpolicy check --rules "$RULES" -- "$@" | jq -r '.decision // "unset"')
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: expected %s, got %s: ' "$expected" "$actual" >&2
    printf '%s ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
  printf 'ok: %-9s ' "$actual"
  printf '%s ' "$@"
  printf '\n'
}

check allow gh pr view 123 --json title
check allow gh issue list
check allow gh run view 123
check allow gh repo view
check allow gh pr checkout 123
check allow rtk gh pr view 123

check prompt gh api repos/example/example/issues/1 --method POST --raw-field body=changed
check prompt gh pr edit 123 --title changed
check prompt gh issue comment 123 --body changed
check prompt gh issue close 123
check prompt gh release upload v1 asset.zip
check prompt rm -rf node_modules
check prompt git push --force-with-lease origin main

check forbidden gh pr merge 123
check forbidden gh repo delete example/example
check forbidden git reset --hard HEAD
check forbidden git checkout -- .
check forbidden git restore .
check forbidden rtk gh pr merge 123
