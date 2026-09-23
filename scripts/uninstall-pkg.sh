#!/bin/bash
# 公式 .pkg で入れたツールを、インストール記録（pkgutil のレシート）に載っているファイルだけ消す。
# fish も Node.js も pkg 用のアンインストーラを持たない。
#
#   DRY_RUN=1 scripts/uninstall-pkg.sh fish        # 消す対象を表示するだけ
#   sudo scripts/uninstall-pkg.sh fish node
set -euo pipefail

run() { if [ "${DRY_RUN:-}" = 1 ]; then echo "$*"; else "$@"; fi; }

[ $# -gt 0 ] || { echo "usage: $0 fish|node ..." >&2; exit 64; }

pkgs=()
for tool in "$@"; do
  case "$tool" in
    fish) pkgs+=(com.ridiculousfish.fish-shell-pkg) ;;
    node) pkgs+=(org.nodejs.node.pkg org.nodejs.npm.pkg) ;;
    *) echo "unknown tool: $tool" >&2; exit 64 ;;
  esac
done

for pkg in "${pkgs[@]}"; do
  pkgutil --pkg-info "$pkg" >/dev/null 2>&1 || { echo "skip: $pkg (not installed)"; continue; }
  echo "== $pkg"
  # --only-files はシンボリックリンク（node の pkg の corepack など）を返さないので、全エントリーから選ぶ。
  pkgutil --files "$pkg" | while IFS= read -r f; do
    p="/$f"
    if [ -L "$p" ] || { [ -f "$p" ] && [ ! -d "$p" ]; }; then run rm -f "$p"; fi
  done
  # ディレクトリは他のソフトと共有しうるので、空になったものだけ消す。
  pkgutil --only-dirs --files "$pkg" | sort -r | while IFS= read -r d; do
    p="/$d"
    case "$p" in /usr|/usr/|/usr/local|/usr/local/|/usr/local/bin|/usr/local/lib|/usr/local/include|/usr/local/share|/usr/local/etc|/usr/local/share/man|/usr/local/share/man/man1|/usr/local/share/doc) continue ;; esac
    [ -d "$p" ] && run rmdir "$p" 2>/dev/null || true
  done
  run pkgutil --forget "$pkg"
done

# npm と npx のリンクは npm の pkg のインストール後スクリプトが作るのでレシートに載らない。リンク先で見分けて消す。
for l in /usr/local/bin/npm /usr/local/bin/npx; do
  case "$(readlink "$l" 2>/dev/null)" in ../lib/node_modules/npm/*) run rm -f "$l" ;; esac
done

# fish の pkg が登録したログインシェル候補を外す（ログインシェルは zsh のまま）。
if [ ! -e /usr/local/bin/fish ] && grep -qx /usr/local/bin/fish /etc/shells; then
  run sed -i '' '\#^/usr/local/bin/fish$#d' /etc/shells
fi
