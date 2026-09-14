# NixOS on T2 Mac (k-2: MacBookPro16,2)

Intel MacBook Pro 13" 2020 (T2 チップ) を NixOS で運用するための調査結果と手順。
Ubuntu 24.04 (t2linux カーネル) からの移行として着手した (issue #151)。

対象: `hosts/k-2/`, `flake.nix` の `nixosConfigurations."k-2"`。

## T2 固有の事情

T2 チップが NVMe / キーボード / トラックパッド / Touch Bar / オーディオを束ねているため、
素の Linux カーネルでは内蔵入力デバイスが動かない。必要なものはすべて
[nixos-hardware](https://github.com/NixOS/nixos-hardware) の `apple-t2` モジュールが提供する:

| 領域 | 仕組み | 設定 |
|---|---|---|
| カーネル | linux-t2 (t2linux パッチ済み) | モジュールが `boot.kernelPackages` を差し替える |
| キーボード / トラックパッド | `apple-bce` | initrd に組み込み済み |
| Touch Bar | tiny-dfr | `hardware.apple.touchBar.enable` (nixpkgs 本体のモジュール) |
| オーディオ | t2-better-audio の UCM / udev | pipewire / wireplumber を override |
| WiFi / Bluetooth (BCM4364) | Apple 復旧イメージからファームウェア抽出 | `hardware.apple-t2.firmware.enable` |

### ファームウェア

`hardware.apple-t2.firmware.enable = true` は macOS の復旧イメージ (~700MB) を
ダウンロードし、`vmTools.runInLinuxVM` の中で HFS+ をマウントして `brcm/` を取り出す。
QEMU が動けばよく、KVM が使えない環境 (Ubuntu の nix-daemon は nixbld が `kvm` グループに
いない) でも TCG で完走する (2026-09-14 に確認)。ファームウェアは unfree なので
`allowUnfreePredicate` に `brcm-firmware` と `brcm-firmware-<version>-zstd` の両方を入れる
(前者が実体、後者は zstd 圧縮した派生で `lib.getName` が名前を分解できない)。

**`version` は `ventura` を使う。** 既定の `sonoma` は抽出スクリプト `get-wifi` が
BCM4388 (Willamette) のエントリで `AssertionError` を起こして失敗する
(nixos-hardware 24cfdc1、2026-09-14)。この機種のチップは BCM4364B3 "Trinidad" で、
Ventura 版の出力に `brcmfmac4364b3-pcie.apple,trinidad.*` / `brcmbt4364b3-apple,trinidad.*`
が入っていることを確認済み。Ubuntu (`apple-firmware-script`) が使っていたのも
`brcmfmac4364b3-pcie` (`journalctl -k | grep brcmf_fw_alloc_request`)。

失敗する環境向けの保険として、Ubuntu 時代の `/lib/firmware/brcm` を USB に退避してある。
その場合は NixOS 側の `/var/lib/apple-firmware/brcm/` 等に置き、
`boot.kernelParams = [ "firmware_class.path=/var/lib/apple-firmware" ]` でカーネルに
先に探させる (`hardware.firmware` に載せる
[wiki の Method 1](https://wiki.t2linux.org/distributions/nixos/installation/#declarative-setup)
は flake の pure 評価とリポジトリ外パスの相性が悪い)。**このリポジトリは public なので
Apple のファームウェアはコミットしない。**

### カーネルのバイナリキャッシュ

linux-t2 は nixpkgs のキャッシュに無い。t2linux コミュニティの Hydra
(`https://cache.soopy.moe`) を substituter に入れないと自前ビルドになる
(この機種の 4 コアで数時間)。

- インストール後: `hosts/k-2/configuration.nix` の `nix.settings` で宣言済み。
- `nixos-install` 時: まだ効かないので `--option extra-substituters ... --option extra-trusted-public-keys ...` を渡す。
- 別ホスト (Ubuntu / WSL) で k-2 の toplevel をビルドするとき: 一般ユーザーは
  `trusted-substituters` に無い substituter を足せない。`/etc/nix/nix.custom.conf` に
  `extra-trusted-substituters` / `extra-trusted-public-keys` を追記して nix-daemon を
  再起動してから、`--option extra-substituters ... --option extra-trusted-public-keys ...`
  を渡す。キャッシュに目的のカーネルがあるかは
  `curl -sI https://cache.soopy.moe/<store hash>.narinfo` で確認できる。

### 動かないもの

Ubuntu と同じ。内蔵カメラ、Touch ID。

### サスペンド

Ubuntu では `deep` (S3) で動作していた。`modules/t2-suspend` が sudo で配置していた
logind / sleep.conf の設定は `configuration.nix` の `services.logind.settings` /
`systemd.sleep.settings` に移した。8 時間超の長時間サスペンド後に内蔵キーボードが
戻らない既知の限界 (issue #111) は NixOS でも変わらない見込み。

## ディスク構成とブート

```
p1  300M EFI   (LABEL=EFI)   macOS / Ubuntu / NixOS 共用。GRUB 本体のみ
p2  macOS      (APFS)        T2 ファームウェア更新は macOS からしかできないので維持
p3  Ubuntu     (ext4)        安定するまで残す (ロールバック先)
p4  NixOS      (LABEL=nixos) root。/boot は root 内
```

- ESP が 300MB しかなく macOS と共用なので、systemd-boot (世代ごとにカーネル + initrd を
  ESP に置く) は使わない。GRUB を ESP に置き、カーネルは root 側 `/boot` から読む。
- `hardware-configuration.nix` はラベル参照で書いてあり、インストール時に
  `LABEL=nixos` で root を作れば UUID の差し替えが要らない。
  `nixos-generate-config --show-hardware-config` の出力とは必ず突き合わせること。
- `boot.loader.grub.useOSProber = true` で Ubuntu / macOS もメニューに出す。
- GRUB は `boot.loader.grub.efiInstallAsRemovable = true` でリムーバブルパス
  `EFI/BOOT/BOOTX64.EFI` に置く。**Apple の Startup Manager (Option キー) は UEFI の
  `Boot####` エントリを列挙せず、ESP の `EFI/BOOT/BOOTX64.EFI` だけを「EFI Boot」として
  出す** (t2linux wiki の NixOS ページが GRUB 向けに示す構成と同じ)。
  `canTouchEfiVariables` は `efiInstallAsRemovable` と排他 (nixpkgs の assertion) なので
  既定の false のままで、NixOS は NVRAM (`efibootmgr`) を管理しない。
  - 初回インストール (2026-09-14) は `canTouchEfiVariables = true` で行ったため
    `EFI/NixOS-boot-efi/grubx64.efi` + NVRAM `Boot0001` が作られ、`BOOTX64.EFI` は
    Ubuntu の shim のままだった。Option キー → 「EFI Boot」で Ubuntu の shim → `fbx64.efi`
    (fallback) が起動し、**BootOrder を Ubuntu 先頭に書き戻す**ため、以後 Option なしでも
    Ubuntu (GRUB は hidden / timeout 0 でメニューなし) が上がって NixOS に入れなくなった。
    詳細は issue #151 のコメント。
  - Ubuntu の shim は `EFI/ubuntu/shimx64.efi` に残る。Ubuntu 側で
    `grub2/force_efi_extra_removable` を true にすると apt 更新で `BOOTX64.EFI` が
    Ubuntu shim に戻るので触らない (現状 false、`debconf-show grub-efi-amd64` で確認)。
  - Ubuntu の fallback で BootOrder が戻ってしまった場合は、下記「NVRAM の整理」の
    `efibootmgr -c` を再度行う。Ubuntu へは GRUB メニューから入れば fallback は走らない。

## インストール手順 (ランブック)

インストーラ環境では Claude Code が使えないので、上から順に打てる形で書いてある。
値はすべて 2026-09-14 時点の実機から採取したもの (`hosts/k-2/scripts/backup-before-install.sh`
の `info/` と照合できる)。**パーティション番号や MiB 値は打つ前に `parted print` で必ず再確認する。**

### 0. 前提

- Ubuntu が起動している = T2 の Secure Boot 緩和と外部起動許可は済んでいる
- 必要な物: USB-C メモリ 1 本 (ISO 用、2GB 以上)。退避先は Ubuntu の `$HOME` + 別媒体
- PR #152 が main にマージ済み (live 環境で `git clone` する)

### 1. 退避 (Ubuntu 上)

```bash
cd ~/.config/home-manager
# Ubuntu 側 (p3 は残すので live USB から読める) と、別媒体の 2 箇所へ
sudo hosts/k-2/scripts/backup-before-install.sh ~/t2-backup --nm-connections
sudo hosts/k-2/scripts/backup-before-install.sh /media/nanasess/<USB>/t2-backup --nm-connections
```

`--nm-connections` は WiFi / VPN の接続プロファイル (PSK・パスワード入り) を含むので、
退避先は自分しか読めない場所に限る。Ubuntu 24.04 の NetworkManager は netplan
バックエンドで、実体は `/etc/netplan/90-NM-*.yaml`、keyfile 形式は
`/run/NetworkManager/system-connections/` に生成される (`/etc/NetworkManager/system-connections/`
は空)。スクリプトは keyfile を `nm-connections/keyfile/` に、netplan の YAML を
`nm-connections/netplan/` に取る。NixOS 側では keyfile を
`/etc/NetworkManager/system-connections/` に 0600 でコピーすれば同じ接続が使える
(L2TP も同じ NetworkManager-l2tp なので互換。`docker0` / `br-*` / `lo` は不要)。

### 2. インストール USB の作成 (Ubuntu 上)

ISO は `~/Downloads/nixos-t2-iso-minimal-v6.18.35.iso` に取得済み
(t2linux/nixos-t2-iso v6.18.35、2026-06-23 リリース、1,424,670,720 bytes、
sha256 `29ec02ed3a1e35efd72089b9df339c00cf9a93e8474646e700d60d2a49683194`。
上流は checksum を配布していないので、この値は手元で取ったもの)。

```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN          # USB メモリのデバイス名を確認 (sdX)
sudo dd if=/home/nanasess/Downloads/nixos-t2-iso-minimal-v6.18.35.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

`of=` を間違えると内蔵 NVMe を壊すので、`TRAN` が `usb` の行であることを確認してから打つ。
`if=` は絶対パスで書く: zsh は `=` の後ろの `~` を展開しない (`MAGIC_EQUAL_SUBST` が
無効) ため、`if=~/...` は「そのようなファイルはない」で失敗する。

### 3. live USB で起動

1. 再起動して Option (⌥) キーを押し続け、`EFI Boot` (USB) を選ぶ
2. `nixos` ユーザーで自動ログインされる。以降は `sudo -i` で root
3. Ubuntu パーティションを読み取り専用でマウントして退避物を取り出す:
   ```bash
   sudo -i
   mkdir -p /ubuntu && mount -o ro /dev/disk/by-label/Ubuntu /ubuntu
   ```

### 4. live 環境で WiFi を使う

ISO には Apple のファームウェアが入っていない。退避した `brcm/` を置いてドライバを再ロードする:

```bash
mkdir -p /lib/firmware/brcm
cp /ubuntu/home/nanasess/t2-backup/brcm/* /lib/firmware/brcm/
modprobe -r brcmfmac_wcc brcmfmac; modprobe brcmfmac
dmesg | grep brcmf_fw_alloc_request    # "using brcm/brcmfmac4364b3-pcie" が出ればよい

nmcli device wifi list
nmcli device wifi connect "<SSID>" password "<パスフレーズ>"   # または nmtui
ping -c 3 cache.nixos.org
```

(ISO のベース `installation-device.nix` は NetworkManager を有効にしている
(nixpkgs 26.11 時点)。t2linux wiki の `wpa_cli` の記述は古い ISO 向け。
代替: iPhone の USB テザリング、または ISO 同梱の `get-apple-firmware` で
macOS パーティションから直接抽出する Method 4。)

### 5. Ubuntu (p3) の縮小と NixOS 用パーティション (p4) の作成

現在のレイアウト (512B セクタ換算、`parted unit MiB` と一致):

| # | 開始 | 終了 | サイズ | 内容 |
|---|---|---|---|---|
| p1 | 0.02 MiB | 300 MiB | 300 MiB | EFI (`LABEL=EFI`) |
| p2 | 300 MiB | 287022 MiB | 280 GiB | macOS APFS |
| p3 | 287023 MiB | 954204 MiB (末尾) | 651.5 GiB | Ubuntu ext4 (`LABEL=Ubuntu`、使用 180 GiB) |

(ディスクは論理セクタ 4096B だが、上の値は `parted unit MiB` / `/sys/block/.../start`
(512B 換算) から算出したもの。)

Ubuntu を **300 GiB** (287023 → 594223 MiB) に縮め、残り約 351 GiB を NixOS にする。

```bash
umount /ubuntu                              # 3 でマウントしていれば外す
e2fsck -f -n /dev/nvme0n1p3                 # まず読み取り専用で健全性確認
e2fsck -f /dev/nvme0n1p3                    # 実修復 (resize2fs の前提)
resize2fs /dev/nvme0n1p3 298G               # FS を目標より小さめに縮める (G = GiB)
parted /dev/nvme0n1 unit MiB print          # p3 の開始が 287023MiB であることを確認
parted /dev/nvme0n1 resizepart 3 594223MiB  # 確認には Yes
parted -s /dev/nvme0n1 mkpart nixos ext4 594223MiB 100%
parted /dev/nvme0n1 unit MiB print          # p3 = 287023〜594223MiB、p4 = 594223MiB〜末尾
resize2fs /dev/nvme0n1p3                    # サイズ省略 = パーティションいっぱいまで再拡張
e2fsck -f -n /dev/nvme0n1p3                 # 縮小後の Ubuntu が健全か再確認
mkfs.ext4 -L nixos /dev/nvme0n1p4
```

順番を間違えない: **ファイルシステム (resize2fs) → パーティション (resizepart)** の順。
逆にすると Ubuntu のデータが切り落とされる。FS を 298G と小さめにしてから
パーティションを縮め、最後にサイズ省略の `resize2fs` で合わせるのは、parted の
終端の丸め (1 セクタ) で FS がパーティションからはみ出す事故を避けるため。

### 6. マウントとハードウェア定義の照合

```bash
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot/efi && mount /dev/disk/by-label/EFI /mnt/boot/efi
mkdir -p /mnt/home/nanasess/.config
git clone https://github.com/nanasess/home-manager.git /mnt/home/nanasess/.config/home-manager
cd /mnt/home/nanasess/.config/home-manager

nixos-generate-config --root /mnt --show-hardware-config > /tmp/hw.nix
diff /tmp/hw.nix hosts/k-2/hardware-configuration.nix
```

差分の見どころは `boot.initrd.availableKernelModules` と `fileSystems` の by-uuid。
ラベル参照 (`/dev/disk/by-label/nixos`, `EFI`) で動くようにしてあるので、UUID への
置き換えは不要。モジュールに不足があればここで `hardware-configuration.nix` を直す
(コミットは NixOS 起動後でよい。git は tracked でないファイルを flake から見ないので
新規ファイルを足したときは `git add` が要る)。

### 7. nixos-install

```bash
nixos-install --root /mnt \
  --flake /mnt/home/nanasess/.config/home-manager#k-2 \
  --option extra-substituters https://cache.soopy.moe \
  --option extra-trusted-public-keys cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=
# 最後に root のパスワードを聞かれる

nixos-enter --root /mnt -c 'passwd nanasess'          # ユーザーのパスワード
nixos-enter --root /mnt -c 'chown -R nanasess:users /home/nanasess'

# NetworkManager の接続プロファイルを持ち込む (任意。秘密情報を含むので 0600)
install -d -m 0700 /mnt/etc/NetworkManager/system-connections
cp /ubuntu/home/nanasess/t2-backup/nm-connections/keyfile/netplan-NM-*.nmconnection /mnt/etc/NetworkManager/system-connections/
chmod 0600 /mnt/etc/NetworkManager/system-connections/*
```

カーネルの取得元が `cache.soopy.moe` になっていることをログで確認する
(`copying path '/nix/store/...-linux-t2-6.18.46' from 'https://cache.soopy.moe'`)。
自前ビルドに入ってしまった場合は Ctrl-C して substituter の指定を見直す。

`reboot` → Option キーで「EFI Boot」を選ぶか、そのまま起動すれば NixOS の GRUB が出る
(`efiInstallAsRemovable` で `EFI/BOOT/BOOTX64.EFI` が NixOS GRUB になっているため。
Ubuntu の shim が `BOOTX64.EFI` に残っている状態だと「EFI Boot」は Ubuntu に入る。
「ディスク構成とブート」参照)。GRUB メニューに Ubuntu / macOS が出ていることも確認
(`useOSProber`)。

`nixos-install` は NVRAM を触らないので、Option なしの既定起動も NixOS にしたければ
起動後に「NVRAM の整理」の `efibootmgr -c` を行う。

### 8. 起動後 (NixOS 上)

```bash
cd ~/.config/home-manager
git status                        # 6 で hardware-configuration.nix を直していれば差分がある
cat /sys/power/mem_sleep          # [deep] か
dmesg | grep -E 'brcmfmac|apple-bce|hci0'
nmcli device wifi list
```

以降は issue #151 のチェックリストに沿って検証し、結果を本ドキュメントの「実機検証」に記録する。
初回に手動で要るもの: 1Password のサインイン (SSH agent / commit 署名)、`gh auth login`、
Chrome の 1Password 拡張 (`custom_allowed_browsers` が効いているか)、
Claude Code のネイティブインストール (`curl -fsSL https://claude.ai/install.sh | bash`。
汎用 ELF なので `programs.nix-ld` で動かす。stub-ld の "cannot run dynamically linked
executables" が出たら `NIX_LD` / `NIX_LD_LIBRARY_PATH` が入る前の古いシェル)、
OneDrive の認可と SKK 辞書のビルド (下記)。

OneDrive (`modules/onedrive.nix`) は認可前だと `--monitor` サービスがブラウザ認可を 10 分待って
失敗し続けるだけなので、先にサービスを止めて対話的に認可する。yaskkserv2 の配信辞書は
OneDrive 上の `SKK-JISYO.all.utf8` から作るため、辞書が無い間は skkserv が即終了し
ibus-skk / nskk とも漢字変換ができない (README.md「SKK 辞書サーバ」節)。

```bash
systemctl --user stop onedrive
onedrive                              # ブラウザで認可。127.0.0.1:53100 に戻らなければ redirect URI を貼る
# 辞書 (emacs/ddskk) だけ先に取る。sync_list 全体 (howm 3000 ファイル超) を待つと 429 で長引く。
# 初回は「--resync が必要」と言われるので付ける (ローカル状態が無いので失われるものは無い)
onedrive --sync --resync --resync-auth --single-directory emacs/ddskk --download-only
systemctl --user start onedrive         # 残り (howm 等) は monitor サービスに任せる
mkdir -p ~/.local/share/yaskkserv2
yaskkserv2_make_dictionary \
  --dictionary-filename ~/.local/share/yaskkserv2/all \
  --utf8 "$HOME/OneDrive - Skirnir Inc/emacs/ddskk/SKK-JISYO.all.utf8"
systemctl --user restart yaskkserv2
ss -ltn | grep 1178                   # listen していれば OK
pkill -x ibus-engine-skk              # skkserv 起動前に立ち上がった ibus-skk は接続失敗を保持する。
                                      # 落とすと次回 IME 切替時に ibus-daemon が再起動して接続し直す
```

### NVRAM の整理 (初回インストール後に 1 回、NixOS 上)

初回インストールを `canTouchEfiVariables = true` で行った実機向け。`efiInstallAsRemovable`
に切り替えたら **`nixos-rebuild switch --install-bootloader`** で `grub-install` を強制する。
nixpkgs の `install-grub.pl` は `/boot/grub/state` との差分 (devices / efiTarget /
efiSysMountPoint / extraGrubInstallArgs / grub のストアパス) があるときだけ `grub-install` を
走らせ、`efiInstallAsRemovable` / `canTouchEfiVariables` は比較に含まれないため、素の
`switch` では `BOOTX64.EFI` が Ubuntu shim のまま残る (2026-09-14 に実機で確認)。
置換後も NVRAM の旧エントリと `EFI/NixOS-boot-efi/` は残る。NixOS は以後 NVRAM を管理しないので手で直す。
`efibootmgr` は `configuration.nix` の `systemPackages` に入れてある (入る前の世代なら
`nix shell nixpkgs#efibootmgr` で取ってから `sudo` に絶対パスで渡す)。

```bash
sudo ls -la /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/ubuntu/shimx64.efi
                                       # BOOTX64.EFI が switch 時刻 / shim と別サイズ = NixOS GRUB に置換済み。
                                       # 966,664 bytes (2026-03-05) のままなら shim なので先に進まない
sudo efibootmgr -v                     # Boot0000 Ubuntu / Boot0001 NixOS-boot-efi / Boot0080 macOS を確認
                                       # (0082 / FFFF は Apple が作る macOS の重複エントリ。触らない)
sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L NixOS -l '\EFI\BOOT\BOOTX64.EFI'   # 新エントリ (0002)。BootOrder 先頭に入り、Option なし起動も NixOS へ
sudo efibootmgr -v                     # BootOrder: 0002,0001,0000,0080
sudo efibootmgr -B -b 0001             # 旧 NixOS-boot-efi エントリを削除 (新エントリを先に作り、常に NixOS への経路を残す)
sudo rm -r /boot/efi/EFI/NixOS-boot-efi   # 古い grubx64.efi が /boot/grub のモジュールと乖離するのを防ぐ
sudo efibootmgr -v                     # BootOrder: 0002,0000,0080
```

Ubuntu の fallback (`fbx64.efi`) が走って BootOrder が Ubuntu 先頭に戻ったときも同じ
`efibootmgr -c` で直す。**設定変更なしの即時復旧** は `sudo efibootmgr -o <NixOS>,0000,0080`
→ Option を押さずに `reboot`。それでも Ubuntu が上がるなら Ubuntu GRUB 起動の瞬間に Esc →
`c` → `set root=(hd0,gpt1)` / `chainloader /EFI/BOOT/BOOTX64.EFI` / `boot`
(旧構成なら `/EFI/NixOS-boot-efi/grubx64.efi`)。

### ロールバック

- Ubuntu に戻る: GRUB メニューの Ubuntu エントリ (Ubuntu の shim は
  `\EFI\ubuntu\shimx64.efi` のまま残る)。Option キーの「EFI Boot」は NixOS GRUB
  (`BOOTX64.EFI`) であって Ubuntu ではない
- ESP を壊した: live USB から
  `dd if=/ubuntu/home/nanasess/t2-backup/esp-p1.img of=/dev/nvme0n1p1 bs=4M conv=fsync`
- p3 の縮小に失敗した: 別媒体の退避物から復旧するしかない (Ubuntu の再インストール)。
  縮小前の `e2fsck -f -n` を省かないこと

## Ubuntu 版との差分 (home-manager 側)

`hosts/ubuntu.nix` にあった以下は NixOS では不要:

- nixGL wrap — GPU ライブラリがシステムと同じ nixpkgs から来る
- `.desktop` / アイコンの手動配置 — `XDG_DATA_DIRS` に `/etc/profiles/per-user/<user>/share`
  が入るので [docs/nix-desktop-integration.md](nix-desktop-integration.md) の問題が起きない
- apt パッケージ差分チェック
- `modules/ibus-skk/ubuntu.nix` (IBUS_COMPONENT_PATH) — `i18n.inputMethod.ibus.engines` で登録
- `modules/t2-suspend` — `configuration.nix` で宣言
- xremap の root 作業 ([docs/xremap.md](xremap.md)) — `hardware.uinput.enable` + グループ

home-manager は NixOS モジュールとして読み込み `useUserPackages = true` にしている。
パッケージは `/etc/profiles/per-user/nanasess` に入るので、home-manager 側で
`~/.nix-profile` を直書きしてはいけない (`config.home.profileDirectory` を使う)。
`useGlobalPkgs` は使わない: `home.nix` の `nixpkgs.config.allowUnfreePredicate` が
無効化されて評価エラーになる。

## 検証の記録

### 2026-09-14: Ubuntu 上での toplevel ビルド (インストール前)

`nix build --option extra-substituters https://cache.soopy.moe '.#nixosConfigurations.k-2.config.system.build.toplevel'`
が Ubuntu 24.04 (現 k-2) 上で成功。確認した内容:

- カーネル `linux-t2-6.18.46` は `cache.soopy.moe` から取得 (自前ビルドなし)。
  `kernel-modules/.../drivers/staging/apple-bce/apple-bce.ko.xz` あり
- `firmware/brcm/brcmfmac4364b3-pcie.apple,trinidad.*` あり (Ventura 版)
- `sw/share/ibus/component/{mozc,skk}.xml` あり
- `etc/NetworkManager/VPN/nm-l2tp-service.name` と GTK4 エディタプラグインあり
- `etc/systemd/logind.conf` / `sleep.conf` に蓋閉じ suspend / hibernation 無効が反映
- カーネルパラメータ: `intel_iommu=on iommu=pt pm_async=off` (apple-t2 モジュール由来)

### 実機検証

(issue #151 のチェックリストに沿って埋める)

- 2026-09-14 インストール完了。世代 2〜5 まで NixOS 上で `nixos-rebuild switch` できている。
- 2026-09-14 **Option キー → 「EFI Boot」で Ubuntu が起動し GRUB メニューが出ない**
  (issue #151 コメント)。原因は `canTouchEfiVariables = true` で GRUB を
  `EFI/NixOS-boot-efi/` に入れたため `BOOTX64.EFI` が Ubuntu shim のままだったこと。
  `efiInstallAsRemovable = true` に変更し、「NVRAM の整理」を手順化した
  (「ディスク構成とブート」参照)。`switch --install-bootloader` → NVRAM の整理 → 再起動で、
  Option なし / Option キー「EFI Boot」の両方で NixOS GRUB が出ることを確認済み
  (BootOrder: 0002 NixOS, 0000 Ubuntu, 0080 macOS)。
- 自宅ルータ (F660A) が EDNS0 に FORMERR を返し名前解決不能 →
  `networking.resolvconf.dnsExtensionMechanism = false` (`configuration.nix`)。
