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
| IBus SKK エンジン | Nix ビルド (`pkgs/ibus-skk.nix`) + `IBUS_COMPONENT_PATH` (`modules/ibus-skk/`) | apt / nixpkgs とも 1.4.4 未提供。apt 版 1.4.3 は変換確定が壊れる（下記参照）。IBus は `XDG_DATA_DIRS` を見ないため `systemd.user.sessionVariables` でエンジンを登録する |
| キーリマップ (xremap) | Nix (`xremap` gnome variant) + systemd ユーザーサービス (`modules/xremap/`) | Chrome にキーバインド変更機能が無いため evdev/uinput レベルで置換。アプリ判定に GNOME Shell 拡張が要る。`input` グループ / udev ルールのみ root 作業として残る |
| Bluetooth オーディオ | home-manager (xdg.configFile) + pavucontrol | WirePlumber の HFP 自動切替を無効化し、A2DP (ステレオ) / HFP (マイク) は pavucontrol で手動切替。プロファイルの記憶 (`~/.local/state/wireplumber/`) はランタイム状態のため管理外 |

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

## East Asian Ambiguous 文字幅 (locale-eaw)

glibc 2.39+ で `wcwidth()` が East Asian Ambiguous 文字 (△→○●■□▲ 等) に 1 を返すようになり、日本語環境で半角表示される問題に対処。[locale-eaw](https://github.com/hamano/locale-eaw) EAW-CONSOLE を使い、全レイヤーで文字幅を統一する。

### メカニズム

```text
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

## Bluetooth オーディオ (T2 Mac + Bose QC Earbuds)

設定: `modules/bluetooth-audio/`（`nanasess@ubuntu` のみ）。2026-08-12 の実機調査に基づく。

### 「接続がぷつぷつ切れる」はマルチポイントを最初に疑う

断続的な切断の真因は **イヤホン側のマルチポイント（iPhone との同時接続）** だった。他機器が A2DP スロットを掴んでいると `bluetoothd` が EBUSY を返し、15 秒周期の再接続ループに入る。

```text
a2dp-sink profile connect failed for <addr>: Device or resource busy
plugins/policy.c:reconnect_timeout() Reconnecting services failed: Device or resource busy (16)
```

iPhone とのペアリング解除で EBUSY はゼロになり、Link quality 255 / RSSI 0 で安定した。**設定では直せない運用上の問題**なので、再発時は WirePlumber や bluez をいじる前に他機器との同時接続を確認する。電波干渉や WiFi との coexistence を疑うのはその後。

### A2DP（ステレオ）と HFP（マイク）は排他

Bluetooth Classic の仕様上、両立できない。

| プロファイル | 出力 | マイク |
|---|---|---|
| `a2dp-sink` | ステレオ SBC | なし |
| `headset-head-unit-msbc` | モノラル 16kHz | あり |

A2DP は片方向でマイクの戻りチャンネルを持たず、マイクには SCO/eSCO を使う HFP が必要で、SCO は狭帯域モノラルしか通せない。回避技術（双方向 A2DP の `faststream_duplex` / `aptx_ll_duplex`、LE Audio の `bap-*`）は PipeWire 側が対応していても **Bose QC Earbuds が非対応**で、`pw-dump` の `EnumProfile` に現れないことを確認済み。これは OS 非依存で Windows でも同じ。

### 自動プロファイル切替を無効化している

WirePlumber の既定では、`/usr/share/wireplumber/policy.lua.d/10-default-policy.lua` の `media-role.applications` に載ったアプリが**実際にマイクを掴んだ**時点で A2DP → HFP へ自動切替する。`"Google Chrome input"` が含まれるため、Chrome のどこか 1 タブがマイク権限を使っているだけで、同じブラウザで再生している音楽まで mSBC 16kHz モノラルに巻き添えになる。

`51-disable-headset-autoswitch.lua` でこれを無効化し、**運用は pavucontrol での手動切替**（音楽 = `a2dp-sink` / 会議 = `headset-head-unit-msbc`）に統一した。

現在のプロファイルの確認（`select` を `Device` 型に絞らないと、同じ `device.api` を持つ
Node オブジェクト 2 件を拾って `null` 行が混ざる）:

```bash
pw-dump | jq -r '.[]
  | select(.type == "PipeWire:Interface:Device" and .info.props."device.api" == "bluez5")
  | "\(.info.props."device.description"): \(.info.params.Profile[0].description)"'
```

実機での出力:

```text
Bose QC Earbuds: High Fidelity Playback (A2DP Sink, codec SBC)   ← ステレオ
Bose QC Earbuds: Headset Head Unit (HSP/HFP, codec mSBC)         ← HFP（モノラル）
```

### プロファイルの記憶は home-manager 管理外

WirePlumber は選択したプロファイルを `~/.local/state/wireplumber/default-profile` に記憶し、再接続時に復元する。ランタイム状態なので宣言的管理の対象外。

- 記憶が HFP のままだと、自動切替を無効化しても再接続時に HFP で繋がる
- 当該行を削除すると優先度による選択（`a2dp-sink` が prio 18 で最大）にフォールバックする
- `wpctl set-profile` では**この記憶が更新されない**。pavucontrol など UI 経由の選択なら保存される

### GNOME にはプロファイル選択 UI がない

GNOME Settings (46) にプロファイルのドロップダウンはない。A2DP 中はイヤホンのマイクがソース一覧に出ないため、GUI から HFP に戻す手段が pavucontrol しかない。`modules/bluetooth-audio/` が pavucontrol を同梱しているのはこのため。

### WirePlumber 0.4 の Lua 設定形式

`51-disable-headset-autoswitch.lua` は WirePlumber 0.4 系の Lua 形式。**0.5 以降は `.conf` ベースの新形式になり本ファイルは無視される**ため、Ubuntu 側の wireplumber を上げるときは要追従。

## Nix GUI アプリのランチャー登録

GNOME セッションの `XDG_DATA_DIRS` は `/usr/local/share:/usr/share:/var/lib/snapd/desktop` だけで、**`~/.nix-profile/share` を含まない**。そのため nixpkgs が提供する `.desktop` はランチャー（GNOME アプリ一覧 / Walker）から見えない。ログインシェルの `XDG_DATA_DIRS` には入っており端末からは起動できてしまうため気づきにくい。

対処は `XDG_DATA_HOME`（`~/.local/share/applications/`）へ自前の `.desktop` を置くこと。`Exec` と `Icon` もセッション側では解決できないので、**`~/.nix-profile` 経由のフルパス**で指定する（store パス直書きは更新のたびに切れる）。

先例: Ghostty (`hosts/ubuntu.nix`)、pavucontrol (`modules/bluetooth-audio/default.nix`)。

根治策として `targets.genericLinux.enable = true` で `XDG_DATA_DIRS` ごと直す手もあるが、セッション全体に影響するため未採用。

### アイコンも同じ理由で解決できない

`.desktop` を `~/.local/share/applications/` に置いてもアプリ一覧に**アイコンだけ出ない**ことがある。`Icon=<name>` のテーマ検索も `XDG_DATA_DIRS` 依存で、GTK の検索パスは `~/.local/share/icons` → `~/.icons` → `$XDG_DATA_DIRS/*/icons` の順。nix profile がここに無いので `~/.nix-profile/share/icons/hicolor/...` は引かれない。

対処は `xdg.dataFile` でアイコンを `~/.local/share/icons/hicolor/<size>/apps/` にリンクすること。`hosts/ubuntu.nix` の `iconLinks` ヘルパーが Ghostty と Emacs 用にこれを行っている。

- `Icon=` に絶対パスを書いてもよい (pavucontrol はこの方式) が、解像度が固定になる。複数サイズを張るほうが HiDPI で有利
- 張るサイズは「パッケージが持っていて、かつ `/usr/share/icons/hicolor/index.theme` が定義しているもの」だけにする。未定義のディレクトリ (Ghostty の `1024x1024` や `*@2`) は張っても引かれない
- `index.theme` 自体は nix profile 側に無くてよい。テーマ定義は `/usr/share/icons/hicolor/index.theme` が提供し、ディレクトリ探索は全ベースディレクトリに適用される

**apt 版が同名アイコンを持つケースに注意**: Emacs は apt の emacs-common が `/usr/share/icons/hicolor` に `emacs.png` を置くため、未配置でも表示されてしまう。apt 版に依存した偶然なので、nixpkgs 側 (実際に起動する `emacs30-pgtk`) を明示的に優先させている。

検証は GTK に実際に引かせるのが確実 (gnome-shell と同じ `XDG_DATA_DIRS` を再現する):

```bash
env -u GI_TYPELIB_PATH XDG_DATA_DIRS="/usr/local/share/:/usr/share/:/var/lib/snapd/desktop" \
  /usr/bin/python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk;
i=Gtk.IconTheme.new().lookup_icon("com.mitchellh.ghostty",128,0); print(i.get_filename() if i else "NOT FOUND")'
```

`/usr/bin/python3` を使うこと (Nix の python3 では GI typelib を拾えず落ちる)。

**Walker は対象外**: nixpkgs の walker は `bin/walker` だけで `share/` を持たず、上流 (`abenz1267/walker`) にもアプリアイコンが存在しない (`v2.17.0` / 旧 Go 版 `v0.13.26` ともスクリーンショット画像のみ)。パス問題ではないので上記の方法では直せない。必要なら application id `dev.benz.walker` で `.desktop` を作り、システムテーマの汎用アイコン (`system-search` 等) を代用する。

**IBus エンジンには通用しない**: IBus のコンポーネント探索は `XDG_DATA_DIRS` も `XDG_DATA_HOME` も見ない。詳細は下記「ibus-skk」節。

## ibus-skk (SKK 入力メソッド)

設定: `pkgs/ibus-skk.nix` + `modules/ibus-skk/`（`nanasess@ubuntu` のみ）。apt 版 1.4.3 を Nix ビルドの 1.4.4 で置き換えている。

### apt 版 1.4.3 は ▼変換中に母音を打つと確定文字列が消える

`▽じょうき` → `SPC` → `▼上記` の状態から `C-j` を省いてローマ字入力を続けたときの挙動:

| 続けて打つ文字 | ddskk | ibus-skk 1.4.3 |
|---|---|---|
| `あ`（母音・1 打鍵） | 「上記あ」 | **「あ」のみ**（上記が消える） |
| `は`（子音+母音・2 打鍵） | 「上記は」 | 「上記は」（正常） |

原因は libskk ではなく ibus-skk 側。1 回の `process_key_event` 中に `commit_text` が 2 回呼ばれ、クライアントには最後の 1 回しか反映されない。

- `src/engine.vala:142` — `context.candidates.selected` シグナル内で `poll_output()` → `commit_text("上記")`
- `src/engine.vala:441` — `process_key_event` 末尾で `poll_output()` → `commit_text("あ")`

母音は 1 打鍵で仮名が確定するので同一イベント内で 2 回、子音+母音はイベントごとに 1 回ずつになるため、母音のときだけ壊れる。上流 1.4.4 の `Don't split sending CommitText when auto-start conversion [#71]` がシグナル側の `commit_text` を削除して修正済み。

libskk 側は 1.0.5 の時点で正しく動作する（`SelectStateHandler` が `candidates.select()` → `state.reset()` → `return false` し、`Context.process_key_event_internal` のループが `NoneStateHandler` で同じキーを再処理する）。切り分けには `gir1.2-skk-1.0` を展開して python から `Skk.Context` を直接叩くのが早い。

### IBus のコンポーネント探索は XDG を一切見ない

`ibus_registry_load()` の実装:

```c
envstr = g_getenv ("IBUS_COMPONENT_PATH");
if (envstr) {
    /* ← 設定されていれば「これだけ」を探索 */
} else {
    dirname = g_build_filename (IBUS_DATA_DIR, "component", NULL);  /* /usr/share/ibus/component のみ */
}
```

`g_get_user_data_dir()` は FIXME でコメントアウトされている。そのため Ghostty / pavucontrol で使っている「`XDG_DATA_HOME` に置く」回避策は効かない。

一方 `ibus-daemon` は GNOME では systemd ユーザーサービス (`org.freedesktop.IBus.session.GNOME.service`) として起動するため `~/.config/environment.d/` が届く。`systemd.user.sessionVariables.IBUS_COMPONENT_PATH` でエンジンを登録している。

**`IBUS_COMPONENT_PATH` を設定すると `/usr/share/ibus/component` が探索対象から外れる**（上記の `else` 分岐）。mozc など他エンジンが消えるので、必ず併記すること。

### apt 版は削除が必須

component 名 (`org.freedesktop.IBus.SKK`) とエンジン名 (`skk`) が apt 版と同一なので、両方が探索対象にあると二重登録になる。`sudo apt remove ibus-skk` すること。`check-system-packages` が競合として検出する。

エンジン名が同一なので、`dconf` の辞書設定 (`desktop/ibus/engine/skk`、`hosts/ubuntu.nix`) はそのまま引き継がれる。`encoding=` の受け渡し (`engine.vala` → `Skk.SkkServ`) も 1.4.4 + libskk 1.1.0 で変わっていない。

### layout は default に固定している

上流の `skk.xml.in.in` は `<layout>jp</layout>` で、SKK を有効にすると JIS 配列が強制される。Ubuntu 側では `/usr/share/ibus/component/skk.xml` を手で `default` に書き換えて運用していた（`dpkg --verify ibus-skk` が改変を検出。2026-03-06）ため、`pkgs/ibus-skk.nix` の `postPatch` でその状態を宣言的に再現している。

### 反映手順

`home-manager switch` だけでは既存セッションに `IBUS_COMPONENT_PATH` が届かない。

```bash
sudo apt remove ibus-skk
# 推奨: 再ログイン (systemd --user が environment.d を読み直す)
```

現在のセッションを維持したい場合は、`environment.d` を読み直してから IBus のユニットを再起動する。

```bash
systemctl --user daemon-reload
systemctl --user restart org.freedesktop.IBus.session.GNOME.service
```

`systemctl --user import-environment IBUS_COMPONENT_PATH` は**使えない**。`systemd.user.sessionVariables` が書き出すのは `environment.d/10-home-manager.conf` だけでシェルには値が入らず、`import-environment` は「クライアント側で設定済みの値」を取り込むコマンドだからである。

`ibus restart` も避ける。D-Bus 経由で daemon に自己 re-exec を要求するもので、re-exec は environ を引き継ぐため新しい値が反映されない (未検証だが、ユニットごと再起動すれば確実に manager 環境を継承する)。

## Chrome のタブ移動キーバインド (xremap)

設定: `modules/xremap/`（`nanasess@ubuntu` のみ）。Chrome にフォーカスがある時だけキーを置換する。

| キー | Chrome での動作 |
|---|---|
| `Ctrl+H` | 前のタブ (`Ctrl+PageUp`) |
| `Ctrl+L` | 次のタブ (`Ctrl+PageDown`) |
| `⌘+L` | アドレスバー (`Ctrl+L`) |

### Chrome 自体にキーバインド変更機能はない

`chrome://settings` にも `chrome://flags` にも項目がなく、タブ移動は `Ctrl+PageUp` / `Ctrl+PageDown` 固定。実現手段は 2 つあり、xremap を採った。

