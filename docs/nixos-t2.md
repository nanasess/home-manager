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

## インストール手順

1. **退避**: `/lib/firmware/brcm` を USB へ。ESP (`p1`) を `dd` でイメージ退避。
2. **ISO**: [t2linux/nixos-t2-iso](https://github.com/t2linux/nixos-t2-iso) の
   `nixos-t2-iso-minimal.iso` (純正 ISO は apple-bce が無く内蔵キーボードが効かない)。
   USB-C メモリに書き込み、Option キー起動。
3. **パーティション**: live 環境から Ubuntu (`p3`) を `e2fsck -f` → `resize2fs` で縮小し、
   空き領域に `p4` を作成、`mkfs.ext4 -L nixos`。
4. **インストール**:
   ```bash
   mount /dev/disk/by-label/nixos /mnt
   mkdir -p /mnt/boot/efi && mount /dev/disk/by-label/EFI /mnt/boot/efi
   git clone https://github.com/nanasess/home-manager /mnt/etc/nixos-src   # 任意の場所でよい
   nixos-install --flake '/mnt/etc/nixos-src#k-2' \
     --option extra-substituters https://cache.soopy.moe \
     --option extra-trusted-public-keys cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=
   ```
5. 再起動後、`nixos-generate-config --show-hardware-config` と
   `hosts/k-2/hardware-configuration.nix` を突き合わせる。

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

(インストール後に埋める。issue #151 のチェックリスト参照)
