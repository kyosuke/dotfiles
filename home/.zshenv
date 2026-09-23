# PATH への重複追加を防ぐ（.zshenv は入れ子のシェルでも都度 source されるため）。
typeset -U path PATH

# Emscripten (emsdk)。同梱の Python は版番号入りのディレクトリに入るので、emsdk を上げても追従するよう glob で引く。
export EMSDK="$HOME/GitHub/emscripten-core/emsdk"
path=($EMSDK $EMSDK/upstream/emscripten $EMSDK/python/*_64bit/bin(N) $path)

# Rust (cargo)
export PATH="$HOME/.cargo/bin:$PATH"

# Deno, Turso
export PATH="$HOME/.deno/bin:$HOME/.turso:$PATH"

# webi, mise
export PATH="$HOME/.local/bin:$PATH"

# mise のツール（node, fish）。対話シェルの fish は mise activate を使うが、
# ターミナルが fish や herdr を起動する時点ではまだ activate されていないのでシムを通す。
export PATH="$HOME/.local/share/mise/shims:$PATH"