| 方式 | 難点 |
|---|---|
| Chrome 拡張 (Shortkeys 等) | コンテンツスクリプト方式のため `chrome://` 系ページ・新規タブページ・ページ読込前で効かない。`Ctrl+L`（アドレスバー）を奪えるかも不確実。宣言的管理にも乗せづらい |
| **xremap** | evdev/uinput レベルで置換するので Chrome に届く時点ですでに `Ctrl+PageUp`。全コンテキストで効く。ただし `input` グループ加入という root 作業とセキュリティ上の代償を伴う |

副作用として Chrome 内で `Ctrl+H`（履歴）と `Ctrl+L`（アドレスバー）は使えなくなる。アドレスバーは `⌘+L` に逃がしてあり、Chrome 標準の `Alt+D` / `F6` も残る。

### XKB レイヤの変換 (ctrl:nocaps / altwin) は xremap には見えない

**最重要の落とし穴**。この環境の `xkb-options` は `['ctrl:nocaps', 'altwin:swap_lalt_lwin']`。

```text
物理キー → evdev (xremap はここを見る) → XKB (ctrl:nocaps 等) → アプリ
```

XKB は evdev より上のレイヤなので、`ctrl:nocaps` による Caps Lock → Ctrl の変換は xremap からは見えない。実際、xremap のデバッグログには **`KEY_LEFTCTRL` が一度も現れず `KEY_CAPSLOCK` だけ**が出る。素直に `C-h` と書いても永久にマッチしない（この症状が最初の実装で発生した）。

