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
config.font_dirs = { 'C:\\Users\\nanasess\\.local\\share\\fonts' }
config.font = wezterm.font_with_fallback {
  'UDEV Gothic JPDOC',
  'UDEV Gothic NF',
}
config.font_size = 14.0

-- locale-eaw EAW-CONSOLE に合わせた文字幅設定
-- https://github.com/hamano/locale-eaw
local eaw = dofile(wezterm.config_dir .. '/.eaw-console-wezterm.lua')
-- Claude Code TUI との互換性のため特定の記号を半角に戻す
table.insert(eaw, {first = 0x23bf, last = 0x23bf, width = 1})  -- ⎿
table.insert(eaw, {first = 0x25cf, last = 0x25cf, width = 1})  -- ●
config.cell_widths = eaw

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
