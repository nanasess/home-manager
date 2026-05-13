{ config, pkgs, lib, ... }:

let
  # Emacs treesit が探すファイル名 (拡張子なし) → nixpkgs の grammar 派生物。
  # キー名は各 major mode が `treesit-ready-p` などに渡す言語シンボルに合わせる
  # (例: csharp-ts-mode は 'c-sharp を使うため、ファイル名も libtree-sitter-c-sharp.so にする)。
  # Emacs 30.2 内蔵 php-ts-mode の font-lock クエリは tree-sitter-php v0.23.x の
  # ノード型 (例: var_modifier) に依存している。nixpkgs の tree-sitter-php は
  # 0.24.2 でこのノードが削除されているため `treesit-query-error` が発生する。
  # php-ts-mode--language-source-alist が要求する v0.23.11 にダウングレードする。
  treesitPhp = pkgs.tree-sitter-grammars.tree-sitter-php.overrideAttrs (_: rec {
    version = "0.23.11";
    src = pkgs.fetchFromGitHub {
      owner = "tree-sitter";
      repo  = "tree-sitter-php";
      rev   = "v${version}";
      hash  = "sha256-+CnUnrNRaD+CejyYjqelMYA1K3GN/WPeZBJoP2y5cmI=";
    };
  });

  treesitGrammarMap = with pkgs.tree-sitter-grammars; {
    typescript = tree-sitter-typescript;
    tsx        = tree-sitter-tsx;
    javascript = tree-sitter-javascript;
    jsdoc      = tree-sitter-jsdoc;
    json       = tree-sitter-json;
    css        = tree-sitter-css;
    html       = tree-sitter-html;
    yaml       = tree-sitter-yaml;
    bash       = tree-sitter-bash;
    c-sharp    = tree-sitter-c-sharp;
    dockerfile = tree-sitter-dockerfile;
    php        = treesitPhp;
    phpdoc     = tree-sitter-phpdoc;
  };

  treesitGrammars = pkgs.runCommandLocal "treesit-grammars" { } ''
    mkdir -p $out
    ${lib.concatStrings (lib.mapAttrsToList (lang: grammar: ''
      ln -s ${grammar}/parser $out/libtree-sitter-${lang}${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
    '') treesitGrammarMap)}
  '';
in
{
  home.file.".emacs.d/init.el".source = ./init.el;
  home.file.".emacs.d/early-init.el".source = ./early-init.el;
  home.file.".emacs.d/site-lisp/eaw-console.el".source = ../locale-eaw/eaw-console.el;
  home.file.".emacs.d/tree-sitter".source = treesitGrammars;

  # lsp-bridge の Python ランタイム依存を uv で隔離管理する。
  # pyproject.toml は home-manager で配置し、activation で uv sync を走らせて
  # ~/.local/share/lsp-bridge/.venv に Python 環境を構築する。
  # init.el では lsp-bridge-python-command として .venv/bin/python を指す。
  home.file.".local/share/lsp-bridge/pyproject.toml".source = ./lsp-bridge/pyproject.toml;

  home.activation.elpacaLockFile = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${./elpaca.lock} ${config.home.homeDirectory}/.emacs.d/elpaca.lock
  '';

  home.activation.lspBridgeUvSync = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x ${pkgs.uv}/bin/uv ]; then
      cd ${config.home.homeDirectory}/.local/share/lsp-bridge && \
        ${pkgs.uv}/bin/uv sync --quiet || true
    fi
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
