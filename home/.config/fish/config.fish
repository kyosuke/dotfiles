# Editor
set -gx EDITOR "code --wait"

# Webi
fish_add_path $HOME/.local/bin

# pnpm
set -gx PNPM_HOME $HOME/Library/pnpm
fish_add_path $PNPM_HOME/bin

# npm global
set -gx NPM_CONFIG_PREFIX $HOME/.npm_global
fish_add_path $HOME/.npm_global/bin

# bun
set -gx BUN_INSTALL $HOME/.bun
test -d $BUN_INSTALL/bin; and fish_add_path $BUN_INSTALL/bin

# deno
set -gx DENO_INSTALL $HOME/.deno
fish_add_path $DENO_INSTALL/bin

# Turso
fish_add_path $HOME/.turso

# Emscripten (emsdk)
set -gx EMSDK $HOME/GitHub/emscripten-core/emsdk
fish_add_path $EMSDK
fish_add_path $EMSDK/upstream/emscripten
fish_add_path $EMSDK/python/3.13.3_64bit/bin

# Rust (cargo)
fish_add_path $HOME/.cargo/bin

# zellij ではペインにカレントディレクトリが出るので、プロンプト(Pure)からは省く。
# Pure に CWD を隠すオプションはないため内部関数を空で上書きする。
if set -q ZELLIJ
    function _pure_prompt_current_folder
    end
end

