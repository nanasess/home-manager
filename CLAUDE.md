# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

Nix Flake ベースの [Home Manager](https://github.com/nix-community/home-manager) 設定リポジトリ。WSL2 Gentoo Linux, Ubuntu の環境を1リポジトリで宣言的に管理する。

### 目標

- 1リポジトリで WSL2 Gentoo + Ubuntu の設定を管理
- Nix Flakes による宣言的な構成管理
- GitHub Actions CI で設定の乖離を防止
- Emacs + elpaca 環境の管理

### 環境情報

| 項目 | 値 |
|------|-----|
| ユーザー名 | `nanasess` |
| WSL ホームディレクトリ | `/home/nanasess` |
| CPU | AMD Ryzen Zen 3 (`-march=znver3`) |
| ロケール | `ja_JP.UTF-8` |
| SSH | 1Password SSH Agent (`~/.1password/agent.sock`) |

## コマンド

```bash
# flake の検証（CI でも実行される）
nix flake check

# wsl-gentoo の設定をビルド（ローカル確認用）
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'

# Ubuntu の設定をビルド
nix build '.#homeConfigurations."nanasess@ubuntu".activationPackage'

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
home-manager switch --flake '.#nanasess@ubuntu'

# Nix ファイルのフォーマット
nix fmt

# flake.lock の更新
nix flake update

# ビルドログ確認
nix log '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'

# ドライラン
home-manager switch --flake '.#nanasess@wsl-gentoo' --dry-run
```

## アーキテクチャ

### ディレクトリ構成

```text
flake.nix              -- エントリポイント（inputs と homeConfigurations）
home.nix               -- 全ホスト共通設定（パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（WezTerm / Ghostty コピー、1Password CLI、WSLg X11/Wayland）
  ubuntu.nix           -- Ubuntu 固有設定（Ghostty、Walker、OneDrive）
modules/
  zsh/
    default.nix        -- Zsh モジュール（プラグイン、エイリアス、補完、1Password 連携）
    .p10k.zsh          -- Powerlevel10k テーマ設定
  emacs/
    default.nix        -- Emacs モジュール（elpaca でパッケージ管理）
    init.el             -- Emacs 設定
    early-init.el       -- Emacs 早期初期化設定
    elpaca.lock         -- elpaca パッケージロックファイル
    init.d/             -- OS/環境別の追加設定
    site-lisp/          -- 自作 Elisp
  locale-eaw/
    default.nix        -- locale-eaw モジュール（localedef + LOCPATH 設定）
    UTF-8-EAW-CONSOLE.gz -- East Asian Ambiguous 文字幅修正済み charmap
    eaw-console-wezterm.lua -- WezTerm cell_widths 設定
    eaw-console.el     -- Emacs char-width-table 設定
  wezterm/
    wezterm.lua        -- WezTerm 設定（WSL → Windows 側にコピー）
  ghostty/
    default.nix        -- Ghostty 共有設定（Linux native / Windows port (PR #12167) 両対応、_module.args で公開）
  bluetooth-audio/
    default.nix        -- Bluetooth オーディオ（HFP 自動切替の無効化 + pavucontrol。ubuntu 用）
    51-disable-headset-autoswitch.lua -- WirePlumber の自動プロファイル切替を無効化
  ibus-skk/
    default.nix        -- IBus SKK エンジン（Nix ビルドの 1.4.4 + IBUS_COMPONENT_PATH。ubuntu 用）
  xremap/
    default.nix        -- キーリマッパー（Chrome のタブ移動を Ctrl+H / Ctrl+L に。ubuntu 用）
  portage.nix          -- Portage 設定（WSL Gentoo 用、xdg.configFile で ~/.config/portage/ に書き出し）
  onedrive.nix         -- OneDrive 設定（WSL Gentoo 用）
  yaskkserv2.nix       -- SKK 辞書サーバ（systemd ユーザーサービス。wsl-gentoo / ubuntu 共通）
pkgs/
  yaskkserv2.nix       -- yaskkserv2 の自作 Nix derivation（buildRustPackage、nixpkgs 未収録のため）
  ibus-skk.nix         -- ibus-skk 1.4.4 の自作 Nix derivation（nixpkgs 未収録 + apt は 1.4.3 で停滞）
docs/                  -- 領域別の詳細ドキュメント（下記「詳細ドキュメント」参照）
.github/workflows/
  check.yml            -- CI 設定
```

### ホスト設定の追加パターン

1. `hosts/<hostname>.nix` を作成（ホスト固有の設定）
2. `flake.nix` の `homeConfigurations` にエントリを追加（`modules = [ ./home.nix ./hosts/<hostname>.nix ./modules/emacs ./modules/zsh ]`）

### 管理方針

| 管理対象 | ツール | 理由 |
|---------|--------|------|
| ユーザー環境・dotfiles | home-manager | 宣言的管理、CI 検証 |
| 開発ツール (CLI) | Nix | 環境再現性 |
| Zsh プラグイン | Nix (programs.zsh.plugins) | sheldon から移行、Nix による再現性 |
| Emacs Elisp パッケージ | elpaca + use-package | 柔軟性、ロックファイルによるバージョン固定 |
| Emacs ネイティブ依存 | Nix (cmigemo 等) | ビルド依存の解決 |
| WezTerm 設定 | home-manager → activation copy | WSL 側から Windows 側 (`/mnt/c/Users/nanasess/`) にコピー |
| Ghostty 設定 | 共有 Nix attrset + renderer | `programs.ghostty.settings` (Linux native) と `%LOCALAPPDATA%\ghostty\config.ghostty` (Windows port) を同一 attrset から生成 |
| East Asian Ambiguous 文字幅 | locale-eaw EAW-CONSOLE | glibc wcwidth + WezTerm cell_widths + Emacs char-width-table を統一 |
| Portage 設定 | home-manager (xdg.configFile) | `~/.config/portage/` に書き出し、`/etc/portage/` から個別にシンボリックリンク |
| システムパッケージ一覧 | Nix リスト + チェックスクリプト | 各ホストの nix ファイルで宣言、`check-system-packages` で差分確認 |
| SKK 辞書サーバ (yaskkserv2) | Nix ビルド (`pkgs/yaskkserv2.nix`) + systemd ユーザーサービス (`modules/yaskkserv2.nix`) | nixpkgs / apt に無いため上流を `buildRustPackage`。全ホスト同一バイナリ + ユーザーパス辞書 (`~/.local/share/yaskkserv2/all`) で sudo 不要・共通化 |
| IBus SKK エンジン | Nix ビルド (`pkgs/ibus-skk.nix`) + `IBUS_COMPONENT_PATH` (`modules/ibus-skk/`) | apt / nixpkgs とも 1.4.4 未提供。apt 版 1.4.3 は変換確定が壊れる（`docs/ibus-skk.md`）。IBus は `XDG_DATA_DIRS` を見ないため `systemd.user.sessionVariables` でエンジンを登録する |
| キーリマップ (xremap) | Nix (`xremap` gnome variant) + systemd ユーザーサービス (`modules/xremap/`) | Chrome にキーバインド変更機能が無いため evdev/uinput レベルで置換。アプリ判定に GNOME Shell 拡張が要る。`input` グループ / udev ルールのみ root 作業として残る |
| Bluetooth オーディオ | home-manager (xdg.configFile) + pavucontrol | WirePlumber の HFP 自動切替を無効化し、A2DP (ステレオ) / HFP (マイク) は pavucontrol で手動切替。プロファイルの記憶 (`~/.local/state/wireplumber/`) はランタイム状態のため管理外 |
| クリップボード画像 (WSL) | `wl-paste` shim (`hosts/wsl-gentoo.nix`) | WSLg が `image/bmp` しか出さず Claude Code が扱えないため、`image/png` を追加広告して ImageMagick で変換（`docs/clipboard-image-paste.md`） |

**プラットフォーム非依存化の判断基準**: portage / apt など特定ホストのパッケージマネージャに依存する構成は、入手経路が「バイナリ + 付随ツール」だけの問題であれば **Nix パッケージ化 (必要なら `pkgs/` に自作 derivation) して全ホスト共通化する**ことを優先する。辞書・データ類はシステムパス (`/usr/lib` 等、要 sudo) ではなくユーザーパス (`xdg.dataHome` 配下) に置き、セットアップを sudo レスにする。yaskkserv2 はこの方針で wsl-gentoo (旧 portage) と ubuntu を統一した先例 (PR #110)。

### 移行元リポジトリ (TODO)

以下のリポジトリからの移行状況。段階的にこのリポジトリへ統合する。

| リポジトリ | 移行対象 | 状態 |
|-----------|---------|------|
| `~/.config/dotfiles` | Zsh 設定、エイリアス、1Password SSH 連携 | 移行済み |
| `~/git-repos/gentoo-ansible` | Portage 設定 (make.conf, package.use 等) | 移行済み (`modules/portage.nix`) |

### フォーマッター

`nixpkgs-fmt` を使用。`nix fmt` で実行可能。`supportedSystems` は `x86_64-linux`。

## CI

GitHub Actions (`.github/workflows/check.yml`) が push/PR 時に以下を実行:
- **check** — `nix flake check` + WezTerm Lua 構文チェック
- **emacs** — `emacs --batch` による init.el の読み込みテスト（elpaca キャッシュ付き）
- **build** — 各ホストの `activationPackage` ビルド（matrix: ubuntu-latest）

## 詳細ドキュメント (`docs/`)

環境ごとの調査結果・落とし穴は `docs/` に分離してある。該当領域を触るときに読むこと。

| ドキュメント | 内容 | 主な対象 |
|---|---|---|
| [docs/locale-eaw.md](docs/locale-eaw.md) | East Asian Ambiguous 文字幅を glibc / WezTerm / Emacs で統一する仕組みと注意点 | `modules/locale-eaw/` |
| [docs/wezterm.md](docs/wezterm.md) | WezTerm 設定を WSL 側から Windows 側へコピーする経路 | `modules/wezterm/` |
| [docs/bluetooth-audio.md](docs/bluetooth-audio.md) | 接続不安定 (マルチポイント / discovery 枯渇 / WiFi 2.4GHz) の切り分け、A2DP と HFP の排他、自動切替の無効化 | `modules/bluetooth-audio/` (ubuntu) |
| [docs/nix-desktop-integration.md](docs/nix-desktop-integration.md) | nixpkgs の GUI アプリがランチャー/アイコンに出ない `XDG_DATA_DIRS` 問題と対処 | `hosts/ubuntu.nix`, 各 GUI モジュール |
| [docs/ibus-skk.md](docs/ibus-skk.md) | apt 版 1.4.3 のバグ、`IBUS_COMPONENT_PATH` によるエンジン登録、反映手順 | `pkgs/ibus-skk.nix`, `modules/ibus-skk/` (ubuntu) |
| [docs/xremap.md](docs/xremap.md) | Chrome のタブ移動リマップ、XKB レイヤとの関係、GNOME Wayland でのアプリ判定、root 作業 | `modules/xremap/` (ubuntu) |
| [docs/clipboard-image-paste.md](docs/clipboard-image-paste.md) | Claude Code への画像貼り付け。`Ctrl+V` が正解な理由、WSLg の BMP 問題と `wl-paste` shim、切り分け手順 | `hosts/wsl-gentoo.nix` (wsl-gentoo) |
