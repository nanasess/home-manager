# wsl-nixos: WSL2 上の NixOS (NixOS-WSL)。wsl-gentoo からの移行先 (Issue #183)。
#
# WSL 固有の部分 (/init からの起動、wsl.conf、WSLg の X11 ソケット、/bin の populate) は
# NixOS-WSL の wsl.* モジュールが担う。k-2 と共通のシステム設定は modules/nixos/common.nix、
# ユーザー環境は ./home.nix + modules/wsl (home-manager)。
#
# 初回導入は flake から tarball を作って `wsl --install --from-file` する (README 参照)。
{ pkgs, lib, ... }:

{
  imports = [
    # zsh / nix-ld / 1Password / Chrome の 1Password 拡張 (k-2 と共通)
    ../../modules/nixos/common.nix
  ];

  wsl = {
    enable = true;
    defaultUser = "nanasess";
    # Docker Desktop の WSL 統合。Windows 側の Docker Desktop の設定
    # (Resources > WSL integration) でこのディストリを有効にする。
    docker-desktop.enable = true;
  };

  # NixOS-WSL の既定 (sudo にパスワード不要) を戻す。既定ユーザーにはパスワードが無いので、
  # 導入直後に `wsl -d NixOS -u root passwd nanasess` で設定する (root は wsl -u root で
  # 常に入れるので締め出されることはない)。
  security.sudo.wheelNeedsPassword = true;

  # wsl.conf の [network] hostname にも使われる。並行運用中に Gentoo と区別するため
  # Windows のホスト名は引き継がない。
  networking.hostName = "wsl-nixos";

  # DNS は NixOS-WSL の既定 (wsl.conf の generateResolvConf = true) のままにする。
  # .wslconfig が networkingMode=mirrored + dnsTunneling なので、WSL が生成する
  # resolv.conf (10.255.255.254) 経由で Windows 側の DNS (VPN 接続時を含む) に従う。
  # Gentoo は generateResolvConf=false + systemd-resolved だったが、上流 DNS を何も
  # 設定しておらず Fallback DNS (1.1.1.1 等) で解決していただけなので再現しない。

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  environment.systemPackages = with pkgs; [
    # 初回の nixos-rebuild (flake の取得) と、home-manager より先に要る場面のため
    git
    vim
    google-chrome
    # WSLg の描画確認用 (glxinfo -B / xeyes)。wsl-gentoo の mesa-progs / xeyes 相当
    mesa-demos
    xeyes
  ];

  # wsl-gentoo の sys-apps/plocate 相当 (既定のパッケージが plocate)
  services.locate.enable = true;

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "1password"
      "1password-cli"
      "google-chrome"
    ];

  users.users.nanasess = {
    shell = pkgs.zsh;
    # isNormalUser / uid 1000 / wheel は wsl.defaultUser から NixOS-WSL が付ける。
    # docker グループは wsl.docker-desktop が付ける。
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "nanasess" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # 最初にインストールした NixOS のリリース。変更しないこと。
  system.stateVersion = "26.11";
}
