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
# summary は全角10文字・半角20文字相当の表示幅に収める。
MAX_SUMMARY_CHARACTERS = 20
MAX_SUMMARY_DISPLAY_WIDTH = 20

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
    candidate = lines[0]
    sentence = re.match(r"^(.+?[。！？!?])", candidate)
    if sentence:
        candidate = sentence.group(1)
    candidate = "".join(char if char.isprintable() else " " for char in candidate)
    candidate = SPACES.sub(" ", candidate).strip()
    return shorten(candidate)


GENERIC_TITLES = {"bash", "claude code", "codex", "fish", "sh", "zsh"}


def terminal_title(payload, pane_id, socket_path):
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


def report(payload):
    if os.environ.get("HERDR_CODEX_SUMMARY", "1") == "0":
        return
    if os.environ.get("HERDR_ENV") != "1":
        return

    pane_id = os.environ.get("HERDR_PANE_ID")
    socket_path = os.environ.get("HERDR_SOCKET_PATH")
    if not pane_id or not socket_path:
        return

    if payload.get("hook_event_name") != "UserPromptSubmit":
        return

    # 依頼直後は Claude/Herdr が付けたタスク名だけを summary にする。
    summary = normalize(terminal_title(payload, pane_id, socket_path))
    if not summary:
        # 汎用タイトルなら、古い summary を上書きしない。
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
