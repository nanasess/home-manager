# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

Nix Flake ベースの [Home Manager](https://github.com/nix-community/home-manager) 設定リポジトリ。WSL2 Gentoo Linux, Ubuntu, macOS の環境を1リポジトリで宣言的に管理する。

### 目標

- 1リポジトリで WSL2 Gentoo + Ubuntu + macOS の設定を管理
- Nix Flakes による宣言的な構成管理
- GitHub Actions CI で設定の乖離を防止
- Emacs + elpaca 環境の管理

### 環境情報

| 項目 | 値 |
|------|-----|
| ユーザー名 | `nanasess` |
| WSL ホームディレクトリ | `/home/nanasess` |
| macOS ホームディレクトリ | `/Users/nanasess` |
| CPU | AMD Ryzen Zen 3 (`-march=znver3`) |
| ロケール | `ja_JP.UTF-8` |
| SSH | 1Password SSH Agent (`~/.1password/agent.sock`) |

## コマンド

```bash
# flake の検証（CI でも実行される）
nix flake check

# wsl-gentoo の設定をビルド（ローカル確認用）
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'

# macOS の設定をビルド
nix build '.#homeConfigurations."nanasess@macbook".activationPackage'

# Ubuntu の設定をビルド
nix build '.#homeConfigurations."nanasess@ubuntu".activationPackage'

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
home-manager switch --flake '.#nanasess@macbook'
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

```
flake.nix              -- エントリポイント（inputs と homeConfigurations）
home.nix               -- 全ホスト共通設定（パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（WezTerm / Ghostty コピー、1Password CLI、WSLg X11/Wayland）
  ubuntu.nix           -- Ubuntu 固有設定（Ghostty、Walker、OneDrive）
  macos.nix            -- macOS 固有設定
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
  portage.nix          -- Portage 設定（WSL Gentoo 用、xdg.configFile で ~/.config/portage/ に書き出し）
  onedrive.nix         -- OneDrive 設定（WSL Gentoo 用）
.github/workflows/
  check.yml            -- CI 設定
```

### ホスト設定の追加パターン

1. `hosts/<hostname>.nix` を作成（ホスト固有の設定）
2. `flake.nix` の `homeConfigurations` にエントリを追加（`modules = [ ./home.nix ./hosts/<hostname>.nix ./modules/emacs ./modules/zsh ]`）
3. macOS ホストの場合は `pkgs` を `aarch64-darwin` の `legacyPackages` に変更

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

### 移行元リポジトリ (TODO)

以下のリポジトリからの移行状況。段階的にこのリポジトリへ統合する。

| リポジトリ | 移行対象 | 状態 |
|-----------|---------|------|
| `~/.config/dotfiles` | Zsh 設定、エイリアス、1Password SSH 連携 | 移行済み |
| `~/git-repos/gentoo-ansible` | Portage 設定 (make.conf, package.use 等) | 移行済み (`modules/portage.nix`) |

### フォーマッター

`nixpkgs-fmt` を使用。`nix fmt` で実行可能。`supportedSystems` は `x86_64-linux`, `aarch64-darwin`, `x86_64-darwin`。

## CI

GitHub Actions (`.github/workflows/check.yml`) が push/PR 時に以下を実行:
- **check** — `nix flake check` + WezTerm Lua 構文チェック
- **emacs** — `emacs --batch` による init.el の読み込みテスト（elpaca キャッシュ付き）
- **build** — 各ホストの `activationPackage` ビルド（matrix: ubuntu-latest, macos-15-intel）

## East Asian Ambiguous 文字幅 (locale-eaw)

glibc 2.39+ で `wcwidth()` が East Asian Ambiguous 文字 (△→○●■□▲ 等) に 1 を返すようになり、日本語環境で半角表示される問題に対処。[locale-eaw](https://github.com/hamano/locale-eaw) EAW-CONSOLE を使い、全レイヤーで文字幅を統一する。

### メカニズム

```
locale-eaw EAW-CONSOLE
├── glibc wcwidth()     -- LOCPATH でカスタムロケール適用 (△→=2, ─│=1)
├── WezTerm cell_widths -- eaw-console-wezterm.lua で同じ幅テーブルを適用
└── Emacs char-width-table -- eaw-console.el で同じ幅テーブルを適用

UDEV Gothic JPDOC (全角グリフ提供)
├── WezTerm -- プライマリフォント (NF は Nerd Font 用 fallback)
└── Emacs   -- プライマリフォント (set-fontset-font はフォールバック機構のため不可)
```

### 設計上の注意点

- **ロケール生成**: `localedef` でユーザー空間 (`~/.local/share/locale/ja_JP.utf8`) にコンパイル。ロケール名は `ja_JP.utf8` のまま、charmap だけ `UTF-8-EAW-CONSOLE` を使用。`LOCPATH` で既存システムロケールより優先。
- **WezTerm**: Windows 側で動作するため、Linux のフォントや LOCPATH は参照不可。`font_dirs` で JPDOC フォントを、`dofile` で cell_widths 設定を Windows 側からロード。
- **Emacs フォント**: `set-fontset-font` はフォールバック機構であり、プライマリフォントにグリフがある場合は無視される。そのため JPDOC をプライマリフォントとして設定する必要がある。
- **Emacs char-width-table**: `set-language-environment "Japanese"` が `char-width-table` をリセットするため、`eaw-console.el` はその後に読み込む。

## Windows on WezTerm

設定ソース: `modules/wezterm/wezterm.lua`
デプロイ先: `/mnt/c/Users/nanasess/.wezterm.lua`

`home.activation.weztermConfig` により `home-manager switch` 時に Windows 側へコピーされる。
ホームディレクトリ外（`/mnt/c/`）のため `home.file` のシンボリックリンクは使えず、`install` コマンドでコピーしている。
