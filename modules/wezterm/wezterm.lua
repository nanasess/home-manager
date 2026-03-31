local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- This is where you actually apply your config choices
config.wsl_domains = {
  {
    name = "WSL:Gentoo-systemd",
    distribution = "Gentoo-systemd",
    default_cwd = "/home/nanasess",
  },
}
config.default_domain = "WSL:Gentoo-systemd"

config.color_scheme = "Solarized Light (Gogh)"
config.font = wezterm.font 'UDEV Gothic NF'
config.font_size = 14.0

local spawn_tab_in_home = wezterm.action.SpawnCommandInNewTab {
  cwd = '\\\\wsl.localhost\\Gentoo-systemd\\home\\nanasess',
  domain = { DomainName = 'WSL:Gentoo-systemd' },
}

config.keys = {
  { key = 'Enter', mods = 'SHIFT', action = wezterm.action.SendString '\x1b[13;2u' },
  { key = 't', mods = 'CTRL|SHIFT', action = spawn_tab_in_home },
  { key = 't', mods = 'SUPER', action = spawn_tab_in_home },
  { key = 'l', mods = 'CTRL', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'h', mods = 'CTRL', action = wezterm.action.ActivateTabRelative(-1) },
}

config.initial_cols = 160
config.initial_rows = 40
config.enable_scroll_bar = true
config.show_close_tab_button_in_tabs = false

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local title = (tab.tab_index + 1) .. ': ' .. tab.active_pane.title
  local min_width = 20
  return string.format("%-" .. min_width .. "s", title)
end)

return config
