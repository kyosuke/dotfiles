#!/bin/sh
# フォントを ~/Library/Fonts へ入れる。入っていれば取りに行かないので、何度実行してもよい。
# Homebrew の cask は Homebrew 本体が要るので使わず、配布元の GitHub から取る。

set -eu

FONTS="$HOME/Library/Fonts"
mkdir -p "$FONTS"
# 途中で落ちたときに書きかけのファイルが残ると、次回は入っているとみなして飛ばしてしまう。一時ディレクトリで揃えてから移す。
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# PlemolJP35 Console NF（WezTerm・Ghostty）。書体ごとの配布が無く、全書体入りの 150MB ほどの zip から抜き出す。
if [ ! -e "$FONTS/PlemolJP35ConsoleNF-Regular.ttf" ]; then
  url=$(curl -fsSL https://api.github.com/repos/yuru7/PlemolJP/releases/latest |
    grep -o 'https://[^"]*/PlemolJP_NF_v[^"]*\.zip' | head -n 1)
  [ -n "$url" ] || {
    printf '%s\n' 'PlemolJP_NF のリリースが見つからない' >&2
    exit 1
  }
  curl -fsSL -o "$tmp/plemoljp.zip" "$url"
  unzip -q -j -o "$tmp/plemoljp.zip" '*/PlemolJP35Console_NF/*.ttf' -d "$tmp/plemoljp"
  mv "$tmp"/plemoljp/*.ttf "$FONTS/"
fi

# IBM Plex Sans JP。リリースの zip は 300MB を超えるので、リリースのタグから OTF だけを 1 つずつ取る。
# モノレポでリリース一覧には他のパッケージも混ざるため、最新版はタグを版番号で並べて決める。
if [ ! -e "$FONTS/IBMPlexSansJP-Regular.otf" ]; then
  tag=$(git ls-remote --tags --refs https://github.com/IBM/plex 'refs/tags/@ibm/plex-sans-jp@*' |
    sed 's|.*refs/tags/||' | sort -t@ -k3 -V | tail -n 1)
  [ -n "$tag" ] || {
    printf '%s\n' 'IBM Plex Sans JP のリリースが見つからない' >&2
    exit 1
  }
  ref=$(printf '%s' "$tag" | sed 's|@|%40|g; s|/|%2F|g')
  for weight in Thin ExtraLight Light Text Regular Medium SemiBold Bold; do
    curl -fsSL --create-dirs -o "$tmp/plex/IBMPlexSansJP-$weight.otf" \
      "https://raw.githubusercontent.com/IBM/plex/$ref/packages/plex-sans-jp/fonts/complete/otf/hinted/IBMPlexSansJP-$weight.otf"
  done
  mv "$tmp"/plex/*.otf "$FONTS/"
fi
