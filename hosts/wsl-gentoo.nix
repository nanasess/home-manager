{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/home/nanasess";

  home.sessionVariables = {
    BROWSER = "wslview";
    GTK_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };

  programs.ghostty = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.ghostty;
    settings = {
      font-family = "Ubuntu Sans Mono";
      font-size = 13;
      theme = "iTerm2 Solarized Light";
      scrollbar = "system";
    };
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-skk
      fcitx5-gtk
    ];
  };

  # OneDrive の SKK 辞書へスペースなしのシンボリックリンクを作成
  home.file.".local/share/skk/SKK-JISYO.ALL".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/OneDrive - Skirnir Inc/emacs/ddskk/SKK-JISYO.ALL";

  # fcitx5-skk の辞書設定（ユーザー辞書 + OneDrive の SKK-JISYO.ALL）
  xdg.dataFile."fcitx5/skk/dictionary_list".text = ''
    type=file,file=$FCITX_CONFIG_DIR/skk/user.dict,mode=readwrite
    type=file,file=${config.home.homeDirectory}/.local/share/skk/SKK-JISYO.ALL,mode=readonly
  '';

  # fcitx5-gtk の GTK4 IM モジュールを GTK が見つけられるようにする
  home.sessionVariablesExtra = ''
    export GTK_PATH="${config.i18n.inputMethod.package}/lib/gtk-4.0''${GTK_PATH:+:$GTK_PATH}"
  '';

  # WezTerm 設定を Windows 側にコピー
  home.activation.weztermConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${../modules/wezterm/wezterm.lua} /mnt/c/Users/${config.home.username}/.wezterm.lua
  '';

  home.file.".local/bin/op" = {
    executable = true;
    text = ''
      #!/bin/bash
      OP_EXE="/mnt/c/Users/${config.home.username}/AppData/Local/Microsoft/WinGet/Links/op.exe"
      OP_LINUX="/usr/bin/op"

      # op run は Linux のバイナリを実行するため、Windows の op.exe では動作しない
      if [ "$1" = "run" ] && [ -x "$OP_LINUX" ]; then
        exec "$OP_LINUX" "$@"
      fi

      if [ ! -f "$OP_EXE" ]; then
        echo "[ERROR] op.exe not found at $OP_EXE" >&2
        exit 1
      fi

      OP_VARS=$(env | grep ^OP_ | cut -d= -f1 | tr '\n' ':')
      export WSLENV="''${WSLENV:-}:''${OP_VARS%:}"
      exec "$OP_EXE" "$@"
    '';
  };
}
