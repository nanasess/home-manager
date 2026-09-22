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

# k-2 (NixOS, T2 Mac) のシステム設定を評価 / ビルド
# toplevel は linux-t2 カーネルと Apple 復旧イメージ (KVM 必須) を抱えるので、
# 他ホストでは評価 + home-manager 部分のビルドまでに留める (docs/nixos-t2.md)
nix eval --raw '.#nixosConfigurations.k-2.config.system.build.toplevel.drvPath'
nix build '.#nixosConfigurations.k-2.config.home-manager.users.nanasess.home.activationPackage'

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
home-manager switch --flake '.#nanasess@ubuntu'
sudo nixos-rebuild switch --flake '.#k-2'   # NixOS ホスト (home-manager も同時に適用)

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
flake.nix              -- エントリポイント（inputs、homeConfigurations、nixosConfigurations）
home.nix               -- 全ホスト共通設定（パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（WezTerm / Ghostty コピー、1Password CLI、WSLg X11/Wayland）
  ubuntu.nix           -- Ubuntu 固有設定（Ghostty (nixGL)、apt 差分チェック、GNOME 拡張）
  k-2/                 -- NixOS (Intel MacBook Pro 2020, T2)。Ubuntu からの移行先 (docs/nixos-t2.md)
    configuration.nix  -- システム設定（apple-t2、GRUB、GNOME、NetworkManager + l2tp、usbmuxd (iPhone テザリング)、1Password、ibus、nix-ld + Playwright 用ライブラリ、蓋閉じ suspend + Touch Bar 復帰フック）
    hardware-configuration.nix -- ディスク (LABEL 参照) / カーネルモジュール
    home.nix           -- ユーザー環境（hosts/ubuntu.nix の NixOS 版）
    scripts/backup-before-install.sh -- インストール前の退避（ファームウェア / ESP イメージ / システム情報）
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
    site-lisp/          -- 自作 Elisp + eaw-console.el（Emacs GUI 限定の EAW 文字幅設定）
  wezterm/
    wezterm.lua        -- WezTerm 設定（WSL → Windows 側にコピー）
  ghostty/
    default.nix        -- Ghostty 共有設定（Linux native / Windows port (PR #12167) 両対応、_module.args で公開）
  bluetooth-audio/
    default.nix        -- Bluetooth オーディオ（HFP 自動切替の無効化 + pavucontrol。GNOME ホスト共通）
    51-disable-headset-autoswitch.lua -- WirePlumber 0.4 (ubuntu) の自動プロファイル切替を無効化
    51-disable-headset-autoswitch.conf -- 同 0.5 以降 (NixOS) 用
  ibus-skk/
    default.nix        -- ibus-skk の辞書設定 (dconf、ホスト共通)
    ubuntu.nix         -- IBus SKK エンジン登録（Nix ビルドの 1.4.4 + IBUS_COMPONENT_PATH。ubuntu 用）
  walker/
    default.nix        -- Walker / Elephant ランチャー（systemd ユーザーサービス + GNOME キーバインド。GNOME ホスト共通）
  xremap/
    default.nix        -- キーリマッパー（Chrome のタブ移動を Ctrl+H / Ctrl+L に。GNOME ホスト共通）
  portage.nix          -- Portage 設定（WSL Gentoo 用、xdg.configFile で ~/.config/portage/ に書き出し）
  onedrive.nix         -- OneDrive 設定（WSL Gentoo 用）
  yaskkserv2.nix       -- SKK 辞書サーバ（systemd ユーザーサービス。wsl-gentoo / ubuntu 共通）
pkgs/
  yaskkserv2.nix       -- yaskkserv2 の自作 Nix derivation（buildRustPackage、nixpkgs 未収録のため）
  ibus-skk.nix         -- ibus-skk 1.4.4 の自作 Nix derivation（nixpkgs 未収録 + apt は 1.4.3 で停滞）
  mew.nix              -- Mew (Emacs メーラ) の外部コマンド mewl / mewencode / incm / cmew / smew（emacsPackages.mew は elisp のみで bin/ を含まない）
  chatgpt/             -- ChatGPT デスクトップアプリ (Linux 版) の deb 再パッケージ（nixpkgs の chatgpt は Darwin 専用。source.nix + update.sh でバージョン固定 / 追従）
shells/
  php-build.nix        -- mise php プラグイン (ソースビルド) 用 devShell（NixOS には FHS のツールチェーンが無いため）
docs/                  -- 領域別の詳細ドキュメント（下記「詳細ドキュメント」参照）
.github/workflows/
  check.yml            -- CI 設定
```

### ホスト設定の追加パターン

1. `hosts/<hostname>.nix` を作成（ホスト固有の設定）
2. `flake.nix` の `homeConfigurations` にエントリを追加（`modules = [ ./home.nix ./hosts/<hostname>.nix ./modules/emacs ./modules/zsh ]`）

NixOS ホストは `hosts/<hostname>/{configuration,hardware-configuration,home}.nix` を作り、
`flake.nix` の `nixosConfigurations` に `nixpkgs.lib.nixosSystem` で追加する。home-manager は
NixOS モジュールとして読み込み `useUserPackages = true` にする (`useGlobalPkgs` は `home.nix` の
`nixpkgs.config` と衝突するので使わない)。GNOME ホスト共通の home-manager モジュールは
`flake.nix` の `gnomeHomeModules` にまとめてある。

home-manager モジュール内で Nix プロファイルのパスが要るときは `config.home.profileDirectory`
を使う。`~/.nix-profile` を直書きすると NixOS (`/etc/profiles/per-user/<user>`) で壊れる。

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
| East Asian Ambiguous 文字幅 | Emacs GUI のみ locale-eaw `eaw-console.el` | ターミナル (noctty / Ghostty 系) は Ambiguous を幅 1 に固定していて変更不可。glibc / ターミナル側は素の幅 1 に統一し、独立レンダラの Emacs GUI だけ幅 2 を維持。Emacs tty フレームは `use-default-char-width-table` で幅 1 に戻す (既定は罫線まで幅 2 になる) |
| Portage 設定 | home-manager (xdg.configFile) | `~/.config/portage/` に書き出し、`/etc/portage/` から個別にシンボリックリンク |
| システムパッケージ一覧 | Nix リスト + チェックスクリプト | 各ホストの nix ファイルで宣言、`check-system-packages` で差分確認 |
| SKK 辞書サーバ (yaskkserv2) | Nix ビルド (`pkgs/yaskkserv2.nix`) + systemd ユーザーサービス (`modules/yaskkserv2.nix`) | nixpkgs / apt に無いため上流を `buildRustPackage`。全ホスト同一バイナリ + ユーザーパス辞書 (`~/.local/share/yaskkserv2/all`) で sudo 不要・共通化 |
| IBus SKK エンジン | Nix ビルド (`pkgs/ibus-skk.nix`) + `IBUS_COMPONENT_PATH` (`modules/ibus-skk/`) | apt / nixpkgs とも 1.4.4 未提供。apt 版 1.4.3 は変換確定が壊れる（`docs/ibus-skk.md`）。IBus は `XDG_DATA_DIRS` を見ないため `systemd.user.sessionVariables` でエンジンを登録する |
| Mew (Emacs メーラ、Gmail XOAUTH2) | elisp は elpaca (`use-package mew`)、外部コマンドは Nix (`pkgs/mew.nix`)、秘密情報は 1Password (`op://Personal/Mew Gmail XOAUTH2/…` を `M-x mew` 初回に `op read`) | `emacsPackages.mew` は elisp のみで `bin/` を含まず、nixpkgs の `mew` は無関係 (dmenu の Wayland 移植)。OAuth2 トークンは master password 方式 (`~/Mail/.mew-passwd.gpg`) でしか永続化されないため master password も 1Password から供給する（`docs/mew.md`）。elisp と bin は同じ上流コミットに固定する |
| ChatGPT デスクトップアプリ | Nix ビルド (`pkgs/chatgpt/`) + `hosts/k-2/configuration.nix` の systemPackages | nixpkgs の `chatgpt` は Darwin 専用。OpenAI 公式 deb (Electron) を dpkg 展開 + autoPatchelf で包む。`latest` URL は中身が変わるので apt pool のバージョン付き URL + SHA256 に固定し、`pkgs/chatgpt/update.sh` が Packages インデックスから `source.nix` を更新。同梱プラグインの `~/.codex/.tmp/` へのコピーが Nix ストアの 555 モードを写して EACCES になるため app.asar を展開 → chmod 挿入 → 再パックしている（詳細は `default.nix` のコメント）。Codex ランタイム (`~/.codex/`) はアプリが自己更新する管理外状態 |
| キーリマップ (xremap) | Nix (`xremap` gnome variant) + systemd ユーザーサービス (`modules/xremap/`) | Chrome にキーバインド変更機能が無いため evdev/uinput レベルで置換。アプリ判定に GNOME Shell 拡張が要る。`input` グループ / udev ルールのみ root 作業として残る |
| Bluetooth オーディオ | home-manager (xdg.configFile) + pavucontrol | WirePlumber の HFP 自動切替を無効化し、A2DP (ステレオ) / HFP (マイク) は pavucontrol で手動切替。プロファイルの記憶 (`~/.local/state/wireplumber/`) はランタイム状態のため管理外 |
| クリップボード画像 (WSL) | `wl-paste` shim (`hosts/wsl-gentoo.nix`) | WSLg が `image/bmp` しか出さず Claude Code が扱えないため、`image/png` を追加広告して ImageMagick で変換（`docs/clipboard-image-paste.md`） |
| PHP (mise) | mise php プラグイン (ソースビルド) + ビルド依存はホスト別 | wsl-gentoo は portage、k-2 は `nix develop .#php-build` (`shells/php-build.nix`)。gettext / readline / gmp の `configure` は `/usr` 直下しか探さないので devShell が `PHP_EXTRA_CONFIGURE_OPTIONS` でストアパスを渡す。RPATH に `/nix/store` が焼き込まれるため `--profile` で GC root を作る (README「mise PHP のセットアップ」) |
| Playwright ブラウザ (k-2) | 公式配布バイナリ (`playwright install`) + `programs.nix-ld.libraries` (`hosts/k-2/configuration.nix`) | nixpkgs の `playwright-driver` (1.61) はプロジェクト側 (`@playwright/test` 1.63) とブラウザリビジョンが合わず、nixpkgs 側で追従すると更新のたびに hash 更新が要る。Chromium の実行時ライブラリだけ nix-ld に載せて公式バイナリを使う (`playwright install-deps` 相当)。nixpkgs に依存ライブラリのみのパッケージは無い (2026-09 時点) |

**プラットフォーム非依存化の判断基準**: portage / apt など特定ホストのパッケージマネージャに依存する構成は、入手経路が「バイナリ + 付随ツール」だけの問題であれば **Nix パッケージ化 (必要なら `pkgs/` に自作 derivation) して全ホスト共通化する**ことを優先する。辞書・データ類はシステムパス (`/usr/lib` 等、要 sudo) ではなくユーザーパス (`xdg.dataHome` 配下) に置き、セットアップを sudo レスにする。yaskkserv2 はこの方針で wsl-gentoo (旧 portage) と ubuntu を統一した先例 (PR #110)。

### Emacs パッケージ (elpaca) の更新手順

`modules/emacs/elpaca.lock` は全パッケージを `:ref` でピン留めしており (`elpaca-menu-lock-file`)、
`~/.emacs.d/elpaca/sources/*` はすべて detached HEAD になっている。このため
**`M-x elpaca-pull-all` / `elpaca-merge-all` は使えない**。`elpaca-fetch` はピン留めを検出して
スキップするが、merge 側にはそのチェックが無く、`elpaca-git--merge` が引数なしの
`git merge --ff-only` を実行して `fatal: No current branch.` (exit 128) で全パッケージが
「Subprocess error」になる。更新は lock の `:ref` を書き換える。

1. **上流を取る**: `git -C ~/.emacs.d/elpaca/sources/<Repo> fetch origin` して新しい rev を決める
   (デフォルトブランチは上流により `master` / `main`。`origin/HEAD` を見る)。
2. **lock を書き換える**: `modules/emacs/elpaca.lock` の当該パッケージの `:ref`。対応する
   derivation が `pkgs/` にある場合 (Mew など) は rev / version / hash も同じコミットに揃える。
   hash は `nix flake prefetch --json github:<owner>/<repo>/<rev>` で取り、`nix build` で確認する。
3. **検証**: `nix flake check` と対象ホストの `activationPackage` ビルド。
4. **適用**: `home-manager switch` (lock は activation で `~/.emacs.d/elpaca.lock` に install される)。
5. **ソースを切り替える**: `git -C ~/.emacs.d/elpaca/sources/<Repo> checkout <rev>`。
   `elpaca-rebuild` のビルドステップに checkout は含まれない (`elpaca-check-version` /
   `elpaca-build-link` / `-autoloads` / `-compile` / `-docs` のみ) ので手動で行う。
6. **Emacs を再起動してから `M-x elpaca-rebuild <pkg>`**。再起動が先なのは、`elpaca-rebuild` が
   `:rebuild` 用のステップに差し替えるのは status が `finished` のときだけで、`elpaca-pull-all` が
   失敗したセッションでは古いステップ (merge) を再実行してまた失敗するため。ビルド後、対象を
   すでに load しているなら再起動して新しい `.elc` を読ませる。

**`advice-add` と native-comp**: `modules/emacs/early-init.el` の `native-comp-speed` は既定値の
2 のままにする。3 にするとネイティブコンパイラが「同じコンパイル単位 (同一ファイル) の関数は
再定義されない」と仮定して呼び出しを直接化し、**`advice-add` と関数の再定義が素通りされる**。
他人のパッケージの内部関数に advice を当てている設定 (init.el の `mew-read-passwd` /
`mew-oauth2-get-auth-code` / `lsp-bridge--mode-line-format`) はこの最適化と両立しない。
実例と切り分け方は `docs/mew.md`「native-comp-speed と advice」。speed を変えても `.eln` の
ファイル名は変わらないので、戻した後は `M-x elpaca-rebuild` か `~/.emacs.d/eln-cache/` の削除で
再コンパイルさせること。

### ChatGPT デスクトップアプリの更新手順

「chatgpt を更新しておいて」と指示されたら、以下を一連で実行して PR まで作る。
上流 (OpenAI の apt リポジトリ) は月に数回更新され、Nix 側は `pkgs/chatgpt/source.nix` の
version / hash を差し替えるだけで追従できる。

1. **source.nix を更新**: main を最新にした状態で `./pkgs/chatgpt/update.sh`。apt の Packages インデックスから `Package: chatgpt` の最新スタンザを読んで `source.nix` を書き換え、バージョンを表示する (deb 本体は落とさない)。`git diff pkgs/chatgpt/source.nix` が空なら既に最新なのでその旨を報告して終了する。
2. **ブランチを切る**: `git checkout -b chore/chatgpt-<新バージョン>` (手順 1 の変更は作業ツリーに残ったまま新ブランチに持ち越される)。
3. **ビルド**: `nix build .#chatgpt` (400MB 弱の deb を取得するので数分かかる)。失敗したら原因は次のどちらか:
   - `substituteInPlace ... --replace-fail` で止まった → 上流が `fs.cp` でプラグインをコピーする箇所を変えた。`asar extract` で新しい `main-*.js` を取り出し、`verbatimSymlinks` 付近を `grep` して置換パターンを合わせる (`default.nix` の該当コメント参照)。パッチの目的は「コピー直後に宛先を `chmod -R u+w` する」ことなので、それが満たせれば形は変えてよい。
   - `auto-patchelf could not satisfy dependency` → 新しい共有ライブラリ依存が増えた。NEEDED を見て `buildInputs` に足す。Qt や musl のような環境依存でしか使わないものは `autoPatchelfIgnoreMissingDeps` に追加する。
4. **起動確認** (k-2 上で作業しているとき): `./result/bin/chatgpt > /tmp/chatgpt.log 2>&1 &` で 20 秒ほど走らせ、ログに `window ready-to-show` と `plugin_marketplace_folder_write_succeeded` があり `EACCES` が無いことを確認して `pkill -x ChatGPT` で止める (`pkill -f` はシェル自身を巻き込むので使わない)。401 / `Unauthorized` は未ログインなだけで正常。k-2 以外では省略し、未検証と報告する。
5. **flake 検証**: `nix flake check` と `nix eval --raw '.#nixosConfigurations.k-2.config.system.build.toplevel.drvPath'`。
6. **コミット / PR**: `chore(chatgpt): <旧> → <新> に更新` でコミットし、PR 本文に手順 3〜5 の結果を書く。`result` シンボリックリンクはコミットしない。CI はポーリングせず、PR URL を報告して終える。
7. **適用はユーザーが行う**: `sudo nixos-rebuild switch --flake .#k-2`。ロールバックは `source.nix` の revert または `nixos-rebuild switch --rollback`。

補足: アプリは `~/.codex/` 配下の Codex ランタイムを自分でダウンロードして自己更新するので、
Nix 側の更新はあくまで Electron 本体 (deb) の追従。in-app updater は apt 前提のため NixOS では
効かない。ライブラリ依存の全体像 (Electron が dlopen するもの含む) は
`pkgs/chatgpt/default.nix` のコメントにまとめてある。

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
- **nixos** — `nixosConfigurations.k-2` の toplevel 評価 + home-manager 部分のビルド（カーネルとファームウェアは CI で作らない）

## 詳細ドキュメント (`docs/`)

環境ごとの調査結果・落とし穴は `docs/` に分離してある。該当領域を触るときに読むこと。

| ドキュメント | 内容 | 主な対象 |
|---|---|---|
| [docs/eaw-width.md](docs/eaw-width.md) | East Asian Ambiguous 文字幅の方針 (ターミナル系は幅 1、Emacs GUI のみ幅 2)、noctty が幅 1 固定である理由 | `modules/emacs/site-lisp/eaw-console.el` |
| [docs/wezterm.md](docs/wezterm.md) | WezTerm 設定を WSL 側から Windows 側へコピーする経路 | `modules/wezterm/` |
| [docs/bluetooth-audio.md](docs/bluetooth-audio.md) | 接続不安定 (マルチポイント / discovery 枯渇 / WiFi 2.4GHz) の切り分け、A2DP と HFP の排他、自動切替の無効化 | `modules/bluetooth-audio/` (ubuntu) |
| [docs/nix-desktop-integration.md](docs/nix-desktop-integration.md) | nixpkgs の GUI アプリがランチャー/アイコンに出ない `XDG_DATA_DIRS` 問題と対処 | `hosts/ubuntu.nix`, 各 GUI モジュール |
| [docs/ibus-skk.md](docs/ibus-skk.md) | apt 版 1.4.3 のバグ、`IBUS_COMPONENT_PATH` によるエンジン登録、反映手順 | `pkgs/ibus-skk.nix`, `modules/ibus-skk/` (ubuntu) |
| [docs/xremap.md](docs/xremap.md) | Chrome のタブ移動リマップ、XKB レイヤとの関係、GNOME Wayland でのアプリ判定、root 作業 | `modules/xremap/` (ubuntu) |
| [docs/clipboard-image-paste.md](docs/clipboard-image-paste.md) | Claude Code への画像貼り付け。`Ctrl+V` が正解な理由、WSLg の BMP 問題と `wl-paste` shim、切り分け手順 | `hosts/wsl-gentoo.nix` (wsl-gentoo) |
| [docs/nixos-t2.md](docs/nixos-t2.md) | T2 Mac での NixOS。nixos-hardware apple-t2 の仕組み、ファームウェア抽出 (KVM 必須)、カーネルのバイナリキャッシュ、ESP 300MB と GRUB、インストール手順 | `hosts/k-2/` (k-2) |
| [docs/mew.md](docs/mew.md) | Mew の Gmail XOAUTH2 + 1Password 化。master password 方式が必要な理由、1Password アイテムと Google OAuth クライアントの作り方、初回認可、旧設定からの差分、MS365 を足す場合 | `pkgs/mew.nix`, `modules/emacs/init.el` (Email (Mew)) |
