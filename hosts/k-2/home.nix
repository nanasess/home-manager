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

  # 1Password の設定画面にある「ログイン時に起動」は Linux では
  # /usr/share/applications/1password.desktop を ~/.config/autostart/ にコピーする実装
  # (op-startup/src/linux.rs) で、NixOS にはそのパスが無いため黙って失敗する
  # (settings.json に app.startAtLogin も残らない)。代わりに autostart エントリを
  # 宣言する。--silent はウィンドウを出さずに常駐 (SSH agent / ブラウザ連携用)。
  # k-2 の GNOME にはトレイ拡張が無いのでアイコンは出ない。ウィンドウはランチャーから
  # 起動すると既存インスタンスにフォーカスする。設定画面のトグルは OFF 表示のまま。
  xdg.configFile."autostart/1password.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=1Password
    Exec=1password --silent %U
    Icon=1password
    StartupWMClass=1Password
    Terminal=false
    X-GNOME-Autostart-enabled=true
  '';

  programs.ghostty = {
    enable = true;
    settings = ghostty.settings;
  };

  home.packages = with pkgs; [
    # Wayland セッションでは pgtk ビルドを使う (理由は hosts/ubuntu.nix 参照)。
    emacs31-pgtk
    # Ubuntu で apt から入れていた開発ツール。
    dotnet-sdk_10
    nodejs
    # EcAuth の E2ETests (pnpm + Playwright) 用。packageManager フィールドの pnpm@10.x は
    # pnpm 10 自身が自動解決する (corepack 不要)。ブラウザは configuration.nix の
    # nix-ld ライブラリで公式バイナリを動かす。
    pnpm_10
  ];

  # XDG ユーザーディレクトリを英語名に固定する。ja_JP.UTF-8 だと初回ログインの
  # xdg-user-dirs-update が ~/ダウンロード 等を作るので、user-dirs.dirs を宣言し
  # user-dirs.conf (enabled=False) で以後のログイン時の再生成 (再ローカライズ) を止める。
  # 既存の日本語ディレクトリは移さない (中身を手で移す。docs/nixos-t2.md)。
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # home-manager 独自の XDG_PROJECTS_DIR (~/Projects) は使わない (~/git-repos がある)。
    projects = null;
  };

  dconf.settings = {
    # Caps Lock を Ctrl、⌘ と Alt を入れ替え。modules/xremap の modmap
    # (capslock → leftctrl) はこの xkb-options を前提にしている。
    # Ubuntu では gsettings で手動設定していたものを宣言化した。
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "ctrl:nocaps" "altwin:swap_lalt_lwin" ];
    };
    # トラックパッドはタップではなく押し込みでクリックする。GNOME 50 の
    # gsettings-desktop-schemas は tap-to-click の既定が true なので明示的に切る。
    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = false;
    };
  };
}
