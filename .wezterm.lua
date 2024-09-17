local wezterm = require 'wezterm'

return {
  default_prog = { '/usr/local/bin/fish', '-l' },
  color_scheme = "Solarized Dark - Patched",
  font = wezterm.font 'PlemolJP35 Console',
  font_size = 14,
}
