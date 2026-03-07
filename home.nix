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

  programs.zoxide = {
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

  home.file.".signature".text = ''
    Kentaro Ohkouchi
  '';

  xdg.desktopEntries = lib.mkIf pkgs.stdenv.isLinux {
    emacs = {
      name = "Emacs (GUI)";
      genericName = "Text Editor";
      comment = "GNU Emacs is an extensible, customizable text editor - and more";
      mimeType = [
        "text/english" "text/plain" "text/x-makefile" "text/x-c++hdr"
        "text/x-c++src" "text/x-chdr" "text/x-csrc" "text/x-java"
        "text/x-moc" "text/x-pascal" "text/x-tcl" "text/x-tex"
        "application/x-shellscript" "text/x-c" "text/x-c++"
      ];
      exec = ''sh -c "export PATH=\\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\\$PATH; exec env GTK_IM_MODULE=none XMODIFIERS=@im=none /usr/bin/emacs \\$@" sh %F'';
      icon = "emacs";
      terminal = false;
      categories = [ "Utility" "Development" "TextEditor" ];
      startupNotify = true;
      settings = {
        StartupWMClass = "Emacs";
        Keywords = "Text;Editor;";
        TryExec = "/usr/bin/emacs";
      };
    };
    emacsclient = {
      name = "Emacs (Client)";
      genericName = "Text Editor";
      comment = "Edit text";
      mimeType = [
        "text/english" "text/plain" "text/x-makefile" "text/x-c++hdr"
        "text/x-c++src" "text/x-chdr" "text/x-csrc" "text/x-java"
        "text/x-moc" "text/x-pascal" "text/x-tcl" "text/x-tex"
        "application/x-shellscript" "text/x-c" "text/x-c++"
        "x-scheme-handler/org-protocol"
      ];
      exec = ''sh -c "export PATH=\\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\\$PATH; if [ -n \"\\$*\" ]; then exec env GTK_IM_MODULE=none XMODIFIERS=@im=none /usr/bin/emacsclient --alternate-editor= --reuse-frame \"\\$@\"; else exec env GTK_IM_MODULE=none XMODIFIERS=@im=none emacsclient --alternate-editor= --create-frame; fi" sh %F'';
      icon = "emacs";
      terminal = false;
      categories = [ "Development" "TextEditor" ];
      startupNotify = true;
      settings = {
        StartupWMClass = "Emacs";
        Keywords = "emacsclient;";
      };
      actions = {
        new-window = {
          name = "New Window";
          exec = ''sh -c "export PATH=\\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\\$PATH; exec env GTK_IM_MODULE=none XMODIFIERS=@im=none /usr/bin/emacsclient --alternate-editor= --create-frame \\$@" sh %F'';
        };
        new-instance = {
          name = "New Instance";
          exec = ''sh -c "export PATH=\\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\\$PATH; exec env GTK_IM_MODULE=none XMODIFIERS=@im=none emacs \\$@" sh %F'';
        };
      };
    };
  };
}
