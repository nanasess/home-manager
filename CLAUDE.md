# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

Nix Flake ベースの [Home Manager](https://github.com/nix-community/home-manager) 設定リポジトリ。WSL2 (Gentoo Linux / NixOS), Ubuntu, NixOS の環境を1リポジトリで宣言的に管理する。

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
| SSH | 1Password SSH Agent (`~/.1password/agent.sock`)。WSL での Windows 版 / Linux 版の役割分担は `docs/1password-wsl.md` |

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

# wsl-nixos (NixOS-WSL) のシステム設定を評価 / ビルド (カーネルを持たないので toplevel もビルドできる)
nix eval --raw '.#nixosConfigurations.wsl-nixos.config.system.build.toplevel.drvPath'
nix build '.#nixosConfigurations.wsl-nixos.config.home-manager.users.nanasess.home.activationPackage'

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
home-manager switch --flake '.#nanasess@ubuntu'
sudo nixos-rebuild switch --flake '.#k-2'   # NixOS ホスト (home-manager も同時に適用)
sudo nixos-rebuild switch --flake '.#wsl-nixos'

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
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（gentooPackages と check-system-packages、op の setgid バイナリのパス）。WSL 共通部分は modules/wsl
  ubuntu.nix           -- Ubuntu 固有設定（Ghostty (nixGL)、apt 差分チェック、GNOME 拡張）
  k-2/                 -- NixOS (Intel MacBook Pro 2020, T2)。Ubuntu からの移行先 (docs/nixos-t2.md)
    configuration.nix  -- システム設定（apple-t2、GRUB、GNOME、NetworkManager + l2tp、usbmuxd (iPhone テザリング)、1Password、ibus、nix-ld + Playwright 用ライブラリ、蓋閉じ suspend + Touch Bar 復帰フック、restic → NAS バックアップ）
    hardware-configuration.nix -- ディスク (LABEL 参照) / カーネルモジュール
    home.nix           -- ユーザー環境（hosts/ubuntu.nix の NixOS 版）
    scripts/backup-before-install.sh -- インストール前の退避（ファームウェア / ESP イメージ / システム情報）
  wsl-nixos/           -- NixOS-WSL。wsl-gentoo からの移行先 (issue #183。導入手順は README)
    configuration.nix  -- システム設定（NixOS-WSL の wsl.*、Docker Desktop 統合、sudo はパスワード必須、DNS は WSL 生成の resolv.conf）
    home.nix           -- ユーザー環境（WSL 共通は modules/wsl、wsl.opLinux = /run/wrappers/bin/op、WSLg スタートメニュー用の 1Password / Chrome の .desktop）
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
  nixos/
    common.nix         -- NixOS ホスト共通のシステム設定（zsh、nix-ld + Playwright 用ライブラリ、1Password、Chrome の 1Password 拡張）。unfree 許可は各ホスト
  wsl/
    default.nix        -- WSL ホスト共通（Windows 側への noctty / Ghostty 設定・ssh config + conf.d ミラー・UDEV Gothic・mackerel のコピー、op シム、wl-paste shim、gpg-agent、WSLg X11/Wayland）
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
| Ghostty 設定 | 共有 Nix attrset + renderer | `programs.ghostty.settings` (Linux native) と `%LOCALAPPDATA%\{noctty,ghostty}\config.ghostty` (Windows 側、activation でコピー) を同一 attrset から生成 |
| East Asian Ambiguous 文字幅 | Emacs GUI のみ locale-eaw `eaw-console.el` | ターミナル (noctty / Ghostty 系) は Ambiguous を幅 1 に固定していて変更不可。glibc / ターミナル側は素の幅 1 に統一し、独立レンダラの Emacs GUI だけ幅 2 を維持。Emacs tty フレームは `use-default-char-width-table` で幅 1 に戻す (既定は罫線まで幅 2 になる) |
| Portage 設定 | home-manager (xdg.configFile) | `~/.config/portage/` に書き出し、`/etc/portage/` から個別にシンボリックリンク |
| システムパッケージ一覧 | Nix リスト + チェックスクリプト | 各ホストの nix ファイルで宣言、`check-system-packages` で差分確認 |
| SKK 辞書サーバ (yaskkserv2) | Nix ビルド (`pkgs/yaskkserv2.nix`) + systemd ユーザーサービス (`modules/yaskkserv2.nix`) | nixpkgs / apt に無いため上流を `buildRustPackage`。全ホスト同一バイナリ + ユーザーパス辞書 (`~/.local/share/yaskkserv2/all`) で sudo 不要・共通化 |
| IBus SKK エンジン | Nix ビルド (`pkgs/ibus-skk.nix`) + `IBUS_COMPONENT_PATH` (`modules/ibus-skk/`) | apt / nixpkgs とも 1.4.4 未提供。apt 版 1.4.3 は変換確定が壊れる（`docs/ibus-skk.md`）。IBus は `XDG_DATA_DIRS` を見ないため `systemd.user.sessionVariables` でエンジンを登録する |
| Mew (Emacs メーラ、Gmail XOAUTH2) | elisp は elpaca (`use-package mew`)、外部コマンドは Nix (`pkgs/mew.nix`)、秘密情報は 1Password (`op://Personal/Mew Gmail XOAUTH2/…` を `M-x mew` 初回に `op read`) | `emacsPackages.mew` は elisp のみで `bin/` を含まず、nixpkgs の `mew` は無関係 (dmenu の Wayland 移植)。OAuth2 トークンは master password 方式 (`~/Mail/.mew-passwd.gpg`) でしか永続化されないため master password も 1Password から供給する（`docs/mew.md`）。elisp と bin は同じ上流コミットに固定する |
| ChatGPT デスクトップアプリ | Nix ビルド (`pkgs/chatgpt/`) + `hosts/k-2/configuration.nix` の systemPackages | nixpkgs の `chatgpt` は Darwin 専用。OpenAI 公式 deb (Electron) を dpkg 展開 + autoPatchelf で包む。`latest` URL は中身が変わるので apt pool のバージョン付き URL + SHA256 に固定し、`pkgs/chatgpt/update.sh` が Packages インデックスから `source.nix` を更新。同梱プラグインの `~/.codex/.tmp/` へのコピーが Nix ストアの 555 モードを写して EACCES になるため app.asar を展開 → chmod 挿入 → 再パックしている（詳細は `default.nix` のコメント）。Codex ランタイム (`~/.codex/`) はアプリが自己更新する管理外状態 |
| キーリマップ (xremap) | Nix (`xremap` gnome variant) + systemd ユーザーサービス (`modules/xremap/`) | Chrome にキーバインド変更機能が無いため evdev/uinput レベルで置換。アプリ判定に GNOME Shell 拡張が要る。`input` グループ / udev ルールのみ root 作業として残る |
| Bluetooth オーディオ | home-manager (xdg.configFile) + pavucontrol | WirePlumber の HFP 自動切替を無効化し、A2DP (ステレオ) / HFP (マイク) は pavucontrol で手動切替。プロファイルの記憶 (`~/.local/state/wireplumber/`) はランタイム状態のため管理外 |
| クリップボード画像 (WSL) | `wl-paste` shim (`modules/wsl`) | WSLg が `image/bmp` しか出さず Claude Code が扱えないため、`image/png` を追加広告して ImageMagick で変換（`docs/clipboard-image-paste.md`） |
| PHP (mise) | mise php プラグイン (ソースビルド) + ビルド依存はホスト別 | wsl-gentoo は portage、k-2 は `nix develop .#php-build` (`shells/php-build.nix`)。gettext / readline / gmp の `configure` は `/usr` 直下しか探さないので devShell が `PHP_EXTRA_CONFIGURE_OPTIONS` でストアパスを渡す。RPATH に `/nix/store` が焼き込まれるため `--profile` で GC root を作る (README「mise PHP のセットアップ」) |
| Azure CLI | mise `pipx:azure-cli` (uv tool で PyPI の wheel を venv に入れる、`home.nix` の `programs.mise`)。zsh 補完は `modules/zsh` がビルド時に生成 | nixpkgs の azure-cli は Python の依存木が大きく、無関係なパッケージの broken で評価ごと止まる (NixOS/nixpkgs#575989、issue #231)。PyPI の wheel は Microsoft 公式で、NixOS では uv の Python を nix-ld で動かす。awscli2 は壊れていないので Nix のまま |
| Playwright ブラウザ (k-2) | 公式配布バイナリ (`playwright install`) + `programs.nix-ld.libraries` (`hosts/k-2/configuration.nix`) | nixpkgs の `playwright-driver` (1.61) はプロジェクト側 (`@playwright/test` 1.63) とブラウザリビジョンが合わず、nixpkgs 側で追従すると更新のたびに hash 更新が要る。Chromium の実行時ライブラリだけ nix-ld に載せて公式バイナリを使う (`playwright install-deps` 相当)。nixpkgs に依存ライブラリのみのパッケージは無い (2026-09 時点) |
| ホスト別 ssh 設定 | private リポジトリ `nanasess/ssh_conf.d` を `~/.ssh/conf.d` に clone、`programs.ssh.includes` で読む。未 clone は activation (`sshConfDCheck`) が警告。WSL ホストは Windows の ssh.exe 用に `%USERPROFILE%\.ssh\` へミラー (`modules/wsl` の `windowsSshConfig`) | 顧客名・接続先の一覧なので public のこのリポジトリには submodule / flake input でも入れない。1Password に登録できない古い鍵 (RSA の exponent 35 等) は Document に置き `ssh-legacy` (`modules/zsh`) で一時 agent に読み込む。WSL からは Windows の ssh.exe を使わない (理由は `docs/ssh-conf-d.md`) |
| バックアップ (k-2) | restic (`services.restic.backups.nas`) → Synology DS720+ の SFTP、秘密情報は `/root/secrets/` (正本は 1Password) | flake で再現できない状態 (`~`、VPN 定義、BT ペアリング) だけを毎時送る。NAS 側は DSM 組み込み SFTP のみで追加ソフト不要、Btrfs の変更不可スナップショットで履歴を保護。ディスクイメージは取らず、復旧は再インストール + `restic-nas restore` (`docs/restic-nas.md`) |

**プラットフォーム非依存化の判断基準**: portage / apt など特定ホストのパッケージマネージャに依存する構成は、入手経路が「バイナリ + 付随ツール」だけの問題であれば **Nix パッケージ化 (必要なら `pkgs/` に自作 derivation) して全ホスト共通化する**ことを優先する。辞書・データ類はシステムパス (`/usr/lib` 等、要 sudo) ではなくユーザーパス (`xdg.dataHome` 配下) に置き、セットアップを sudo レスにする。yaskkserv2 はこの方針で wsl-gentoo (旧 portage) と ubuntu を統一した先例 (PR #110)。

### Emacs パッケージ (elpaca) の更新手順

`modules/emacs/elpaca.lock` は全パッケージを `:ref` でピン留めしており (`elpaca-menu-lock-file`)、
lock から入れた `~/.emacs.d/elpaca/sources/*` は detached HEAD になっている。elpaca の merge は
引数なしの `git merge --ff-only` なので、**そのまま `M-x elpaca-pull-all` / `elpaca-merge-all` を
実行すると `fatal: No current branch.` (exit 128) で「Subprocess error」になる**。

- **全パッケージを最新化する**: README「Emacs パッケージの更新 (elpaca)」の標準手順
  (`M-x elpaca-checkout-branches` → `M-x elpaca-pull-all` → `M-x elpaca-write-lock-file`)。
  `elpaca-checkout-branches` (init.el) はレシピの `:branch`、無ければ `origin/HEAD` のブランチへ戻し、
  失敗したパッケージを `*Warnings*` に出す。`Missing dependency <pkg>` は上流で依存が増えたもので、
  pull の経路では依存が自動で入らない (対処は README)。lock は `elpaca-lock-file` が
  `~/.config/home-manager/modules/emacs/elpaca.lock` を指すので main の作業ツリーに書かれる。
  worktree で PR にするときは `emacsclient --eval '(elpaca-write-lock-file "<worktree>/modules/emacs/elpaca.lock")'`
  で書き出し先を指定する。
- **特定パッケージだけ上げる**: 以下の手順で lock の `:ref` を書き換える。

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
3. **ビルド**: `nix build .#chatgpt` (400MB 弱の deb を取得するので数分かかる)。失敗したら原因は次のいずれか:
   - `substituteInPlace ... --replace-fail` で止まった → 上流が `fs.cp` でプラグインをコピーする箇所を変えた。`asar extract` で新しい `main-*.js` を取り出し、`default.\w*\.cp(` を `grep` して置換パターンを合わせる (`default.nix` の該当コメント参照)。パッチ箇所は 2 つ (同梱プラグイン → `~/.codex/.tmp/` と codex-app-tools → `~/.config/Codex/executor-plugins/`)。fs と `promisify(execFile)` のミニファイ名 (`b` / `nne` 等) は版ごとに変わるので両方追従させる。パッチの目的は「コピー直後に宛先を `chmod -R u+w` する」ことなので、それが満たせれば形は変えてよい。
   - `auto-patchelf could not satisfy dependency` → 新しい共有ライブラリ依存が増えた。NEEDED を見て `buildInputs` に足す。Qt や musl のような環境依存でしか使わないものは `autoPatchelfIgnoreMissingDeps` に追加する。
   - ビルドは通るが起動ログに `EACCES` が出る → 上流が新たに Nix ストアからの `fs.cp` を追加した。スタックトレースの関数を `main-*.js` で探し、コピー直後に同じ chmod を挟む。テスト起動で読み取り専用のコピーが残ると次回の `cp` が `unlink` で失敗するので、`chmod -R u+w` で戻してから再確認する。
4. **起動確認** (k-2 上で作業しているとき): 先に `pgrep -x ChatGPT` で起動中でないことを確かめる (起動中だと新プロセスは既存インスタンスへ委譲して即終了し、後の `pkill` がユーザーのアプリを閉じてしまう。起動中ならユーザーに閉じてもらう)。`./result/bin/chatgpt > /tmp/chatgpt.log 2>&1 &` で 20 秒ほど走らせ、ログに `window ready-to-show` と `plugin_marketplace_folder_write_succeeded` があり `EACCES` が無いことを確認して `pkill -x ChatGPT` で止める (`pkill -f` はシェル自身を巻き込むので使わない)。401 / `Unauthorized` は未ログインなだけで正常。k-2 以外では省略し、未検証と報告する。
5. **flake 検証**: `nix flake check` と `nix eval --raw '.#nixosConfigurations.k-2.config.system.build.toplevel.drvPath'`。
6. **コミット / PR**: `chore(chatgpt): <旧> → <新> に更新` でコミットし、PR 本文に手順 3〜5 の結果を書く。`result` シンボリックリンクはコミットしない。CI はポーリングせず、PR URL を報告して終える。
7. **適用はユーザーが行う**: `sudo nixos-rebuild switch --flake .#k-2`。ロールバックは `source.nix` の revert または `nixos-rebuild switch --rollback`。

補足: アプリは `~/.codex/` 配下の Codex ランタイムを自分でダウンロードして自己更新するので、
Nix 側の更新はあくまで Electron 本体 (deb) の追従。in-app updater は apt 前提のため NixOS では
効かない。ライブラリ依存の全体像 (Electron が dlopen するもの含む) は
`pkgs/chatgpt/default.nix` のコメントにまとめてある。

### k-2 (T2) の nixpkgs / nixos-hardware の更新手順

k-2 の linux-t2 は T2 パッチを当てたカーネルで、nixpkgs を上げるときの最大のリスクになる。
upstream の nixos-hardware は nixpkgs の `linux_6_18` にパッチを当てるため、nixpkgs が先に進むと
パッチが当たらなくなる (nixos-hardware#2027。PR #202 で落ち、PR #205 で nixpkgs を固定した)。
現在は、カーネルのバージョンもパッチと一緒に固定する nixos-hardware#1934 の fork
(`github:soopyc/nixos-hardware/<rev>`) にコミットで固定している (PR #229、issue #227)。
**#1934 がマージされたら `github:NixOS/nixos-hardware` に戻す。** fork の rev は flake.nix の URL に
書いているので、`nix flake update` では動かない (上げるときは URL を書き換える)。

1. **入力を更新**: worktree で `nix flake update nixpkgs` (k-2 が目的なら他の input は後回しでよい)。
2. **カーネルのキャッシュを確認** (自前ビルドは 4 コアで数時間):
   ```bash
   K=$(nix eval --raw '.#nixosConfigurations.k-2.config.boot.kernelPackages.kernel.outPath')
   curl -s -o /dev/null -w '%{http_code}\n' "https://cache.soopy.moe/$(basename $K | cut -d- -f1).narinfo"
   nix build --no-link '.#nixosConfigurations.k-2.config.boot.kernelPackages.kernel.configfile'
   ```
   fork でもカーネルの drv は nixpkgs のツールチェーンに依存するので、**nixpkgs の rev によっては
   404 になる** (PR #229 では `3ec6363` は 200、1 つ前のチャネル tip の `fe13242` は 404 だった)。
   404 なら別のチャネル tip を試すか、数日待つ。`configfile` が `Hunk #N FAILED` で落ちたら、
   原因になった input (fork の rev か nixpkgs) を直前に成功した rev に戻す。
3. **nixpkgs 側のパッケージが壊れていたら、そのパッケージだけ古い rev から取る**。nixpkgs 全体を
   古い rev に揃えるとカーネルがキャッシュから外れるため。PR #229 の azure-cli
   (fabric が invoke 3 非対応で broken、NixOS/nixpkgs#575989) が先例で、`nixpkgs-azure-cli` input と
   overlay で古い rev から取っていた (その後 issue #231 で mise の `pipx:azure-cli` に移して Nix から外した)。
   上流の修正が nixos-unstable に入ったら外す。最後に壊れていなかったチャネル tip は次で探す:
   ```bash
   # nixos-unstable が進んだ履歴 (各行がチャネル tip = Hydra でビルド済み)
   gh api 'repos/NixOS/nixpkgs/activity?ref=refs/heads/nixos-unstable&per_page=20' \
     --jq '.[]|"\(.timestamp[0:16]) \(.after[0:12])"'
   # 壊した commit を含むか (diverged = 含まない / ahead = 含む)
   gh api "repos/NixOS/nixpkgs/compare/<壊した commit>...<tip>" --jq .status
   ```
   `nix flake lock --override-input nixpkgs github:nixos/nixpkgs/<rev>` なら、`original` を
   `nixos-unstable` のまま rev だけ固定できる。
4. **toplevel をビルド**: k-2 上なら `nix build '.#nixosConfigurations.k-2.config.system.build.toplevel'`。
   ログに `copying path '...-linux-t2-<ver>' from 'https://cache.soopy.moe'` が出ていればカーネルは
   キャッシュから取れている。自作 derivation (`pkgs/chatgpt` など) の autoPatchelf は、nixpkgs の更新で
   他の buildInputs 経由の間接依存が消えると落ちる (PR #229 では `tpm2-tss` / `openssl`)。旧ビルドの
   rpath (`patchelf --print-rpath`) と比べ、不足分を buildInputs に明示する。
5. **他ホストの検証**: `nix flake check`、wsl-gentoo / wsl-nixos の activationPackage。
   ubuntu の activationPackage は Ghostty とその依存 (zig 等) がソースからのビルドになり時間がかかる
   ので、k-2 が目的ならユーザーに確認したうえでスキップして CI に任せてよい。
6. **closure の差分**: `nix store diff-closures /run/current-system <toplevel>` で linux-t2 /
   t2bce-* / pipewire / wireplumber / xremap の変化を PR 本文に書く。
7. **実機確認はユーザーが行う**: カーネルが変わるので `switch` ではなく
   `sudo nixos-rebuild boot --flake .#k-2` + 再起動 (sudo は Claude からは通らない)。確認項目:
   `uname -r`、内蔵キーボード / トラックパッド、内蔵スピーカー / マイク / Bluetooth オーディオ、
   蓋閉じ suspend からの復帰 (キーボード / トラックパッド / Touch Bar)、xremap (Chrome の
   Ctrl+H / Ctrl+L)。ロールバックは GRUB で前の世代を選ぶか `nixos-rebuild switch --rollback`。

fork (#1934) では内蔵キーボード / トラックパッドのモジュール名が `apple-bce` → `t2bce-vhci` に、
オーディオが t2-better-audio → `t2bce-alsa-ucm` に変わった。`boot.initrd.kernelModules` に
`apple_bce` を直書きしている設定は書き換えが要る (k-2 はモジュール任せなので影響なし)。
6.18.55 で上記の確認項目がすべて問題ないことを確認済み (2026-10-28)。

### ssh 接続のトラブル

「ssh で繋がらない」「ssh のエラーが出る」と相談されたら、`docs/ssh-conf-d.md` の
「ssh で問題が起きたときの切り分け」に従う。ホスト別設定はこのリポジトリではなく
`~/.ssh/conf.d` (private の `nanasess/ssh_conf.d` の clone) にあるので、修正と PR は
ssh_conf.d 側に出す。このリポジトリの Issue / PR / コミットにはホスト名・IP・顧客名を書かない。

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
- **check** — `nix flake check`
- **emacs** — `emacs --batch` による init.el の読み込みテスト（elpaca キャッシュ付き）
- **build** — 各ホストの `activationPackage` ビルド（matrix: ubuntu-latest）
- **nixos** — `nixosConfigurations` (k-2 / wsl-nixos) の toplevel 評価 + home-manager 部分のビルド（k-2 のカーネルとファームウェアは CI で作らない）

## 詳細ドキュメント (`docs/`)

環境ごとの調査結果・落とし穴は `docs/` に分離してある。該当領域を触るときに読むこと。

| ドキュメント | 内容 | 主な対象 |
|---|---|---|
| [docs/eaw-width.md](docs/eaw-width.md) | East Asian Ambiguous 文字幅の方針 (ターミナル系は幅 1、Emacs GUI のみ幅 2)、noctty が幅 1 固定である理由 | `modules/emacs/site-lisp/eaw-console.el` |
| [docs/bluetooth-audio.md](docs/bluetooth-audio.md) | 接続不安定 (マルチポイント / discovery 枯渇 / WiFi 2.4GHz) の切り分け、A2DP と HFP の排他、自動切替の無効化 | `modules/bluetooth-audio/` (ubuntu) |
| [docs/nix-desktop-integration.md](docs/nix-desktop-integration.md) | nixpkgs の GUI アプリがランチャー/アイコンに出ない `XDG_DATA_DIRS` 問題と対処 | `hosts/ubuntu.nix`, 各 GUI モジュール |
| [docs/ibus-skk.md](docs/ibus-skk.md) | apt 版 1.4.3 のバグ、`IBUS_COMPONENT_PATH` によるエンジン登録、反映手順 | `pkgs/ibus-skk.nix`, `modules/ibus-skk/` (ubuntu) |
| [docs/xremap.md](docs/xremap.md) | Chrome のタブ移動リマップ、XKB レイヤとの関係、GNOME Wayland でのアプリ判定、root 作業 | `modules/xremap/` (ubuntu) |
| [docs/clipboard-image-paste.md](docs/clipboard-image-paste.md) | Claude Code への画像貼り付け。`Ctrl+V` が正解な理由、WSLg の BMP 問題と `wl-paste` shim、切り分け手順 | `modules/wsl` (WSL ホスト共通) |
| [docs/nixos-t2.md](docs/nixos-t2.md) | T2 Mac での NixOS (nixpkgs の更新手順は上記「k-2 (T2) の nixpkgs / nixos-hardware の更新手順」)。nixos-hardware apple-t2 の仕組み、ファームウェア抽出 (KVM 必須)、カーネルのバイナリキャッシュ、ESP 300MB と GRUB、インストール手順 | `hosts/k-2/` (k-2) |
| [docs/mew.md](docs/mew.md) | Mew の Gmail XOAUTH2 + 1Password 化。master password 方式が必要な理由、1Password アイテムと Google OAuth クライアントの作り方、初回認可、旧設定からの差分、MS365 を足す場合 | `pkgs/mew.nix`, `modules/emacs/init.el` (Email (Mew)) |
| [docs/restic-nas.md](docs/restic-nas.md) | restic → Synology NAS。DSM の SFTP 仮想ルート (`/restic/...`)、backup 専用ユーザーと `authorized_keys` の置き方、`/root/secrets/` の運用、復旧手順 | `hosts/k-2/configuration.nix` (バックアップ) |
| [docs/ssh-conf-d.md](docs/ssh-conf-d.md) | ホスト別 ssh 設定 (private の ssh_conf.d) の構成、**ssh 接続トラブルの切り分け手順** (`ssh -v` の `Applying options` で conf.d のファイルと行を特定 → 症状別の原因表 → ssh_conf.d に PR)、棚卸し手順 | `home.nix` (`programs.ssh`)、`~/.ssh/conf.d` |
| [docs/1password-wsl.md](docs/1password-wsl.md) | WSL での Windows 版 / Linux 版 1Password の併用。用途別の担当表 (ssh = Linux 版 agent、コミット署名 = Windows 版 `op-ssh-sign.exe`、`op` = シム → `op.exe`、`op run` = Linux 版、Environments = Linux 版)、アプリ側の手作業設定、`op` シム、トラブルシュート、Zenn 記事との差分 | `modules/wsl`、`home.nix`、`hosts/wsl-*/` |
