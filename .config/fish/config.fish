if status is-interactive
  # npm global
  fish_add_path $HOME/.npm_global/bin

  # pnpm
  setenv PNPM_HOME $HOME/Library/pnpm
  fish_add_path $PNPM_HOME

  # deno
  setenv DENO_INSTALL $HOME/.deno
  fish_add_path $DENO_INSTALL/bin

  # Bun
  setenv BUN_INSTALL $HOME/.bun
  fish_add_path $BUN_INSTALL/bin

  # Turso
  fish_add_path $HOME/.turso
end
