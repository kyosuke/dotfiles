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

# UserPromptSubmit では標準出力・標準エラーとも捨て、フックの成否をセッションへ漏らさない。
HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY' >/dev/null 2>&1 || exit 0
import json
import os
import random
import re
import socket
import time
import unicodedata

SOURCE = "dotfiles:claude-summary"
AGENT_SOURCE = "herdr:claude"
TOKEN = "summary"
# summary は全角10文字・半角20文字相当の表示幅に収める。
MAX_SUMMARY_CHARACTERS = 20
MAX_SUMMARY_DISPLAY_WIDTH = 20

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


def char_width(char):
    if unicodedata.combining(char):
        return 0
    return 2 if unicodedata.east_asian_width(char) in ("W", "F") else 1


def shorten(text):
    display_width = sum(char_width(char) for char in text)
    if (
        len(text) <= MAX_SUMMARY_CHARACTERS
        and display_width <= MAX_SUMMARY_DISPLAY_WIDTH
    ):
        return text
    ellipsis = "…"
    budget = MAX_SUMMARY_DISPLAY_WIDTH - char_width(ellipsis)
    result = []
    width = 0
    for char in text:
        if len(result) >= MAX_SUMMARY_CHARACTERS - 1:
            break
        next_width = width + char_width(char)
        if next_width > budget:
            break
        result.append(char)
        width = next_width
    return "".join(result).rstrip() + ellipsis


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
    candidate = lines[0]
    sentence = re.match(r"^(.+?[。！？!?])", candidate)
    if sentence:
        candidate = sentence.group(1)
    candidate = "".join(ch if ch.isprintable() else " " for ch in candidate)
    candidate = SPACES.sub(" ", candidate).strip()
    return shorten(candidate)


GENERIC_TITLES = {"bash", "claude code", "codex", "fish", "sh", "zsh"}


def terminal_title(payload):
    request = {
        "id": "%s:%d:%06d" % (SOURCE, int(time.time() * 1000), random.randrange(1_000_000)),
        "method": "pane.get",
        "params": {"pane_id": pane_id},
    }
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(0.5)
        client.connect(socket_path)
        client.sendall((json.dumps(request) + "\n").encode())
        response = client.recv(4096)
        client.close()
        envelope = json.loads(response.decode())
        pane = envelope.get("result", {}).get("pane", {})
        title = pane.get("terminal_title_stripped") or pane.get("terminal_title")
    except Exception:
        return ""
    if not isinstance(title, str):
        return ""
    title = title.strip()
    if not title or title.casefold() in GENERIC_TITLES:
        return ""
    if title.startswith(("~/", "/")) or re.search(r"\s-\s(?:bash|fish|sh|zsh)$", title, re.I):
        return ""
    cwd = payload.get("cwd")
    if isinstance(cwd, str) and title == os.path.basename(cwd.rstrip("/")):
        return ""
    return title


if payload.get("hook_event_name") != "UserPromptSubmit":
    raise SystemExit(0)

# 依頼直後は Claude/Herdr が付けたタスク名だけを summary にする。
summary = normalize(terminal_title(payload))
if not summary:
    # 汎用タイトルなら、古い summary を上書きしない。
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
