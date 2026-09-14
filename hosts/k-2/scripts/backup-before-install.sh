#!/usr/bin/env bash
# NixOS インストール前の退避 (issue #151 手順 2)。Ubuntu 上で root として実行する。
#
#   sudo hosts/k-2/scripts/backup-before-install.sh <退避先ディレクトリ> [--nm-connections]
#
# 退避するもの:
#   brcm/              /lib/firmware/brcm (WiFi/BT ファームウェア)。live USB で WiFi を使う
#                      ため、および hardware.apple-t2.firmware が失敗したときの保険
#   esp-p1.img         ESP (LABEL=EFI, 300MB) の生イメージ。GRUB 導入で壊したときの復元用
#   info/              lsblk / blkid / parted / efibootmgr / fstab / apt の一覧 (照合用)
#   nm-connections/    --nm-connections 指定時のみ。NetworkManager の接続プロファイル
#                      (WiFi / L2TP VPN)。**PSK やパスワードを含む** ので、退避先は
#                      自分しか読めない場所に限る (public な場所・リポジトリに置かない)。
#                      Ubuntu 24.04 の NM は netplan バックエンドで、実体は
#                      /etc/netplan/90-NM-*.yaml、NixOS で使える keyfile 形式は
#                      /run/NetworkManager/system-connections/ に生成される。両方を取る
#
# 退避先は 2 箇所を推奨: Ubuntu の $HOME 配下 (Ubuntu パーティションは残すので live USB
# から p3 をマウントすれば読める) と、USB メモリなど別媒体 (p3 の縮小に失敗した場合の保険)。
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "root で実行してください: sudo $0 $*" >&2
  exit 1
fi

DEST=${1:?退避先ディレクトリを指定してください}
WITH_NM=0
[ "${2:-}" = "--nm-connections" ] && WITH_NM=1

ESP=/dev/disk/by-label/EFI
[ -e "$ESP" ] || { echo "ESP ($ESP) が見つかりません" >&2; exit 1; }

install -d -m 0700 "$DEST" "$DEST/info"

echo "== 1/4 ファームウェア (/lib/firmware/brcm) =="
rm -rf "$DEST/brcm"
cp -a /lib/firmware/brcm "$DEST/brcm"
echo "  $(find "$DEST/brcm" -type f | wc -l) files"

echo "== 2/4 ESP イメージ ($ESP) =="
dd if="$ESP" of="$DEST/esp-p1.img" bs=4M status=progress conv=fsync

echo "== 3/4 システム情報 =="
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,PARTUUID,UUID,MOUNTPOINT > "$DEST/info/lsblk.txt"
blkid > "$DEST/info/blkid.txt"
parted -s /dev/nvme0n1 unit MiB print > "$DEST/info/parted-MiB.txt"
parted -s /dev/nvme0n1 unit s print > "$DEST/info/parted-sectors.txt"
efibootmgr -v > "$DEST/info/efibootmgr.txt" || true
cp /etc/fstab "$DEST/info/fstab"
apt-mark showmanual > "$DEST/info/apt-manual.txt"
dpkg --get-selections > "$DEST/info/dpkg-selections.txt"
cat /sys/class/dmi/id/product_name > "$DEST/info/product_name.txt"
uname -a > "$DEST/info/uname.txt"
journalctl -k -b --no-pager | grep -E 'brcmfmac|Bluetooth: hci0' > "$DEST/info/kernel-brcm.log" || true

if [ "$WITH_NM" -eq 1 ]; then
  echo "== 4/4 NetworkManager 接続プロファイル (秘密情報を含む) =="
  rm -rf "$DEST/nm-connections"
  install -d -m 0700 "$DEST/nm-connections/keyfile" "$DEST/nm-connections/netplan"
  # keyfile 形式 (NixOS の /etc/NetworkManager/system-connections/ にそのまま置ける)。
  # netplan バックエンドでは /run に生成されるので、/etc と /run の両方を見る。
  for d in /etc/NetworkManager/system-connections /run/NetworkManager/system-connections; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 1 -type f -name '*.nmconnection' -exec cp -a {} "$DEST/nm-connections/keyfile/" \;
  done
  # netplan の元ファイル (参照用)。
  find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -exec cp -a {} "$DEST/nm-connections/netplan/" \; 2>/dev/null || true
  find "$DEST/nm-connections" -type f -exec chmod 0600 {} +
  echo "  keyfile: $(find "$DEST/nm-connections/keyfile" -type f | wc -l) files, netplan: $(find "$DEST/nm-connections/netplan" -type f | wc -l) files"
else
  echo "== 4/4 NetworkManager 接続プロファイルはスキップ (--nm-connections で退避) =="
fi

echo "== チェックサム =="
# find の除外条件で SHA256SUMS 自身は読まない (SC2094 は誤検知)。
# shellcheck disable=SC2094
(cd "$DEST" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
chmod -R go-rwx "$DEST"

echo
echo "完了: $DEST"
du -sh "$DEST"
echo "検証: (cd $DEST && sha256sum -c SHA256SUMS)"
