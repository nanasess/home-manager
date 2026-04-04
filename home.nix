{ config, pkgs, lib, ... }:

{
  home.username = "nanasess";
  home.stateVersion = "24.05";

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "terraform"
    ];

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
    terraform
    azure-cli
    awscli2
    hugo

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

  programs.zoxide = {
    enable = true;
  };

  programs.mise = {
    enable = true;
    globalConfig = {
      tools = {
        node = "lts";
      };
    };
  };

  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    PAGER = "less";
    LESSCHARSET = "utf-8";
    LESS = "-R";
    JQ_COLORS = "1;36:0;33:0;33:0;36:0;32:1;39:1;39";
  };

  home.file.".signature".text = ''
    Kentaro Ohkouchi
  '';

  home.file.".local/bin/emacs-wrapper" = lib.mkIf pkgs.stdenv.isLinux {
    executable = true;
    text = ''
      #!/bin/bash
      export PATH="${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      export GTK_IM_MODULE=none
      export XMODIFIERS=@im=none
      exec /usr/bin/emacs "$@"
    '';
  };

  home.file.".local/bin/emacsclient-wrapper" = lib.mkIf pkgs.stdenv.isLinux {
    executable = true;
    text = ''
      #!/bin/bash
      export PATH="${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      export GTK_IM_MODULE=none
      export XMODIFIERS=@im=none
      if [ -n "$*" ]; then
        exec /usr/bin/emacsclient --alternate-editor= --reuse-frame "$@"
      else
        exec /usr/bin/emacsclient --alternate-editor= --create-frame
      fi
    '';
  };

  home.file.".local/share/applications/emacs.desktop" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      [Desktop Entry]
      Name=Emacs (GUI)
      GenericName=Text Editor
      Comment=GNU Emacs is an extensible, customizable text editor - and more
      MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
      Exec=${config.home.homeDirectory}/.local/bin/emacs-wrapper %F
      Icon=emacs
      Type=Application
      Terminal=false
      Categories=Utility;Development;TextEditor;
      StartupNotify=true
      StartupWMClass=Emacs
      Keywords=Text;Editor;
      TryExec=/usr/bin/emacs
    '';
  };

  home.file.".local/share/applications/emacsclient.desktop" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      [Desktop Entry]
      Name=Emacs (Client)
      GenericName=Text Editor
      Comment=Edit text
      MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;x-scheme-handler/org-protocol;
      Exec=${config.home.homeDirectory}/.local/bin/emacsclient-wrapper %F
      Icon=emacs
      Type=Application
      Terminal=false
      Categories=Development;TextEditor;
      StartupNotify=true
      StartupWMClass=Emacs
      Keywords=emacsclient;

      [Desktop Action new-window]
      Name=New Window
      Exec=${config.home.homeDirectory}/.local/bin/emacsclient-wrapper %F

      [Desktop Action new-instance]
      Name=New Instance
      Exec=${config.home.homeDirectory}/.local/bin/emacs-wrapper %F
    '';
  };
}
