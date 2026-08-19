#!/usr/bin/env python3
"""Report a short Codex task summary to the Herdr pane metadata."""

import json
import os
import random
import re
import socket
import sys
import time
import unicodedata


SOURCE = "dotfiles:codex-summary"
# Sidebar では全角10文字前後に収まるよう、表示幅を短く保つ。
MAX_DISPLAY_WIDTH = 22

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
OPAQUE = re.compile(r"\b[A-Za-z0-9]{40,}\b")
LIST_MARK = re.compile(r"^\s*(?:[-*+]\s+|>\s*|#{1,6}\s+|\d+[.)]\s+)")
SPACES = re.compile(r"\s+")


def char_width(char):
    if unicodedata.combining(char):
        return 0
    return 2 if unicodedata.east_asian_width(char) in ("W", "F") else 1


def shorten(text):
    if sum(char_width(char) for char in text) <= MAX_DISPLAY_WIDTH:
        return text
    ellipsis = "…"
    budget = MAX_DISPLAY_WIDTH - char_width(ellipsis)
    result = []
    width = 0
    for char in text:
        width += char_width(char)
        if width > budget:
            break
        result.append(char)
    return "".join(result).rstrip() + ellipsis


def normalize(text):
    if not isinstance(text, str) or not text.strip():
        return ""
    value = OPEN_FENCE.sub(" ", FENCE.sub(" ", text))
    value = TAG.sub(" ", value)
    value = URL_CRED.sub("://***@", value)
    value = KNOWN_SECRET.sub("***", value)
    value = KV_SECRET.sub(lambda match: match.group(1) + "=***", value)
    value = OPAQUE.sub("***", value)
    lines = []
    for line in value.splitlines():
        line = LIST_MARK.sub("", line).replace("`", "").strip()
        if line:
            lines.append(line)
    value = " ".join(lines)
    value = "".join(char if char.isprintable() else " " for char in value)
    value = SPACES.sub(" ", value).strip()
    return shorten(value)


def report(payload):
    if os.environ.get("HERDR_CODEX_SUMMARY", "1") == "0":
        return
    if os.environ.get("HERDR_ENV") != "1":
        return

    pane_id = os.environ.get("HERDR_PANE_ID")
    socket_path = os.environ.get("HERDR_SOCKET_PATH")
    if not pane_id or not socket_path:
        return

    event = str(payload.get("hook_event_name") or "")
    if event == "UserPromptSubmit":
        summary = normalize(payload.get("prompt"))
        if not summary:
            return
    elif event == "Stop":
        summary = normalize(payload.get("last_assistant_message"))
        if not summary:
            return
    elif event in ("SessionStart", "SessionEnd"):
        summary = ""
    else:
        return

    request = {
        "id": "%s:%d:%06d" % (SOURCE, int(time.time() * 1000), random.randrange(1_000_000)),
        "method": "pane.report_metadata",
        "params": {
            "pane_id": pane_id,
            "source": SOURCE,
            "agent": "codex",
            "tokens": {"summary": summary},
            "seq": time.time_ns(),
        },
    }

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    try:
        client.connect(socket_path)
        client.sendall((json.dumps(request, ensure_ascii=False) + "\n").encode())
        try:
            client.recv(4096)
        except Exception:
            pass
    finally:
        client.close()


def main():
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
        if isinstance(payload, dict):
            report(payload)
    except Exception:
        # A display-only hook must never block or alter the Codex turn.
        pass


if __name__ == "__main__":
    main()
