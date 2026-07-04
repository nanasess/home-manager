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

### Portage 設定のセットアップ（WSL Gentoo のみ）

Portage 設定は `~/.config/portage/` に書き出され、`/etc/portage/` 内の各ファイルから個別にシンボリックリンクします。
`gnupg/`, `make.profile`, `profile/` は root 管理のまま `/etc/portage/` に残します。

```bash
# 1. home-manager switch で ~/.config/portage/ を生成
home-manager switch --flake '.#nanasess@wsl-gentoo'

# 2. 管理対象ファイルのシンボリックリンクを作成（初回のみ）
for f in make.conf binrepos.conf package.accept_keywords package.mask package.unmask package.license; do
  sudo ln -sfn ~/.config/portage/$f /etc/portage/$f
done
sudo rm -rf /etc/portage/package.use /etc/portage/repos.conf
sudo ln -sfn ~/.config/portage/package.use /etc/portage/package.use
sudo ln -sfn ~/.config/portage/repos.conf /etc/portage/repos.conf

# 3. GnuPG 鍵の取得（未取得の場合）
sudo getuto
```

### SKK 辞書サーバ (yaskkserv2) のセットアップ（WSL Gentoo / Ubuntu 共通）

Emacs (nskk) の辞書本体を skkserv (yaskkserv2) に逃がし、nskk が全辞書を起動時にトライ索引へ全件展開することで full GC が 20-50 秒かかる問題を回避します。サーバは `modules/yaskkserv2.nix` が **systemd ユーザーサービス**として管理します（`/etc` も sudo も OpenRC も不要）。

バイナリ (`yaskkserv2` / `yaskkserv2_make_dictionary`) は nixpkgs / apt に無いため `pkgs/yaskkserv2.nix` で **Nix ビルド**し、両ホストで同一バイナリを共有します。配信辞書はユーザーパス `~/.local/share/yaskkserv2/all` に置くため、セットアップは **すべて sudo 不要**です。

```bash
# 1. home-manager switch でバイナリ導入 + 設定生成 + ユーザーサービス起動
#    （<host> は wsl-gentoo または ubuntu）
home-manager switch --flake '.#nanasess@<host>'

# 2. 配信辞書を SKK-JISYO.all.utf8 からビルド（初回 + 辞書更新時のみ再実行）
#    yaskkserv2_make_dictionary は上記 switch で ~/.nix-profile/bin に入る
mkdir -p ~/.local/share/yaskkserv2
yaskkserv2_make_dictionary \
  --dictionary-filename ~/.local/share/yaskkserv2/all \
  --utf8 "$HOME/OneDrive - Skirnir Inc/emacs/ddskk/SKK-JISYO.all.utf8"

# 3. 辞書生成後にサービスを再起動して読み込ませる
systemctl --user restart yaskkserv2

# 4. 稼働確認
systemctl --user status yaskkserv2

# 5. 変換動作確認（UTF-8 ワイヤ。1/愛/相/... が返れば OK。nc 不要）
python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",1178),2); s.sendall("1あい ".encode()); print(s.recv(8192).decode("utf-8","replace"))'
```

設定 (`modules/yaskkserv2.nix`) を変更したら `home-manager switch` で自動反映されます（手動再起動が要る場合は `systemctl --user restart yaskkserv2`）。`listen-address = 127.0.0.1`（LAN へ露出しない）ですが、WSL2 では localhostForwarding 経由で Windows からも `localhost:1178` で接続できます。

### システムパッケージの確認

各ホストでシステムパッケージマネージャ（portage/apt/Homebrew）のパッケージが揃っているか確認できます。

```bash
~/.local/bin/check-system-packages
```

### mise PHP のセットアップ

```bash
# PHP インストール
mise install php@8.3

# カスタム設定（memory_limit 等）
echo "memory_limit=1G" > ~/.local/share/mise/installs/php/8.3.30/conf.d/custom.ini

# PECL 拡張の追加
pecl install redis
echo "extension=redis.so" > ~/.local/share/mise/installs/php/8.3.30/conf.d/redis.ini

# 確認
php -m | grep redis
php -r 'echo ini_get("memory_limit")."\n";'
```

## ディレクトリ構成

```
flake.nix              -- エントリポイント（inputs と homeConfigurations）
home.nix               -- 全ホスト共通設定（パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（WezTerm コピー、1Password CLI、WSLg）
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
    default.nix         -- locale-eaw モジュール（localedef + LOCPATH 設定）
    UTF-8-EAW-CONSOLE.gz -- East Asian Ambiguous 文字幅修正済み charmap
    eaw-console-wezterm.lua -- WezTerm cell_widths 設定
    eaw-console.el      -- Emacs char-width-table 設定
  wezterm/
    wezterm.lua         -- WezTerm 設定（WSL → Windows 側にコピー）
  portage.nix           -- Portage 設定（WSL Gentoo 用、~/.config/portage/ に書き出し）
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

elpaca はロックファイルの `:ref` で各パッケージを特定コミットに固定するため、
`~/.emacs.d/elpaca/sources/<pkg>/` は通常 detached HEAD 状態になっている。
そのまま `elpaca-pull-all` を実行すると pull 先ブランチが特定できず失敗するので、
事前にブランチを復元する必要がある（init.el で定義されている `elpaca-checkout-branches` を使う）。

#### 標準手順

```bash
# 1. 全パッケージを default branch に戻す（detached HEAD 解消）
M-x elpaca-checkout-branches

# 2. 全パッケージを更新
M-x elpaca-pull-all

