#!/bin/sh
# Claude Code の作業概要を Herdr のペインメタデータ `summary` トークンへ報告する。
#
# herdr が入れる ~/.claude/hooks/herdr-agent-state.sh は integration の再インストールで
# 上書きされるため、そちらへ足さずに別ファイルへ分けている。
# 表示側（config.toml の $summary 行）は Herdr 側で設定する。
#
# 無効化: HERDR_CLAUDE_SUMMARY=0

set -eu

# フックの stdin は必ず読み切る。読まずに抜けると呼び出し側が EPIPE を踏む。
hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-claude-summary.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

[ "${HERDR_CLAUDE_SUMMARY:-1}" != "0" ] || exit 0
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# UserPromptSubmit では stdout がそのままコンテキストへ差し戻される。
# 標準出力・標準エラーとも捨て、フックの成否をセッションへ漏らさない。
HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY' >/dev/null 2>&1 || exit 0
import json
import os
import random
import re
import socket
import time

SOURCE = "dotfiles:claude-summary"
AGENT_SOURCE = "herdr:claude"
TOKEN = "summary"
MAX_CHARS = 80

pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
input_path = os.environ.get("HERDR_HOOK_INPUT_FILE")
if not pane_id or not socket_path or not input_path:
    raise SystemExit(0)

try:
    with open(input_path, encoding="utf-8") as handle:
        raw = handle.read()
    payload = json.loads(raw) if raw.strip() else {}
except Exception:
    raise SystemExit(0)
if not isinstance(payload, dict):
    raise SystemExit(0)

# サブエージェントは親と同じペインに紐づく。親の表示を奪わせない。
if payload.get("agent_id"):
    raise SystemExit(0)

FENCE = re.compile(r"```.*?```", re.S)
OPEN_FENCE = re.compile(r"```.*\Z", re.S)
TAG = re.compile(r"</?[A-Za-z][A-Za-z0-9_-]{0,40}(?:\s[^>\n]{0,200})?/?>")
URL_CRED = re.compile(r"://[^/\s:@]+:[^/\s@]+@")
KNOWN_SECRET = re.compile(
    r"(?:sk-[A-Za-z0-9_-]{16,}"
    r"|gh[pousr]_[A-Za-z0-9]{16,}"
    r"|github_pat_[A-Za-z0-9_]{20,}"
    r"|AKIA[0-9A-Z]{12,}"
    r"|xox[abposr]-[A-Za-z0-9-]{10,}"
    r"|AIza[0-9A-Za-z_-]{20,}"
    r"|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})"
)
KV_SECRET = re.compile(
    r"(?i)\b(password|passwd|secret|token|api[_-]?key|access[_-]?key|authorization|bearer)\b"
    r"\s*[:=]\s*\S+"
)
# 区切り記号を含まない長い英数字だけを狙う。パスは / や . で語境界が切れるので巻き込まない。
OPAQUE = re.compile(r"\b[A-Za-z0-9]{40,}\b")
LIST_MARK = re.compile(r"^\s*(?:[-*+]\s+|>\s*|#{1,6}\s+|\d+[.)]\s+)")
SPACES = re.compile(r"\s+")


def normalize(text):
    if not isinstance(text, str) or not text.strip():
        return ""
    t = OPEN_FENCE.sub(" ", FENCE.sub(" ", text))
    t = TAG.sub(" ", t)
    t = URL_CRED.sub("://***@", t)
    t = KNOWN_SECRET.sub("***", t)
    t = KV_SECRET.sub(lambda m: m.group(1) + "=***", t)
    t = OPAQUE.sub("***", t)
    lines = []
    for line in t.splitlines():
        line = LIST_MARK.sub("", line).replace("`", "").strip()
        if line:
            lines.append(line)
    t = " ".join(lines)
    t = "".join(ch if ch.isprintable() else " " for ch in t)
    t = SPACES.sub(" ", t).strip()
    if len(t) > MAX_CHARS:
        t = t[: MAX_CHARS - 1].rstrip() + "…"
    return t


event = str(payload.get("hook_event_name") or "")
if event == "UserPromptSubmit":
    summary = normalize(payload.get("prompt"))
    if not summary:
        raise SystemExit(0)
elif event == "Stop":
    # 応答本文が取れないターン（ツール実行だけで終わる等）は直前の表示を残す。
    summary = normalize(payload.get("last_assistant_message"))
    if not summary:
        raise SystemExit(0)
elif event in ("SessionStart", "SessionEnd"):
    summary = None
else:
    raise SystemExit(0)

request = {
    "id": "%s:%d:%06d" % (SOURCE, int(time.time() * 1000), random.randrange(1_000_000)),
    "method": "pane.report_metadata",
    "params": {
        "pane_id": pane_id,
        "source": SOURCE,
        "agent": "claude",
        "applies_to_source": AGENT_SOURCE,
        "tokens": {TOKEN: summary},
        "seq": time.time_ns(),
    },
}

try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    client.connect(socket_path)
    client.sendall((json.dumps(request) + "\n").encode())
    try:
        client.recv(4096)
    except Exception:
        pass
    client.close()
except Exception:
    pass
PY

exit 0
