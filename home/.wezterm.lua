local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.window_background_opacity = 0.90
config.macos_window_background_blur = 50
-- fish は mise で入れるため、ログインシェル(zsh)で PATH を解決してから起動する。
config.default_prog = { '/bin/zsh', '--login', '-c', 'exec fish -l' }
config.color_scheme = "Solarized Dark - Patched"
config.font = wezterm.font 'PlemolJP35 Console NF'
config.font_size = 14

return config

