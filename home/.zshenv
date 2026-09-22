# PATH への重複追加を防ぐ（.zshenv は入れ子のシェルでも都度 source されるため）。
typeset -U path PATH

# npm global
export NPM_CONFIG_PREFIX="$HOME/.npm_global"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

# Emscripten (emsdk)
export EMSDK="$HOME/GitHub/emscripten-core/emsdk"
export PATH="$EMSDK:$EMSDK/upstream/emscripten:$EMSDK/python/3.13.3_64bit/bin:$PATH"

# Rust (cargo)
export PATH="$HOME/.cargo/bin:$PATH"

# webi
export PATH="$HOME/.local/bin:$PATH"
