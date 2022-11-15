if status is-interactive
  # npm global
  fish_add_path /Users/kyosuke/.npm_global/bin

  # pnpm
  set PNPM_HOME /Users/kyosuke/Library/pnpm
  fish_add_path $PNPM_HOME

  # deno
  set DENO_INSTALL /Users/kyosuke/.deno
  fish_add_path $DENO_INSTALL/bin
end
