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


  # WSL 固有の zsh 設定
  programs.zsh.initContent = lib.mkAfter ''
    # VS Code PATH (WSL)
    export PATH="/mnt/c/Users/''${USER}/AppData/Local/Programs/Microsoft VS Code/bin":$PATH

    # X11/Wayland symlinks for WSLg
    if [ ! -L /tmp/.X11-unix ]; then
      rm -rf /tmp/.X11-unix
      ln -s /mnt/wslg/.X11-unix /tmp/.X11-unix
    fi
    if [ ! -L "''${XDG_RUNTIME_DIR}/wayland-0" ]; then
      rm -rf "''${XDG_RUNTIME_DIR}/wayland-0*"
      ln -s /mnt/wslg/runtime-dir/wayland-0* "$XDG_RUNTIME_DIR"
    fi

    # keyboard layout
    if [ -z "$WAYLAND_DISPLAY" ]; then
      if which setxkbmap > /dev/null; then setxkbmap -layout us; fi
    fi
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
