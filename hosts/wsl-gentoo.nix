{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/home/nanasess";

  home.sessionVariables = {
    BROWSER = "wslview";
  };

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
