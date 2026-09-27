# PATH は .zshenv で組み立てる。ターミナルも herdr もログインシェル(zsh)を通して fish を起動するので、ここでは足さない。
# fish_add_path はユニバーサル変数へ書き込み、設定から消した後も fish_variables にパスが残り続ける。

# Editor
set -gx EDITOR "code --wait"

# mise（ディレクトリごとのツールのバージョンを反映させるため、PATH の先頭へ置けるよう最後に activate する）
# 非対話の fish はシムで足りるので activate しない。mise bootstrap の中で fish -c を呼ぶ時点では、
# 新しい Mac だと .zshenv がまだ効いておらず mise が PATH に無い。
status is-interactive; and mise activate fish | source

# pure はSSH接続時しかホスト名を出さない。Orca経由だとSSHにならないので、Airとminiを見分けるため常に出す
function _pure_prompt_ssh
    echo (_pure_set_color $pure_color_hostname)(prompt_hostname)
end
# 既定の true だとホスト名がgitブランチの後ろに回るので、ディレクトリの前へ出す
set -g pure_begin_prompt_with_current_directory false
