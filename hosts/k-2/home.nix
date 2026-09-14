# k-2 (NixOS) のユーザー環境。hosts/ubuntu.nix の NixOS 版。
#
# Ubuntu 版にあった以下は NixOS では不要なので持ち込まない:
#  - nixGL wrap (GPU ライブラリはシステムと同じ nixpkgs から来る)
#  - .desktop / アイコンの手動配置 (XDG_DATA_DIRS に /etc/profiles/per-user が入る。
#    docs/nix-desktop-integration.md の問題は NixOS では起きない)
#  - apt パッケージの差分チェック (check-system-packages)
#  - modules/t2-suspend (logind / sleep は configuration.nix で宣言)
{ config, pkgs, ghostty, ... }:

{
  home.homeDirectory = "/home/nanasess";

  # programs._1password-gui (configuration.nix) が systemPackages に入れるので
  # /run/current-system/sw/bin に現れる。ストアパスを直接書くと GUI 更新のたびに
  # git config が変わるため、安定パスで参照する。
  programs.git.signing.signer = "/run/current-system/sw/bin/op-ssh-sign";

  programs.ghostty = {
    enable = true;
    settings = ghostty.settings;
  };

  home.packages = with pkgs; [
    # Wayland セッションでは pgtk ビルドを使う (理由は hosts/ubuntu.nix 参照)。
    emacs31-pgtk
    # Ubuntu で apt から入れていた開発ツール。
    dotnet-sdk_9
    nodejs
  ];

  dconf.settings = {
    # Caps Lock を Ctrl、⌘ と Alt を入れ替え。modules/xremap の modmap
    # (capslock → leftctrl) はこの xkb-options を前提にしている。
    # Ubuntu では gsettings で手動設定していたものを宣言化した。
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "ctrl:nocaps" "altwin:swap_lalt_lwin" ];
    };
  };
}
