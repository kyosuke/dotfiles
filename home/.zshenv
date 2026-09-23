# PATH への重複追加を防ぐ（.zshenv は入れ子のシェルでも都度 source されるため）。
typeset -U path PATH

# Emscripten (emsdk)
export EMSDK="$HOME/GitHub/emscripten-core/emsdk"
export PATH="$EMSDK:$EMSDK/upstream/emscripten:$EMSDK/python/3.13.3_64bit/bin:$PATH"

# Rust (cargo)
export PATH="$HOME/.cargo/bin:$PATH"

# webi, mise
export PATH="$HOME/.local/bin:$PATH"

# mise のツール（node, fish）。対話シェルの fish は mise activate を使うが、
# ターミナルが fish や herdr を起動する時点ではまだ activate されていないのでシムを通す。
export PATH="$HOME/.local/share/mise/shims:$PATH"
