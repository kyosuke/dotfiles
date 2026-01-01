# Google Antigravity AGENT向けの最小構成
if set -q ANTIGRAVITY_AGENT
    # プロンプトを極力プレーンにする
    functions -q fish_mode_prompt; and functions -e fish_mode_prompt
    function fish_prompt
        echo '$ '
    end

    # 起動時メッセージを抑制
    set -g fish_greeting ""

    # 以降の設定は読み込まず終了
    return
end

if status is-interactive
    # npm global
    fish_add_path $HOME/.npm_global/bin

    # pnpm
    set -gx PNPM_HOME $HOME/Library/pnpm
    fish_add_path $PNPM_HOME

    # deno
    set -gx DENO_INSTALL $HOME/.deno
    fish_add_path $DENO_INSTALL/bin

    # Bun
    set -gx BUN_INSTALL $HOME/.bun
    fish_add_path $BUN_INSTALL/bin

    # Turso
    fish_add_path $HOME/.turso

    # webinstall.dev (Webi)
    fish_add_path $HOME/.local/bin
end

# Generated for envman. Do not edit.
test -s ~/.config/envman/load.fish; and source ~/.config/envman/load.fish
