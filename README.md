# home-manager

Nix Flake ベースの [Home Manager](https://github.com/nix-community/home-manager) 設定リポジトリ。
WSL2 Gentoo Linux, Ubuntu, NixOS の環境を1リポジトリで宣言的に管理する。

## 対応ホスト

| ホスト名 | OS | 適用方法 | 設定ファイル |
|---------|-----|---------|------------|
| `nanasess@wsl-gentoo` | WSL2 Gentoo Linux | `home-manager switch` (standalone) | `hosts/wsl-gentoo.nix` |
| `nanasess@ubuntu` | Ubuntu 24.04 (Wayland) | `home-manager switch` (standalone) | `hosts/ubuntu.nix` |
| `k-2` | NixOS (Intel MacBook Pro 2020, T2) | `nixos-rebuild switch` (home-manager は NixOS モジュール) | `hosts/k-2/` |

k-2 は Ubuntu からの移行先 (issue #151)。T2 固有の事情 (linux-t2 カーネル、ファームウェア、
ESP と GRUB) とインストール手順は [docs/nixos-t2.md](docs/nixos-t2.md) にまとめてある。

## セットアップ

### 前提条件

- wsl-gentoo / ubuntu: [Nix](https://nixos.org/download/) (Flakes 有効) と
  [Home Manager](https://github.com/nix-community/home-manager) がインストール済みであること
- k-2: NixOS 本体。home-manager は `flake.nix` の `nixosConfigurations."k-2"` に組み込まれているので
  standalone の `home-manager` コマンドは使わない (入っていない)

### 初回適用

```bash
# リポジトリをクローン
git clone https://github.com/nanasess/home-manager.git ~/.config/home-manager
cd ~/.config/home-manager

# 設定を適用（ホスト名は環境に合わせて変更）
home-manager switch --flake '.#nanasess@wsl-gentoo'
home-manager switch --flake '.#nanasess@ubuntu'
sudo nixos-rebuild switch --flake '.#k-2'    # NixOS (home-manager も同時に適用)
```

k-2 の初回インストール (パーティション作成、`nixos-install`、NVRAM の整理) は
[docs/nixos-t2.md](docs/nixos-t2.md) のランブックに従う。

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

### SKK 辞書サーバ (yaskkserv2) のセットアップ（全ホスト共通）

Emacs (nskk) の辞書本体を skkserv (yaskkserv2) に逃がし、nskk が全辞書を起動時にトライ索引へ全件展開することで full GC が 20-50 秒かかる問題を回避します。サーバは `modules/yaskkserv2.nix` が **systemd ユーザーサービス**として管理します（`/etc` も sudo も OpenRC も不要）。

バイナリ (`yaskkserv2` / `yaskkserv2_make_dictionary`) は nixpkgs / apt に無いため `pkgs/yaskkserv2.nix` で **Nix ビルド**し、全ホストで同一バイナリを共有します。配信辞書はユーザーパス `~/.local/share/yaskkserv2/all` に置くため、セットアップは **すべて sudo 不要**です。

```bash
# 1. home-manager でバイナリ導入 + 設定生成 + ユーザーサービス起動
#    （<host> は wsl-gentoo または ubuntu。k-2 は sudo nixos-rebuild switch --flake '.#k-2'）
home-manager switch --flake '.#nanasess@<host>'

# 2. 配信辞書を SKK-JISYO.all.utf8 からビルド（初回 + 辞書更新時のみ再実行）
#    yaskkserv2_make_dictionary は上記で ~/.nix-profile/bin
#    (k-2 は /etc/profiles/per-user/nanasess/bin) に入る
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

設定 (`modules/yaskkserv2.nix`) を変更したら `home-manager switch` / `nixos-rebuild switch` で自動反映されます（手動再起動が要る場合は `systemctl --user restart yaskkserv2`）。`listen-address = 127.0.0.1`（LAN へ露出しない）ですが、WSL2 では localhostForwarding 経由で Windows からも `localhost:1178` で接続できます。

辞書の元ファイルは OneDrive 上にあるため、辞書が無い間は skkserv が即終了し ibus-skk / nskk とも漢字変換ができない。k-2 初回セットアップでの OneDrive 認可と辞書ビルドの順序は [docs/nixos-t2.md](docs/nixos-t2.md)「起動後」参照。

### システムパッケージの確認（wsl-gentoo / ubuntu）

portage / apt で入れるべきパッケージが揃っているか、Nix 側と衝突するパッケージ (ubuntu の `ibus-skk` 等) が入っていないかを確認できます。
NixOS (k-2) はシステムパッケージも `configuration.nix` で宣言するので不要。

```bash
~/.local/bin/check-system-packages
```

### mise PHP のセットアップ

mise の php プラグイン (`jdx/vfox-php`) は PHP をソースからビルドする。ビルド依存は
ホストごとに入手経路が異なる:

| ホスト | ビルド依存の入手 |
|---|---|
| wsl-gentoo | portage (`hosts/wsl-gentoo.nix` の `mise PHP ビルド依存`)。`mise install php@8.5` をそのまま実行 |
| k-2 (NixOS) | `nix develop .#php-build` (`shells/php-build.nix`)。FHS 前提のツールチェーンが無いので devShell 経由で実行する |

```bash
# PHP インストール (k-2)。--profile で GC root を作り、リンク先ライブラリが
# nix-collect-garbage で消えないようにする (RPATH に /nix/store が焼き込まれる)
nix develop '.#php-build' --profile ~/.local/state/nix/profiles/php-build \
  -c mise install php@8.5

# PHP インストール (wsl-gentoo)
mise install php@8.5

# カスタム設定（memory_limit 等）
echo "memory_limit=1G" > ~/.local/share/mise/installs/php/8.5.9/conf.d/custom.ini

# PECL 拡張の追加 (k-2 では devShell 内で実行する)
pecl install redis
echo "extension=redis.so" > ~/.local/share/mise/installs/php/8.5.9/conf.d/redis.ini

# 確認
php -m | grep redis
php -r 'echo ini_get("memory_limit")."\n";'
```

k-2 の注意点:

- `flake.lock` 更新でライブラリが変わっても、プロファイルの古い世代が残っている間は
  既存の PHP は動く。`nix profile wipe-history --profile ~/.local/state/nix/profiles/php-build`
  や `nix-collect-garbage -d` の後に `error while loading shared libraries` が出たら
  `mise install php@8.5 --force` で再ビルドする。
- gettext / readline / gmp は `configure` が `/usr` 直下しか探さないため、devShell が
  `PHP_EXTRA_CONFIGURE_OPTIONS` でストアパスを渡している (詳細は `shells/php-build.nix`)。

## ディレクトリ構成

```text
flake.nix              -- エントリポイント（inputs、homeConfigurations、nixosConfigurations、packages、devShells）
home.nix               -- 全ホスト共通設定（パッケージ、git、direnv、環境変数）
hosts/
  wsl-gentoo.nix       -- WSL Gentoo 固有設定（gentooPackages と check-system-packages、op の setgid バイナリのパス）
  ubuntu.nix           -- Ubuntu 固有設定（Ghostty (nixGL)、apt 差分チェック、GNOME 拡張）
  k-2/                 -- NixOS (Intel MacBook Pro 2020, T2)。Ubuntu からの移行先 (docs/nixos-t2.md)
    configuration.nix  -- システム設定（apple-t2、GRUB、GNOME、NetworkManager、usbmuxd、1Password、ibus、nix.settings）
    hardware-configuration.nix -- ディスク (LABEL 参照) / カーネルモジュール
    home.nix           -- ユーザー環境（hosts/ubuntu.nix の NixOS 版）
    scripts/backup-before-install.sh -- インストール前の退避
modules/
  zsh/                 -- Zsh（プラグイン、エイリアス、補完、1Password 連携、Powerlevel10k）
  emacs/               -- Emacs（elpaca でパッケージ管理。init.el / early-init.el / elpaca.lock / init.d / site-lisp）
  ghostty/             -- Ghostty 共有設定（Linux native / noctty / Windows port を同一 attrset から生成）
  claude/              -- Claude Code のユーザー設定（CLAUDE.md、PreToolUse hook）
  wakatime/            -- WakaTime CLI（API キーは 1Password から実行時に解決）
  wsl/                 -- WSL ホスト共通（Windows 側への noctty / Ghostty 設定・UDEV Gothic・Mackerel のコピー、op / wl-paste シム、gpg-agent、WSLg）
  mackerel/            -- LibreHardwareMonitor → Mackerel カスタムメトリック（modules/wsl が Windows 側へ配置）
  bluetooth-audio/     -- WirePlumber の HFP 自動切替無効化 + pavucontrol（GNOME ホスト共通）
  ibus-skk/            -- ibus-skk の辞書設定 (dconf) と ubuntu 用エンジン登録
  walker/              -- Walker / Elephant ランチャー（GNOME ホスト共通）
  xremap/              -- キーリマッパー（Chrome のタブ移動を Ctrl+H / Ctrl+L に。GNOME ホスト共通）
  t2-suspend/          -- T2 Mac サスペンド設定の sudo 配置ヘルパー（ubuntu。k-2 は configuration.nix）
  portage.nix          -- Portage 設定（WSL Gentoo 用、~/.config/portage/ に書き出し）
  onedrive.nix         -- OneDrive クライアント（systemd ユーザーサービス）
  yaskkserv2.nix       -- SKK 辞書サーバ（systemd ユーザーサービス。全ホスト共通）
pkgs/
  yaskkserv2.nix       -- yaskkserv2 の自作 derivation（nixpkgs 未収録）
  ibus-skk.nix         -- ibus-skk 1.4.4 の自作 derivation（nixpkgs 未収録 + apt は 1.4.3 で停滞）
  mew.nix              -- Mew (Emacs メーラ) の外部コマンド（elisp は elpaca。docs/mew.md）
shells/
  php-build.nix        -- mise php プラグイン (ソースビルド) 用 devShell（NixOS 用）
docs/                  -- 領域別の詳細ドキュメント（EAW 文字幅、Bluetooth、ibus-skk、xremap、NixOS T2 等）
.claude/skills/
  flake-update-pr/     -- nix flake update を PR 化する手順（更新パッケージ一覧の生成を含む）
.github/workflows/
  check.yml            -- CI（flake check、各ホストのビルド、NixOS 評価、Emacs batch test）
```

## パッケージ更新手順

### Nix パッケージの更新 (flake.lock)

`flake.lock` は全ホスト共通。更新は 1 度で済み、各ホストで適用する。
PR 化するときは `flake-update-pr` Skill (`.claude/skills/flake-update-pr/`) を使う
(closure 差分から更新パッケージ一覧を生成して PR 本文に載せる)。

```bash
# 1. flake.lock を更新（nixpkgs, home-manager, nixgl, nixos-hardware の全 inputs を最新化）
nix flake update

# 2. ビルドして問題がないか確認（ドライラン）
home-manager switch --flake '.#nanasess@wsl-gentoo' --dry-run
nixos-rebuild dry-build --flake '.#k-2'               # k-2 (sudo 不要)

# 3. 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
sudo nixos-rebuild switch --flake '.#k-2'             # k-2 (下記「NixOS (k-2) の更新」)

# 4. 変更をコミット
git add flake.lock
git commit -m "chore(deps): nix flake update"
```

特定の input のみ更新する場合:

```bash
nix flake update nixpkgs
nix flake update home-manager
nix flake update nixos-hardware   # k-2 の linux-t2 カーネル / ファームウェア
```

### NixOS (k-2) の更新

k-2 では **システムと home-manager を `nixos-rebuild` が一括で適用する**。standalone の
`home-manager switch` は使わない (コマンド自体入っていない)。手順は `flake.lock` の更新 →
ビルド確認 → `switch` → (カーネルが変わっていれば) 再起動。

```bash
cd ~/.config/home-manager

# 1. flake.lock を更新 (上記)。nixpkgs は nixos-unstable を追従している
nix flake update

# 2. 何がビルド / 取得されるかを確認 (実ビルドはしない)
#    「will be built」に linux-t2 が出たら止める (下記「カーネルのキャッシュ」)
nix build --dry-run '.#nixosConfigurations.k-2.config.system.build.toplevel'

# 3. 先にビルドして現行世代との差分を見る (任意。switch が何を変えるか把握できる)
nix build '.#nixosConfigurations.k-2.config.system.build.toplevel'
nix store diff-closures /run/current-system ./result

# 4. 適用 (システム + home-manager)。次回起動の既定世代にもなる
sudo nixos-rebuild switch --flake '.#k-2'

# 5. home-manager 側が失敗していないか確認
#    (システム側が成功すると見落としやすい。失敗するとその世代の dotfiles / autostart が入らない)
systemctl status home-manager-nanasess.service --no-pager

# 6. カーネルが変わっていれば再起動
#    list-generations の Kernel 列と uname -r が違う間は、稼働中カーネルは旧のまま
nixos-rebuild list-generations | head -3
uname -r
sudo reboot

# 7. コミット
git add flake.lock
git commit -m "chore(deps): nix flake update"
```

`switch` の代わりに `sudo nixos-rebuild boot --flake '.#k-2'` を使うと、世代を作って
GRUB の既定に据えるだけで稼働中システムは変えない。カーネル更新のように再起動前提の
変更や、稼働中に切り替えたくない場合はこちら。

#### カーネルのキャッシュ

linux-t2 は nixpkgs のキャッシュに無く、t2linux コミュニティの Hydra (`https://cache.soopy.moe`)
から取る (`hosts/k-2/configuration.nix` の `nix.settings.substituters` で宣言済み)。
Hydra が nixpkgs の更新に追随するまでは新しい `flake.lock` に対応するカーネルが無く、
その状態で `switch` すると **自前ビルド (4 コアで数時間)** になる。

自前ビルドにすら失敗することもある。nixos-hardware の apple-t2 は T2 パッチ集
(`apple/t2/pkgs/linux-t2/stable.json`) を t2linux/linux-t2-patches の特定 commit に固定して
いるので、nixpkgs 側の `linux_6_18` だけが進むとパッチが当たらなくなる
(`4001-asahi-trackpad.patch` が `hid-magicmouse.c` で `Hunk FAILED`、2026-09 の 6.18.46 → 6.18.51 で発生。
[nixos-hardware#2027](https://github.com/NixOS/nixos-hardware/issues/2027))。
`nix log` で `linux-config-*.drv` の patchPhase を見れば分かる。この場合は nixos-hardware 側が
パッチ集を同期するまで nixpkgs を据え置き、`nix flake update home-manager` のように他の input
だけ更新する (下記)。

```bash
# 目的のカーネルがキャッシュにあるか (200 なら有り)
K=$(nix eval --raw '.#nixosConfigurations.k-2.config.boot.kernelPackages.kernel.outPath')
curl -sI "https://cache.soopy.moe/${K:11:32}.narinfo" | head -1   # store hash 32 文字だけを使う
```

無い場合は数日待つか、`nixpkgs` / `nixos-hardware` を個別に前の rev のまま置いておく
(`nix flake update home-manager` のように input を絞って更新する)。
別ホストから k-2 の toplevel をビルドする場合の substituter 設定は
[docs/nixos-t2.md](docs/nixos-t2.md)「カーネルのバイナリキャッシュ」参照。

#### 世代の確認とロールバック

`boot.loader.grub.configurationLimit = 20` で直近 20 世代が GRUB メニューに残る。

```bash
nixos-rebuild list-generations                                  # 世代一覧 (Current 列が稼働中)
nix profile diff-closures --profile /nix/var/nix/profiles/system   # 世代ごとのパッケージ差分

# 1 つ前の世代に戻す (稼働中のシステムを切り替え、GRUB の既定も戻す)
sudo nixos-rebuild switch --rollback

# 起動しない場合は GRUB メニューの旧世代エントリ (サブメニュー) から選んで起動する
```

#### 古い世代の削除 (GC)

`nix.gc` (`configuration.nix`) が **毎週、30 日より古い世代を自動削除**する。
手動で即時に空ける場合:

```bash
sudo nix-collect-garbage --delete-older-than 30d   # 30 日より古い世代を消す
sudo nix-collect-garbage -d                        # 現行以外の全世代を消す (ロールバック不可になる)
sudo nixos-rebuild boot --flake '.#k-2'            # GRUB メニューから消えた世代を落とす
```

自分のユーザーで実行した `nix-collect-garbage -d` は `~/.local/state/nix/profiles/php-build`
(mise PHP の GC root) の旧世代も消す (sudo 経由は root のプロファイルを見るので対象外)。
PHP が `error while loading shared libraries` で動かなくなったら「mise PHP のセットアップ」の
再ビルドを行う。

#### ブートローダ設定を変えたとき

`boot.loader.grub.*` (`efiInstallAsRemovable` 等) を変えただけでは `switch` は
`grub-install` を再実行しない (`/boot/grub/state` との差分が無いと判定される)。
**`sudo nixos-rebuild switch --flake '.#k-2' --install-bootloader`** で強制する。
NVRAM (`efibootmgr`) は NixOS が管理しないので、エントリの整理は手作業
([docs/nixos-t2.md](docs/nixos-t2.md)「NVRAM の整理」)。

`system.stateVersion` は最初にインストールしたリリース (`26.05`) のまま変えない。
リリース追従は `flake.lock` の nixpkgs で行う。

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

# 5. home-manager に反映 (k-2 は sudo nixos-rebuild switch --flake '.#k-2')
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
home-manager switch --flake '.#nanasess@wsl-gentoo'    # k-2 は sudo nixos-rebuild switch --flake '.#k-2'

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
home-manager switch --flake '.#nanasess@wsl-gentoo'    # k-2 は sudo nixos-rebuild switch --flake '.#k-2'
git add flake.lock modules/emacs/elpaca.lock
git commit -m "chore: nix flake update + elpaca パッケージ更新"
```

## 設定変更の反映

Nix の設定ファイル (`*.nix`) や dotfiles を編集した後:

```bash
# ビルドの確認
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'
nixos-rebuild build --flake '.#k-2'                                     # k-2 実機のみ (sudo 不要、./result に toplevel)
# k-2 以外のホストから k-2 の設定を確認するときは評価 + home-manager 部分に留める
# (toplevel を丸ごとビルドすると linux-t2 カーネルと Apple 復旧イメージを抱える。「開発コマンド」参照)
nix eval --raw '.#nixosConfigurations.k-2.config.system.build.toplevel.drvPath'
nix build '.#nixosConfigurations.k-2.config.home-manager.users.nanasess.home.activationPackage'

# 設定を適用
home-manager switch --flake '.#nanasess@wsl-gentoo'
sudo nixos-rebuild switch --flake '.#k-2'                              # k-2
```

## 開発コマンド

```bash
# flake の検証（自作 derivation (packages) のビルドも含む）
nix flake check

# Nix ファイルのフォーマット (nixpkgs-fmt)
nix fmt

# 各ホストのビルド
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'
nix build '.#homeConfigurations."nanasess@ubuntu".activationPackage'

# k-2: toplevel の評価と home-manager 部分のビルド
# (toplevel を丸ごとビルドすると linux-t2 カーネルと Apple 復旧イメージ (KVM 必須) を抱えるので、
#  k-2 以外のホストではここまでに留める)
nix eval --raw '.#nixosConfigurations.k-2.config.system.build.toplevel.drvPath'
nix build '.#nixosConfigurations.k-2.config.home-manager.users.nanasess.home.activationPackage'

# ビルドログの確認
nix log '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage'
```

## CI

GitHub Actions (`.github/workflows/check.yml`) が push / PR 時に以下を実行:

- **check** -- `nix flake check`
- **emacs** -- `emacs --batch` による init.el の読み込みテスト（elpaca キャッシュ付き）
- **build** -- 各ホストの `activationPackage` ビルド（ubuntu-latest。wsl-gentoo / ubuntu）
- **nixos** -- `nixosConfigurations.k-2` の toplevel 評価 + home-manager 部分のビルド（カーネルとファームウェアは CI で作らない）

## East Asian Ambiguous 文字幅 (EAW)

glibc 2.39+ で East Asian Ambiguous 文字 (△→○●■□▲ 等) の `wcwidth()` が 2→1 に変更された問題への方針。

メインターミナルの noctty (Ghostty の Windows port fork) は Ambiguous を**幅 1 に固定**しており設定で変更できないため、**ターミナル系はすべて幅 1 に統一**し、独立したレンダラである **Emacs GUI だけ幅 2** を維持している。

| レイヤー | 幅 | 設定 |
|---------|----|------|
| ターミナル (noctty / Ghostty 系) | 1 | uucode のテーブル (変更不可) |
| glibc (`wcwidth`) / zsh / tmux | 1 | 素の `ja_JP.utf8` を使う (`LOCPATH` の上書きは撤去) |
| Emacs GUI (WSLg) | 2 | `modules/emacs/site-lisp/eaw-console.el` + UDEV Gothic JPDOC |
| Emacs TUI (`emacs -nw` / `emacsclient -t`) | 1 | `use-default-char-width-table` で Emacs 既定のテーブルに戻す |

以前は locale-eaw EAW-CONSOLE で全レイヤーを幅 2 に揃えていたが、WezTerm から noctty へ移行した際に撤去した。詳細は [docs/eaw-width.md](docs/eaw-width.md) 参照。

## 詳細ドキュメント (`docs/`)

| ドキュメント | 内容 |
|---|---|
| [docs/nixos-t2.md](docs/nixos-t2.md) | k-2 (T2 Mac) の NixOS。カーネルのバイナリキャッシュ、ファームウェア、ESP と GRUB、インストール手順、NVRAM の整理 |
| [docs/eaw-width.md](docs/eaw-width.md) | East Asian Ambiguous 文字幅の方針 |
| [docs/bluetooth-audio.md](docs/bluetooth-audio.md) | Bluetooth の接続不安定の切り分け、A2DP / HFP の排他 |
| [docs/nix-desktop-integration.md](docs/nix-desktop-integration.md) | Ubuntu で nixpkgs の GUI アプリがランチャーに出ない問題 |
| [docs/ibus-skk.md](docs/ibus-skk.md) | apt 版 1.4.3 のバグ、Nix ビルド 1.4.4 の登録 |
| [docs/xremap.md](docs/xremap.md) | Chrome のタブ移動リマップ、GNOME Wayland でのアプリ判定 |
| [docs/clipboard-image-paste.md](docs/clipboard-image-paste.md) | WSL から Claude Code への画像貼り付け |
| [docs/mew.md](docs/mew.md) | Mew (Emacs メーラ) の Gmail XOAUTH2 + 1Password 化。セットアップと初回認可の手順 |

## TODO: 移行元リポジトリの統合

以下のリポジトリからの移行は未完了。段階的にこのリポジトリへ統合する。

| リポジトリ | 移行対象 | 状態 |
|-----------|---------|------|
| `~/.config/dotfiles` | Zsh 設定、エイリアス、1Password SSH 連携 | 移行済み |
| `~/git-repos/gentoo-ansible` | Portage 設定 (make.conf, package.use 等) | 移行済み (`modules/portage.nix`) |

## ホストの追加

### home-manager standalone ホスト

1. `hosts/<hostname>.nix` を作成
2. `flake.nix` の `homeConfigurations` にエントリを追加:
   ```nix
   "nanasess@<hostname>" = home-manager.lib.homeManagerConfiguration {
     pkgs = nixpkgs.legacyPackages.x86_64-linux;
     modules = [ ./home.nix ./hosts/<hostname>.nix ./modules/emacs ./modules/zsh ];
   };
   ```
   GNOME デスクトップを持つホストは `gnomeHomeModules` を使う (`hosts/ubuntu.nix` 参照)
3. `.github/workflows/check.yml` の build matrix にエントリを追加

### NixOS ホスト

1. `hosts/<hostname>/{configuration,hardware-configuration,home}.nix` を作成 (`hosts/k-2/` 参照)
2. `flake.nix` の `nixosConfigurations` に `nixpkgs.lib.nixosSystem` で追加し、
   `home-manager.nixosModules.home-manager` を `useUserPackages = true` で読み込む
   (`useGlobalPkgs` は `home.nix` の `nixpkgs.config` と衝突するので使わない)
3. home-manager モジュール内で Nix プロファイルのパスが要るときは `config.home.profileDirectory` を使う
   (`~/.nix-profile` を直書きすると NixOS の `/etc/profiles/per-user/<user>` で壊れる)
4. `.github/workflows/check.yml` の `nixos` ジョブに評価 / ビルドを追加