`modules/xremap/default.nix` では Chrome スコープの `modmap` で `capslock: leftctrl` に変換し、その出力を `keymap` に通して解決している（README「the output of `modmap` goes through `keymap`」）。`application` で Chrome に限定してあるので他アプリの入力経路は変わらず、アプリ判定が失敗しても capslock がそのまま流れて XKB が Ctrl にするだけなので縮退動作は従来どおり。

同じ理由で **`⌘` は evdev では `KEY_LEFTMETA`**（xremap の表記では `Super-` / `Win-`）。`altwin:swap_lalt_lwin` で XKB 上は Alt になっているが、xremap はその手前で消費するので影響を受けない。実測でも `KEY_LEFTALT` は一度も現れない。

切り分けはデバッグログが最速。サービスを止めて手動起動する:

```bash
systemctl --user stop xremap.service
RUST_LOG=debug xremap --watch ~/.config/xremap/config.yml 2>&1 | tee /tmp/xremap.log
```

`=> 1: KEY_XXX` が全キーイベント（`1`=押下 / `0`=解放 / `2`=オートリピート）。`application-client:` 行が一度も出ない場合は、**キー自体が一致していない**（xremap はキー + 修飾キーが一致して初めてアプリ判定を呼ぶ）。

### GNOME Wayland ではアプリ判定に Shell 拡張が要る

