# Editor
set -gx EDITOR "code --wait"

# Webi
fish_add_path $HOME/.local/bin

# pnpm
set -gx PNPM_HOME $HOME/Library/pnpm
fish_add_path $PNPM_HOME

# npm global
fish_add_path $HOME/.npm_global/bin

# bun
set -gx BUN_INSTALL $HOME/.bun
test -d $BUN_INSTALL/bin; and fish_add_path $BUN_INSTALL/bin

# deno
set -gx DENO_INSTALL $HOME/.deno
fish_add_path $DENO_INSTALL/bin

# Turso
fish_add_path $HOME/.turso

