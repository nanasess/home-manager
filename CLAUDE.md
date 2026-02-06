# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

Nix Flake ベースの [Home Manager](https://github.com/nix-community/home-manager) 設定リポジトリ。WSL2 Gentoo Linux と macOS の環境を1リポジトリで宣言的に管理する。

### 目標

- 1リポジトリで WSL2 Gentoo + macOS の設定を管理
- Nix Flakes による宣言的な構成管理
- GitHub Actions CI で設定の乖離を防止
- Portage との併用（Gentoo 固有）
- Emacs + el-get 環境の管理

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

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
home-manager switch --flake '.#nanasess@macbook'

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

### 目標構成

```
flake.nix              -- エントリポイント。inputs と homeConfigurations を定義
home.nix               -- 全ホスト共通設定（ユーザー名、共通パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（Portage、WSL 環境変数）
  macos.nix            -- macOS 固有設定
modules/
  emacs/
    default.nix        -- Emacs モジュール（el-get でパッケージ管理、Nix はネイティブ依存のみ）
    init.el, early-init.el, lisp/
  zsh/
    default.nix        -- Zsh モジュール（sheldon + powerlevel10k）
    .zaliases, .p10k.zsh, eterm.zsh
  git.nix
  portage.nix          -- Portage 設定管理モジュール（Gentoo 用カスタムモジュール）
packages/
  common.nix           -- 共通 Nix パッケージ
  gentoo-portage.nix   -- Portage パッケージ宣言
.github/workflows/
  check.yml            -- CI 設定
```

### ホスト設定の追加パターン

1. `hosts/<hostname>.nix` を作成（ホスト固有の設定）
2. `flake.nix` の `homeConfigurations` にエントリを追加（`modules = [ ./home.nix ./hosts/<hostname>.nix ]`）
3. macOS ホストの場合は `pkgs` を `aarch64-darwin` の `legacyPackages` に変更

### 管理方針

| 管理対象 | ツール | 理由 |
|---------|--------|------|
| ユーザー環境・dotfiles | home-manager | 宣言的管理、CI 検証 |
| 開発ツール (CLI) | Nix | 環境再現性 |
| Gentoo システム基盤 | Portage | カーネル、ドライバ、USE flags |
| Portage 設定ファイル | home-manager → symlink | 宣言的に記述、手動同期 |
| Emacs ネイティブ依存 | Nix (vterm, pdf-tools, treesit-grammars) | ビルド依存の解決 |
| Emacs 純 Elisp パッケージ | el-get | 柔軟性、開発版追従 |
| Zsh プラグイン | sheldon | 既存のプラグイン管理を維持 |
| WSL 設定 (/etc/wsl.conf 等) | 手動 or ansible | システムレベルのため home-manager 対象外 |

### 移行元リポジトリ

| リポジトリ | 移行対象 |
|-----------|---------|
| `~/.config/dotfiles` | Zsh 設定、Emacs 設定、エイリアス、1Password SSH 連携 |
| `~/git-repos/gentoo-ansible` | Portage 設定 (make.conf, package.use 等)、パッケージ一覧 |

### Portage モジュール (`modules/portage.nix`)

home-manager のカスタムモジュールとして `/etc/portage` 配下の設定を宣言的に管理する。`services.portage` オプションで `makeConf`, `packageUse`, `packageAcceptKeywords`, `packageMask`, `packageUnmask`, `packageLicense` 等を定義し、`~/.config/portage/` に出力後、同期スクリプトで `/etc/portage` にシンボリックリンクを張る。

### フォーマッター

`nixpkgs-fmt` を使用。`nix fmt` で実行可能。`supportedSystems` は `x86_64-linux`, `aarch64-darwin`, `x86_64-darwin`。

## CI

GitHub Actions (`.github/workflows/check.yml`) が push/PR 時に以下を実行:
- `nix flake check` — flake の構文・評価検証
- 各ホストの `activationPackage` ビルド（matrix: ubuntu-latest + macos-latest）
- フォーマットチェック (`nix fmt -- --check .`)
- Portage の `package.use` 重複チェック（wsl-gentoo のみ）