# 3. 動作確認後、ロックファイルを書き出し
M-x elpaca-write-lock-file

# 4. 変更をコミット
cd ~/.config/home-manager
git add modules/emacs/elpaca.lock
git commit -m "chore(emacs): elpaca パッケージ更新"

# 5. home-manager に反映
home-manager switch --flake '.#nanasess@wsl-gentoo'
```

#### 既知の制約: 一部パッケージは手動 checkout が必要

`elpaca-checkout-branches` は `git symbolic-ref refs/remotes/origin/HEAD` で default branch を判定するため、
以下のような GNU ELPA mirror 由来でリモートに `origin/HEAD` シンボリックリンクがなく、
かつ default が `main` / `master` でないパッケージでは復帰できない:

- `csv-mode` (default branch: `externals/csv-mode`)
- `queue` (default branch: `externals/queue`)

これらは `elpaca-pull-all` のログでエラーになっていれば手動で checkout する:

```bash
cd ~/.emacs.d/elpaca/sources/csv-mode && git checkout externals/csv-mode
cd ~/.emacs.d/elpaca/sources/queue    && git checkout externals/queue
```

その後あらためて `M-x elpaca-pull-all` を実行する。

#### lock のリビジョンに追従する（composer install / npm ci 相当）

上記「標準手順」はパッケージを最新化して lock を書き直す **更新**手順（`composer update` / `npm update` 相当）。
一方、**lock に固定済みのリビジョンへローカルを合わせたい**場合（別マシンでの再現、
CI や PR で更新された `elpaca.lock` の取り込み等）は手順が異なる。

**注意:** `elpaca-pull-all` は default branch の最新へ更新するため lock 追従には使えない。
`elpaca-checkout-branches` も detached HEAD（= lock 固定状態）を解除してしまうので実行しない。

elpaca には lock 全体を一括復元する専用コマンドが無いため、対象の `builds` / `sources` を
削除して再インストールさせるのが最も確実（`rm -rf node_modules && npm ci` 相当）。
`elpaca-menu-lock-file` が最優先 menu のため、まっさらな状態から入れ直すと各パッケージは
`elpaca.lock` の `:ref` でインストールされる。

```bash
# 1. 最新の init.el / elpaca.lock を反映（PR やブランチを適用済みにしてから）
home-manager switch --flake '.#nanasess@wsl-gentoo'

# 2a. 特定パッケージだけ lock の :ref に合わせる場合（推奨・高速）
rm -rf ~/.emacs.d/elpaca/builds/<pkg> ~/.emacs.d/elpaca/sources/<pkg>
#    例: nskk を elpaca.lock のリビジョンに追従させる
rm -rf ~/.emacs.d/elpaca/builds/nskk ~/.emacs.d/elpaca/sources/nskk

# 2b. 全パッケージを lock の :ref に合わせる場合（elpaca 本体も再 bootstrap される）
rm -rf ~/.emacs.d/elpaca/builds ~/.emacs.d/elpaca/sources

# 3. Emacs を起動
#    elpaca が elpaca.lock の :ref で対象パッケージを clone / checkout し直す
```

削除したパッケージは次回起動時に lock の `:ref`（detached HEAD）で入り直すため、
`M-x elpaca-write-lock-file` は不要（lock は変更しない）。

### Nix + Emacs を一括更新

```bash
nix flake update
# Emacs で M-x elpaca-checkout-branches → M-x elpaca-pull-all → M-x elpaca-write-lock-file
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

## East Asian Ambiguous 文字幅 (locale-eaw)

glibc 2.39+ で East Asian Ambiguous 文字 (△→○●■□▲ 等) の `wcwidth()` が 2→1 に変更され、日本語環境で半角表示される問題に対処している。

[locale-eaw](https://github.com/hamano/locale-eaw) EAW-CONSOLE を使い、glibc / WezTerm / Emacs の全レイヤーで文字幅を統一する。

| レイヤー | 設定 | 効果 |
|---------|------|------|
| glibc (`wcwidth`) | `localedef` + `LOCPATH` でカスタムロケール適用 | zsh 等のカーソル位置が正確に |
| WezTerm | `cell_widths` (eaw-console-wezterm.lua) | ターミナル描画幅が一致 |
| Emacs | `eaw-console.el` で `char-width-table` 設定 | Emacs 内部の文字幅が一致 |
| フォント | UDEV Gothic JPDOC をプライマリフォント | 全角グリフで描画 |

罫線 (─│) は半角のまま維持されるため、TUI アプリやプロンプトの表示は崩れない。

## TODO: 移行元リポジトリの統合

以下のリポジトリからの移行は未完了。段階的にこのリポジトリへ統合する。

| リポジトリ | 移行対象 | 状態 |
|-----------|---------|------|
| `~/.config/dotfiles` | Zsh 設定、エイリアス、1Password SSH 連携 | 移行済み |
| `~/git-repos/gentoo-ansible` | Portage 設定 (make.conf, package.use 等) | 移行済み (`modules/portage.nix`) |

## ホストの追加

1. `hosts/<hostname>.nix` を作成
2. `flake.nix` の `homeConfigurations` にエントリを追加:
   ```nix
   "nanasess@<hostname>" = home-manager.lib.homeManagerConfiguration {
     pkgs = nixpkgs.legacyPackages.<system>;
     modules = [ ./home.nix ./hosts/<hostname>.nix ./modules/emacs ./modules/zsh ];
   };
   ```
3. `.github/workflows/check.yml` の build matrix にエントリを追加