xremap は「フォーカス中アプリ」を知らないと `application.only` を判定できない。X11 なら xremap 自身が `WM_CLASS` を読めるが、Wayland にはその汎用 API がない。GNOME では xremap の Shell 拡張 (`xremap@k0kubun.com`) が D-Bus (`com.k0kubun.Xremap`) で WMClass を渡す。

**Chrome 151 は Ubuntu 24.04 でネイティブ Wayland 動作**（`xprop` / `xlsclients` に現れない）なので、この経路が必須。

- nixpkgs の `pkgs.xremap` 既定は **wlroots build**。`override { withVariant = "gnome"; }` で gnome feature 版に差し替える（variant 名は nixpkgs の `pkgs/by-name/xr/xremap/package.nix` の `variants` 参照）
- 拡張は `xdg.dataFile` で `~/.local/share/gnome-shell/extensions/` へリンクする。上記「Nix GUI アプリのランチャー登録」と同じ `XDG_DATA_DIRS` 問題がここにも当てはまる
- `dconf` の `org/gnome/shell` `enabled-extensions` は**配列まるごと置換**。Ubuntu 既定の `ding` / `ubuntu-dock` / `tiling-assistant` を併記しないと消える
- WMClass の実測は `busctl --user call org.gnome.Shell /com/k0kubun/Xremap com.k0kubun.Xremap WMClasses`。GNOME Wayland では `xremap --list-windows` は使えない
- キー名は `parse_key()` が大文字化して `KEY_` を補うので `pageup` / `pagedown` でよい

