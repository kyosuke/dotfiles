#!/usr/bin/env python3
"""PreToolUse(Bash): gh pr merge の確認を決める。

kyosuke/snowcation で、単独の `gh pr merge [番号] --auto --merge [-d]` だけを確認なしで通し、
それ以外の gh pr merge は全て確認に回す。マージそのものの条件（必須チェック・競合）は GitHub 側が持つ。

引用符の中の文字列（sed のパターンや --prompt の説明文など）はマージとして扱わない。
実行される位置にある gh pr merge だけを対象にする。
判定のテストは scripts/check-pr-merge-gate.sh。
"""

import json
import os
import re
import shlex
import subprocess
import sys

REPO = "kyosuke/snowcation"
SEP = set(";&|()\n")
# 後ろに続く文字列をコマンドとして実行しうるもの。引数のどこかに gh と merge があれば対象にする。
RUNNERS = {
    "bash", "sh", "zsh", "fish", "dash", "eval", "source", ".", "exec", "command", "builtin",
    "sudo", "env", "nohup", "nice", "time", "timeout", "xargs", "parallel", "watch", "ssh",
}
# 次の語もコマンドの先頭として見るもの。
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "!", "{", "}"}
GH = re.compile(r"(^|[^\w-])gh([^\w-]|$)")
MERGE = re.compile(r"(^|[^\w-])merge([^\w-]|$)")


def mentions(text):
    return bool(GH.search(text) and MERGE.search(text))


def outside_single_quotes(cmd):
    """単引用符の中を除いた文字列。二重引用符の中の $( と ` は実行されるので残す。"""
    out, quote, i = [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if quote == "'":
            if c == "'":
                quote = None
        elif c == "\\":
            out.append(cmd[i : i + 2])
            i += 1
        elif c == "'" and quote is None:
            quote = "'"
        else:
            if c == '"':
                quote = None if quote == '"' else '"'
            out.append(c)
        i += 1
    return "".join(out)


def tokens(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace = " \t\r"
    lex.commenters = ""
    return list(lex)


def simple_commands(toks):
    """区切り記号で分けた単純コマンドを、代入・キーワード・リダイレクトを除いた語の列で返す。"""
    cmd, start, skip = [], True, False
    for t in toks:
        if t and set(t) <= set(";&|()<>\n"):
            if set(t) & SEP:
                if cmd:
                    yield cmd
                cmd, start = [], True
            else:
                skip = True  # リダイレクトの直後はファイル名
            continue
        if skip:
            skip = False
            continue
        if start and (t in KEYWORDS or re.match(r"^[A-Za-z_]\w*=", t)):
            continue
        start = False
        cmd.append(t)
    if cmd:
        yield cmd


def is_merge(cmd):
    if not mentions(cmd):
        return False
    # $( や ` の中は実行される。単引用符の中は実行されない。
    live = outside_single_quotes(cmd)
    if ("$(" in live or "`" in live) and mentions(live):
        return True
    try:
        toks = tokens(cmd)
    except ValueError:
        return True  # 引用符が閉じていないなど。確かめきれないので対象にする。
    for words in simple_commands(toks):
        name = os.path.basename(words[0])
        if name == "gh" and "pr" in words[1:] and "merge" in words[1:]:
            return True
        if name in RUNNERS and mentions(" ".join(words[1:])):
            return True
    return False


def decide(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": f"gh pr merge: {reason}",
    }}, ensure_ascii=False))
    sys.exit(0)


def check(cmd, cwd):
    # 改行・連結・置換・リダイレクト・引用符を含むものは、中身を確かめきれないので確認に回す。
    if re.search(r"[\n;&|$`<>()\"'\\]", cmd):
        decide("ask", "単独のコマンドではない")
    w = cmd.split()
    if w[:3] != ["gh", "pr", "merge"]:
        decide("ask", "形が想定外")
    auto = merge = False
    i = 3
    while i < len(w):
        t = w[i]
        if t == "--auto":
            auto = True
        elif t == "--merge":
            merge = True
        elif t in ("-d", "--delete-branch"):
            pass
        elif t in ("-R", "--repo"):
            i += 1
            if i >= len(w) or w[i] != REPO:
                decide("ask", f"{REPO} 以外を指している")
        elif t.startswith("--repo="):
            if t[len("--repo="):] != REPO:
                decide("ask", f"{REPO} 以外を指している")
        # 番号以外（URL・ブランチ名）は別リポジトリを指せるので通さない。--admin などの他フラグもここで落ちる。
        elif not t.isdigit():
            decide("ask", f"想定外の引数 {t}")
        i += 1
    if not (auto and merge):
        decide("ask", "--auto --merge ではない")
    try:
        actual = subprocess.run(
            ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
            cwd=cwd or None, capture_output=True, text=True, timeout=10,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        actual = ""
    if actual != REPO:
        decide("ask", f"カレントが {REPO} ではない")
    decide("allow", f"{REPO} の auto-merge")


def main():
    data = json.load(sys.stdin)
    cmd = (data.get("tool_input") or {}).get("command") or ""
    # gh pr merge を実行しないコマンドは何も返さず、通常の権限判定に任せる。
    if is_merge(cmd):
        check(cmd, data.get("cwd") or "")


if __name__ == "__main__":
    main()
