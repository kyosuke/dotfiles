# PATH は .zshenv で組み立てる。ターミナルも herdr もログインシェル(zsh)を通して fish を起動するので、ここでは足さない。
# fish_add_path はユニバーサル変数へ書き込み、設定から消した後も fish_variables にパスが残り続ける。

# Editor
set -gx EDITOR "code --wait"

# mise（ディレクトリごとのツールのバージョンを反映させるため、PATH の先頭へ置けるよう最後に activate する）
mise activate fish | source
