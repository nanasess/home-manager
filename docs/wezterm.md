# Windows on WezTerm

設定ソース: `modules/wezterm/wezterm.lua`
デプロイ先: `/mnt/c/Users/nanasess/.wezterm.lua`

`home.activation.weztermConfig` により `home-manager switch` 時に Windows 側へコピーされる。
ホームディレクトリ外（`/mnt/c/`）のため `home.file` のシンボリックリンクは使えず、`install` コマンドでコピーしている。