### 権限設定は root 作業として残る

home-manager では宣言できない。`/dev/uinput` は既定で `root:root 0600`、`uinput` モジュールも未ロード。

```bash
sudo gpasswd -a nanasess input
echo 'KERNEL=="uinput", GROUP="input", TAG+="uaccess", MODE:="0660", OPTIONS+="static_node=uinput"' \
  | sudo tee /etc/udev/rules.d/99-input.rules
echo uinput | sudo tee /etc/modules-load.d/uinput.conf
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo modprobe uinput
```

最後の `modprobe` を省かないこと。`modules-load.d` は `systemd-modules-load.service` が早期ブートで処理する仕組みで、ファイルを置いた時点ではロードされない。ただし**この T2 Mac のカーネルでは `uinput` は組み込み**で、`/dev/uinput` が静的ノードとして最初から存在する（`lsmod | grep uinput` は空、`/sys/devices/virtual/misc/uinput` は存在）。つまり本機では `modules-load.d` も `modprobe` も実質 no-op で、効いているのは udev ルールと `input` グループだけ。手順は他機での再現のために残してある。

**セキュリティ上のトレードオフ**: `input` グループ加入は、このユーザーアカウントに全アプリのキー入力を読む権限を与える（xremap の `doc/running_without_sudo.md` も明記）。画面ロック中もリマップは有効。承知のうえで採用している。「セキュリティ向上のため」と称してこの構成を勝手に変更しないこと。

