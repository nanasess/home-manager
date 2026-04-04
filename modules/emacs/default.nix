{ config, pkgs, lib, ... }:

{
  home.file.".emacs.d/init.el".source = ./init.el;
  home.file.".emacs.d/early-init.el".source = ./early-init.el;
  home.file.".emacs.d/init.d".source = ./init.d;
  home.file.".emacs.d/site-lisp".source = ./site-lisp;

  home.activation.elpacaLockFile = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${./elpaca.lock} ${config.home.homeDirectory}/.emacs.d/elpaca.lock
  '';

  home.packages = with pkgs; [
    cmigemo
  ];

  home.file.".local/bin/emacs-wrapper" = lib.mkIf pkgs.stdenv.isLinux {
    executable = true;
    text = ''
      #!/bin/bash
      export PATH="${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      export GTK_IM_MODULE=none
      export XMODIFIERS=@im=none
      exec emacs "$@"
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
        exec emacsclient --alternate-editor= --reuse-frame "$@"
      else
        exec emacsclient --alternate-editor= --create-frame
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
      TryExec=${config.home.homeDirectory}/.nix-profile/bin/emacs
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
