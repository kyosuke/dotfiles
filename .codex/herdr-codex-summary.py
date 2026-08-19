#!/usr/bin/env python3
"""Report a short Codex task summary to the Herdr pane metadata."""

import json
import os
import random
import re
import socket
import sys
import time


SOURCE = "dotfiles:codex-summary"
MAX_CHARS = 80

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
    if len(value) > MAX_CHARS:
        value = value[: MAX_CHARS - 1].rstrip() + "…"
    return value


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
