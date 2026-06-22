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
    # マウス選択で通常クリップボードにコピー (Ctrl+V で貼付可能)
    # Linux では selection clipboard にも入るので中クリックペーストも維持される
    # Windows のデフォルトは false, Linux のデフォルトは true (selection のみ)
    copy-on-select = "clipboard";
  };

  # Windows で動作する版に共通のフォントフォールバック
  # - Segoe UI Symbol を追加フォールバック
  #   Ghostty 自動フォールバックリスト (CodepointResolver.zig) に seguisym.ttf が
  #   含まれておらず、U+23F5 (⏵) 等の記号が豆腐になるため明示指定
  windowsFontFamily = settings.font-family ++ [ "Segoe UI Symbol" ];

  # Windows port (PR #12167) 固有の追加設定
  # - command: 起動時に WSL の Gentoo-systemd ディストリをログインシェルで立ち上げる
  #   "direct:" プレフィックスを付けて /bin/sh -c ラップを回避 (Windows には sh が無い)
  #   --cd ~ でホームディレクトリに入る (WezTerm の default_cwd と等価)
  windowsSettings = settings // {
    command = "direct:wsl.exe -d Gentoo-systemd --cd ~";
    font-family = windowsFontFamily;
  };

  # GhostInTheWSL (Codavo/ghostinthewsl) 固有の設定
  # ConPTY を経由せず Hyper-V ソケットのブリッジで WSL2 の Linux PTY に直結するため、
  # Windows port のような command = "direct:wsl.exe ..." は不要 (ブリッジが WSL 接続を担う)。
  # - working-directory: デフォルト (inherit 相当) だと起動プロセス (Windows 側 exe) の
  #   cwd を引き継ぎ、/mnt/c/.../zig-out/bin で WSL シェルが起動してしまう。
  #   そこに blocked な .envrc があると direnv が zsh 初期化中に出力し、p10k instant
  #   prompt の警告を誘発する。
  #   GhostInTheWSL では `home` は無効 (src/Surface.zig の WorkingDirectory.value() が
  #   .home/.inherit に対し null を返し、ブリッジの cwd が空 → Windows cwd へフォールバック
  #   するだけで、upstream のような passwd home 解決が繋がっていない)。
  #   .path の明示パスのみブリッジへ cwd として渡るため、WSL ホームを直接指定する。
  ghostinthewslSettings = settings // {
    font-family = windowsFontFamily;
    working-directory = "/home/nanasess";
  };

  # home-manager の programs.ghostty が内部で使っているのと同じフォーマッタ
  # (listsAsDuplicateKeys = true で keybind = ... 行を複数行に展開)
  renderConfig = lib.generators.toKeyValue {
    mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
    listsAsDuplicateKeys = true;
  };

  configFile = pkgs.writeText "ghostty-config.ghostty" (renderConfig windowsSettings);
  ghostinthewslConfigFile = pkgs.writeText "config.ghostinthewsl" (renderConfig ghostinthewslSettings);
in
{
  # settings / configFile / ghostinthewslConfigFile を
  # 他のモジュール (hosts/*.nix) から参照できるように公開
  _module.args.ghostty = {
    inherit settings configFile ghostinthewslConfigFile;
  };
}
