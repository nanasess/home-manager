{ config, pkgs, lib, ... }:

{
  home.username = "nanasess";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # CLI tools
    ripgrep
    fd
    fzf
    eza
    jq
    tree
    htop
    cmigemo

    # Development
    git-lfs
    gh
    sheldon

    # Fonts
    noto-fonts
    noto-fonts-color-emoji
  ]
  ++ lib.optionals stdenv.isLinux [
    wakatime-cli
  ]
  ++ lib.optionals stdenv.isDarwin [
    coreutils
  ];

  programs.git = {
    enable = true;
    userName = "Kentaro Ohkouchi";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
  };

  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    PAGER = "less";
    LESSCHARSET = "utf-8";
    LESS = "-R";
    JQ_COLORS = "1;36:0;33:0;33:0;36:0;32:1;39:1;39";
  };

  home.file.".local/bin/op" = lib.mkIf pkgs.stdenv.isLinux {
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

  home.file.".signature".text = ''
    Kentaro Ohkouchi
  '';
}
