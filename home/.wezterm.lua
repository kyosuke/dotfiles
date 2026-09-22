local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.window_background_opacity = 0.90
config.macos_window_background_blur = 50
config.default_prog = { '/usr/local/bin/fish', '-l' }
config.color_scheme = "Solarized Dark - Patched"
config.font = wezterm.font 'PlemolJP35 Console'
config.font_size = 14

return config

