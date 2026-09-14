# k-2 (MacBookPro16,2) のハードウェア定義。
#
# インストール前に書いた暫定版。パーティションは UUID ではなくラベルで参照し、
# インストール時に `LABEL=nixos` で root を作れば nixos-generate-config を
# 待たずに評価/ビルドできるようにしてある。インストール後に
#   nixos-generate-config --show-hardware-config
# の出力 (availableKernelModules 等) と突き合わせて差分を取り込むこと (issue #151)。
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # apple-bce (内蔵キーボード / トラックパッド) は nixos-hardware の apple-t2 が
  # initrd.kernelModules に足す。ここは NVMe とストレージ周りのみ。
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # ディスク構成 (issue #151):
  #   p1  EFI   (LABEL=EFI)   macOS / Ubuntu と共用の ESP。GRUB 本体のみ置く
  #   p2  macOS (APFS)        T2 ファームウェア更新用に維持
  #   p3  Ubuntu (ext4)       安定するまで残す
  #   p4  NixOS (LABEL=nixos) root。カーネル/initrd は root 側 /boot に置く
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # ハイバネーションは使わない (T2 では復帰に失敗する。modules/t2-suspend 参照) ので
  # スワップパーティションは切らず zram で済ませる。
  swapDevices = [ ];
  zramSwap.enable = true;

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
