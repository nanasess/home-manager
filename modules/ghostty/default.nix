{ pkgs, lib, ... }:

let
  # 全ホスト共通の Ghostty 設定
  # Linux (home-manager programs.ghostty.settings) と Windows port
  # (%LOCALAPPDATA%\ghostty\config.ghostty) で共有する
  settings = {
    # UDEV Gothic JPDOC をプライマリ、NF を Nerd Font フォールバックとして使用
    # (WezTerm 設定と合わせる。modules/wezterm/wezterm.lua 参照)
    font-family = [
      "UDEV Gothic JPDOC"
      "UDEV Gothic NF"
    ];
    font-size = 13;
    keybind = [
      "ctrl+l=next_tab"
      "ctrl+h=previous_tab"
    ];
    theme = "iTerm2 Solarized Light";
  };

  # Windows 版固有の追加設定
  # - command: 起動時に WSL の Gentoo-systemd ディストリをログインシェルで立ち上げる
  #   "direct:" プレフィックスを付けて /bin/sh -c ラップを回避 (Windows には sh が無い)
  #   --cd ~ でホームディレクトリに入る (WezTerm の default_cwd と等価)
  # - font-family: Segoe UI Symbol を追加フォールバック
  #   Ghostty 自動フォールバックリスト (CodepointResolver.zig) に seguisym.ttf が
  #   含まれておらず、U+23F5 (⏵) 等の記号が豆腐になるため明示指定
  windowsSettings = settings // {
    command = "direct:wsl.exe -d Gentoo-systemd --cd ~";
    font-family = settings.font-family ++ [ "Segoe UI Symbol" ];
  };

  # home-manager の programs.ghostty が内部で使っているのと同じフォーマッタ
  # (listsAsDuplicateKeys = true で keybind = ... 行を複数行に展開)
  renderConfig = lib.generators.toKeyValue {
    mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
    listsAsDuplicateKeys = true;
  };

  configFile = pkgs.writeText "ghostty-config.ghostty" (renderConfig windowsSettings);
in
{
  # settings / configFile を他のモジュール (hosts/*.nix) から参照できるように公開
  _module.args.ghostty = {
    inherit settings configFile;
  };
}
