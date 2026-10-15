# wsl-nixos のユーザー環境。WSL 共通部分は modules/wsl。
{ ... }:

let
  # システムパッケージ (configuration.nix / modules/nixos/common.nix) の実体。
  # store パスを直書きすると更新のたびに切れるので、現在の世代を指すリンク経由にする。
  sw = "/run/current-system/sw";
in
{
  home.homeDirectory = "/home/nanasess";

  # programs._1password (modules/nixos/common.nix) の security wrapper が
  # setgid onepassword-cli 付きで生成する。
  wsl.opLinux = "/run/wrappers/bin/op";

  # WSLg のスタートメニュー (Windows 側の「<アプリ名> (NixOS)」ショートカット) の元。
  # WSLg は /usr/share/applications 等の固定パスと、modules/wsl が .wslgconfig で足した
  # ~/.local/share/wslg/applications しか見ない。NixOS の .desktop は
  # /run/current-system/sw/share/applications にあって読まれないので、ここに置き直す。
  # Icon= の相対名も /usr/share/icons と /usr/share/pixmaps しか探さないため絶対パスにする。
  # wsl-gentoo は portage 版が /usr/share/applications にあるので、こちらだけに置く
  # (共通の modules/wsl に置くと Gentoo では二重に登録される)。
  # ファイル名から .desktop を除いた部分が WSLg のキーで、ウィンドウの WM_CLASS と一致すると
  # タスクバーのアイコンにも使われる (Chrome は google-chrome で一致する。1Password の
  # WM_CLASS は com.onepassword.OnePassword で一致しないので modules/wsl の
  # wslg-net-wm-icon が別途アイコンを付ける)。
  # WSLg は起動時に存在しないフォルダを監視しないので、初回は wsl --shutdown が必要。
  xdg.dataFile."wslg/applications/1password.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=1Password
    Exec=${sw}/bin/1password %U
    Icon=${sw}/share/icons/hicolor/256x256/apps/1password.png
    StartupWMClass=1Password
  '';
  xdg.dataFile."wslg/applications/google-chrome.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Google Chrome
    Exec=${sw}/bin/google-chrome-stable %U
    Icon=${sw}/share/icons/hicolor/256x256/apps/google-chrome.png
    StartupWMClass=google-chrome
  '';
}
