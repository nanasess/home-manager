# home-manager

Nix Flake ベースの [Home Manager](https://github.com/nix-community/home-manager) 設定リポジトリ。
WSL2 Gentoo Linux, Ubuntu, macOS の環境を1リポジトリで宣言的に管理する。

## 対応ホスト

| ホスト名 | OS | 設定ファイル |
|---------|-----|------------|
| `nanasess@wsl-gentoo` | WSL2 Gentoo Linux | `hosts/wsl-gentoo.nix` |
| `nanasess@ubuntu` | Ubuntu (Wayland) | `hosts/ubuntu.nix` |
| `nanasess@macbook` | macOS (Intel) | `hosts/macos.nix` |

## セットアップ

### 前提条件

- [Nix](https://nixos.org/download/) がインストール済みであること（Flakes 有効）
- [Home Manager](https://github.com/nix-community/home-manager) がインストール済みであること

### 初回適用

```bash
# リポジトリをクローン
git clone https://github.com/nanasess/home-manager.git ~/.config/home-manager

# 設定を適用（ホスト名は環境に合わせて変更）
home-manager switch --flake '.#nanasess@wsl-gentoo'
```

## ディレクトリ構成

```
flake.nix              -- エントリポイント（inputs と homeConfigurations）
home.nix               -- 全ホスト共通設定（パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（WezTerm コピー、1Password CLI）
  ubuntu.nix           -- Ubuntu 固有設定（Ghostty、Walker、OneDrive）
  macos.nix            -- macOS 固有設定
modules/
  emacs/
    default.nix        -- Emacs モジュール（elpaca でパッケージ管理）
    init.el             -- Emacs 設定
    early-init.el       -- Emacs 早期初期化設定
    elpaca.lock         -- elpaca パッケージロックファイル
    init.d/             -- OS/環境別の追加設定
    site-lisp/          -- 自作 Elisp
  wezterm/
    wezterm.lua         -- WezTerm 設定（WSL → Windows 側にコピー）
  onedrive.nix          -- OneDrive 設定（WSL Gentoo 用）
.github/workflows/
  check.yml            -- CI（flake check, ビルド, Emacs batch test）
```

## パッケージ更新手順

### Nix パッケージの更新

```bash
# 1. flake.lock を更新（nixpkgs, home-manager 等の全 inputs を最新化）
nix flake update

# 2. ビルドして問題がないか確認（ドライラン）
home-manager switch --flake '.#nanasess@wsl-gentoo' --dry-run

# 3. 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'

# 4. 変更をコミット
git add flake.lock
git commit -m "chore: nix flake update"
```

特定の input のみ更新する場合:

```bash
nix flake update nixpkgs
nix flake update home-manager
```

### Emacs パッケージの更新 (elpaca)

`elpaca-lock-file` は `~/.config/home-manager/modules/emacs/elpaca.lock` を直接指しているため、
`M-x elpaca-write-lock-file` で home-manager ソースに直接書き出される（手動コピー不要）。

```bash
# 1. ロックファイルから復元した環境では全パッケージが detached HEAD のため、
#    まずブランチに戻す
M-x elpaca-checkout-branches

# 2. 全パッケージを更新
M-x elpaca-pull-all

# 3. 動作確認後、ロックファイルを書き出し（home-manager ソースに直接反映）
M-x elpaca-write-lock-file

# 4. 変更をコミット
cd ~/.config/home-manager
git add modules/emacs/elpaca.lock
git commit -m "chore(emacs): elpaca パッケージ更新"

# 5. home-manager に反映（elpaca.lock を ~/.emacs.d/ にコピー）
home-manager switch --flake '.#nanasess@wsl-gentoo'
```

特定のパッケージのみ更新する場合:

```bash
M-x elpaca-checkout-branches   # 必要に応じて
M-x elpaca-pull                # パッケージ名を指定
M-x elpaca-write-lock-file
```

### Nix + Emacs を一括更新

```bash
nix flake update
# Emacs で M-x elpaca-pull-all → M-x elpaca-write-lock-file
home-manager switch --flake '.#nanasess@wsl-gentoo'
git add flake.lock modules/emacs/elpaca.lock
git commit -m "chore: nix flake update + elpaca パッケージ更新"
```

## 設定変更の反映

Nix の設定ファイル (`*.nix`) や dotfiles を編集した後:

```bash
# ビルドの確認
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
```

## 開発コマンド

```bash
# flake の検証
nix flake check

# Nix ファイルのフォーマット (nixpkgs-fmt)
nix fmt

# 各ホストのビルド
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'
nix build '.#homeConfigurations."nanasess@macbook".activationPackage'
nix build '.#homeConfigurations."nanasess@ubuntu".activationPackage'

# ビルドログの確認
nix log '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'
```

## CI

GitHub Actions (`.github/workflows/check.yml`) が push / PR 時に以下を実行:

- **check** -- `nix flake check` + WezTerm Lua 構文チェック
- **emacs** -- `emacs --batch` による init.el の読み込みテスト（elpaca キャッシュ付き）
- **build** -- 各ホストの `activationPackage` ビルド（ubuntu-latest, macos-15-intel）

## TODO: 移行元リポジトリの統合

以下のリポジトリからの移行は未完了。段階的にこのリポジトリへ統合する。

| リポジトリ | 移行対象 |
|-----------|---------|
| `~/.config/dotfiles` | Zsh 設定、エイリアス、1Password SSH 連携 |
| `~/git-repos/gentoo-ansible` | Portage 設定 (make.conf, package.use 等)、パッケージ一覧 |

## ホストの追加

1. `hosts/<hostname>.nix` を作成
2. `flake.nix` の `homeConfigurations` にエントリを追加:
   ```nix
   "nanasess@<hostname>" = home-manager.lib.homeManagerConfiguration {
     pkgs = nixpkgs.legacyPackages.<system>;
     modules = [ ./home.nix ./hosts/<hostname>.nix ./modules/emacs ];
   };
   ```
3. `.github/workflows/check.yml` の build matrix にエントリを追加