### 反映手順

`home-manager switch` 後に**再ログインが必要**。理由が 2 つある。

- `input` グループの追加はログインし直さないと反映されない
- **Wayland では GNOME Shell を再起動できない**（X11 の `Alt+F2` → `r` に相当する手段がない）ため、拡張のロードにログインし直しが要る

権限が無い間、`xremap.service` は `Failed to prepare input devices: No device was selected!` で 3 秒ごとに再起動を繰り返す。これは想定内で、権限が付けば解消する。

### 設定変更は `--watch=config,device` で反映される

`ExecStart` が参照するのは安定パス `~/.config/xremap/config.yml` なので、**設定内容が変わってもユニットファイルは変化せず、home-manager はサービスを再起動しない**。裸の `--watch` は device 監視のみ（xremap の CLI 定義が `default_missing_value = "device"`）なので、config も監視対象に含めておかないと `home-manager switch` のたびに `systemctl --user restart xremap.service` が必要になる。

home-manager のシンボリックリンク差し替えでも検知できる。`ConfigWatcher` が親ディレクトリを `IN_CREATE | IN_MOVED_TO` で監視し、ファイル名を照合して watch を張り直す実装になっている（`src/platform_linux/config_watcher.rs`）。

### `exact_match` は既定の false のままにしてある

`false` だと `Ctrl+Shift+H` のように修飾キーが増えた組み合わせにもマッチするが、**余った修飾キーは解放されず保持される**（`event_handler.rs` の `extra_modifiers.retain(|key| ... && !extra_modifiers_pressed.contains(key))`）。つまり出力は `Ctrl+Shift+PageUp` = Chrome のタブ並び替えになる。`H` / `L` のニーモニックと整合する有用な副産物で、これで潰れる Chrome 標準ショートカットも無い。`exact_match: true` を足すとこの動作が消えるだけなので、レビューで指摘されても意図的な選択であることを確認してから判断する。

### 動作確認

```bash
systemctl --user status xremap.service
gnome-extensions info xremap@k0kubun.com          # State: ACTIVE か
busctl --user call org.gnome.Shell /com/k0kubun/Xremap com.k0kubun.Xremap WMClasses
```
