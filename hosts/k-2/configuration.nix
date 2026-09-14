# k-2: Intel MacBook Pro 13" 2020 (MacBookPro16,2, T2 チップ) の NixOS システム設定。
#
# Ubuntu 24.04 (t2linux カーネル) からの移行先。経緯と手順は issue #151。
# T2 固有の部分 (linux-t2 カーネル / apple-bce / Touch Bar / T2 オーディオ /
# WiFi・BT ファームウェア) は nixos-hardware の apple-t2 モジュールが担い、
# ここではそれ以外のシステム構成を宣言する。ユーザー環境は ./home.nix (home-manager)。
{ config, pkgs, lib, ... }:

let
  # nixpkgs / apt には 1.4.4 が無いため上流をローカルでビルドする (pkgs/ibus-skk.nix)。
  # Ubuntu では IBUS_COMPONENT_PATH で登録していたが (modules/ibus-skk/ubuntu.nix)、
  # NixOS は i18n.inputMethod.ibus.engines で ibus 本体ごと束ねるので不要。
  ibus-skk = pkgs.callPackage ../../pkgs/ibus-skk.nix { };
in
{
  imports = [ ./hardware-configuration.nix ];

  # ---------------------------------------------------------------------------
  # T2 (nixos-hardware apple-t2)
  # ---------------------------------------------------------------------------

  # WiFi / Bluetooth (BCM4364B3 "Trinidad") のファームウェアを Apple の復旧イメージから
  # 宣言的に抽出する。vmTools.runInLinuxVM で HFS+ をマウントするため QEMU が動く
  # (KVM が無くても TCG で完走する。Ubuntu 上での事前ビルドで確認済み)。
  #
  # version は ventura に固定。既定の sonoma は抽出スクリプト (get-wifi) が BCM4388
  # (Willamette) のエントリで AssertionError を起こして失敗する (2026-09-14、
  # nixos-hardware 24cfdc1)。ventura 版に brcmfmac4364b3-pcie.apple,trinidad.* と
  # brcmbt4364b3-apple,trinidad.* が入っていることは確認済み。
  #
  # 失敗する場合の保険として、Ubuntu 時代の /lib/firmware/brcm を USB に退避してある
  # (issue #151)。その場合は boot.kernelParams の firmware_class.path= でリポジトリ外の
  # ディレクトリを指す (public リポジトリに Apple のファームウェアは置かない)。
  hardware.apple-t2.firmware = {
    enable = true;
    version = "ventura";
  };

  # Touch Bar (tiny-dfr)。nixos-hardware 側の enableTinyDfr は nixpkgs 本体の
  # モジュールに統合され削除されたため、こちらを使う。
  hardware.apple.touchBar.enable = true;

  # サスペンド (modules/t2-suspend の NixOS 版。Ubuntu では sudo で /etc に配置していた)。
  #  - hibernation は BCE コントローラが電源復帰できず失敗するので封じる
  #  - 蓋閉じ → suspend。外部モニタ接続 (docked) 時は無視 (gsettings と整合)
  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
  };
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  services.thermald.enable = true;

  # ---------------------------------------------------------------------------
  # ブート
  # ---------------------------------------------------------------------------

  # ESP (300MB) は macOS と共用で小さいため、systemd-boot のように世代ごとに
  # カーネル + initrd を ESP に積む方式は採らない。GRUB を ESP に置き、カーネルは
  # root 側の /boot から読ませる (Ubuntu と同じ構成)。
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      # 併存する Ubuntu / macOS をメニューに出す (ロールバック経路)。
      useOSProber = true;
      configurationLimit = 20;
    };
  };

  # ---------------------------------------------------------------------------
  # ネットワーク
  # ---------------------------------------------------------------------------

  networking.hostName = "k-2";
  networking.networkmanager = {
    enable = true;
    # L2TP/IPsec (PSK + MS-CHAPv2) のリモートアクセス VPN 用。strongSwan / xl2tpd を
    # 同梱しており、NixOS モジュール側で /etc/ipsec.secrets の include
    # (NixOS/nixpkgs#64965) も処理される。Ubuntu の network-manager-l2tp(-gnome) 相当。
    plugins = [ pkgs.networkmanager-l2tp ];
  };

  # ---------------------------------------------------------------------------
  # ロケール / 入力
  # ---------------------------------------------------------------------------

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = [
      pkgs.ibus-engines.mozc
      ibus-skk
    ];
  };

  # ---------------------------------------------------------------------------
  # デスクトップ (GNOME)
  # ---------------------------------------------------------------------------

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  services.pulseaudio.enable = false;
  hardware.bluetooth.enable = true;

  # xremap (modules/xremap) 用。Ubuntu では udev ルールと input グループを sudo で
  # 用意していたが、NixOS では uinput グループ + udev ルールをここで宣言する。
  hardware.uinput.enable = true;

  fonts.packages = with pkgs; [
    # Ubuntu では OS の静的 Noto CJK (fonts-noto-cjk) に委譲していた。nixpkgs の既定は
    # 可変フォント版で Emacs (ftcrhb) が realize できず豆腐になるため (home.nix の
    # コメント参照)、静的版を選ぶ。
    noto-fonts-cjk-sans-static
    noto-fonts-cjk-serif-static
    # GNOME の UI フォント (Adwaita Sans)。
    adwaita-fonts
  ];

  # ---------------------------------------------------------------------------
  # サービス / プログラム
  # ---------------------------------------------------------------------------

  virtualisation.docker.enable = true;

  # zsh をログインシェルにするには NixOS 側でも有効化が必要 (/etc/shells 登録)。
  # 設定本体は modules/zsh (home-manager)。
  programs.zsh.enable = true;

  # 1Password。SSH agent (~/.1password/agent.sock) と commit 署名 (op-ssh-sign) は
  # home.nix / hosts/k-2/home.nix から参照する。
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "nanasess" ];
  };
  # nixpkgs の Chrome はストアパスから起動するため、1Password のブラウザ連携が
  # 許可リストで弾く。バイナリ名 (chrome) を許可する。
  # 要確認: 実機で拡張から接続できなければ wiki.nixos.org/wiki/1Password を参照。
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      chrome
    '';
    mode = "0755";
  };

  # GUI アプリは home-manager の pkgs (home.nix の allowUnfreePredicate) と分けて
  # システム側で管理する。unfree の許可はこのファイルの nixpkgs.config に集約。
  environment.systemPackages = with pkgs; [
    google-chrome
    slack
    spotify
    dbeaver-bin
    gnome-tweaks
    vim
    git
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "1password"
      "1password-cli"
      # nixos-hardware apple-t2 の WiFi/BT ファームウェア (Apple 復旧イメージ由来)。
      # 実体 (pname brcm-firmware) と、それを zstd 圧縮した派生 (名前が
      # brcm-firmware-<macOS version>-zstd で lib.getName が分解できない) の両方が要る。
      "brcm-firmware"
      "brcm-firmware-ventura-zstd"
      "google-chrome"
      "slack"
      "spotify"
    ];

  # ---------------------------------------------------------------------------
  # ユーザー / Nix
  # ---------------------------------------------------------------------------

  users.users.nanasess = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      # xremap (evdev 読み取り / uinput 書き込み)。セキュリティ上のトレードオフは
      # modules/xremap/default.nix のコメント参照。
      "input"
      "uinput"
    ];
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "nanasess" ];
    # t2linux コミュニティの Hydra。linux-t2 カーネルを自前ビルドしないために使う
    # (https://wiki.t2linux.org/distributions/nixos/faq/#substituter-setup)。
    # nixos-install 時はまだ効かないので --option で同じ値を渡すこと (issue #151)。
    # substituters は既定値 (cache.nixos.org) を置き換えるので明示的に併記する。
    substituters = [
      "https://cache.nixos.org/"
      "https://cache.soopy.moe"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # 最初にインストールした NixOS のリリース。変更しないこと。
  system.stateVersion = "26.05";
}
