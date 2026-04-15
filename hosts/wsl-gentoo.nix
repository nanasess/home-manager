{ config, pkgs, lib, ... }:

let
  # Gentoo (portage) で管理するパッケージ一覧
  # Issue #48 の「3. Gentoo に残す」参照
  gentooPackages = [
    "app-admin/sudo"
    "app-eselect/eselect-repository"
    "app-portage/gentoolkit"
    "app-portage/mirrorselect"
    "dev-util/pkgdev"
    "dev-util/pkgcheck"
    "www-client/google-chrome"
    "x11-misc/xvfb-run"
    "x11-apps/mesa-progs"
    "x11-apps/xeyes"
    "app-shells/zsh"
    "sys-apps/plocate"

    # mise PHP ビルド依存（asdf-php workflow.yml 参照）
    "dev-db/postgresql"
    "media-libs/gd"
    "net-misc/curl"
    "dev-libs/libedit"
    "dev-libs/icu"
    "media-libs/libjpeg-turbo"
    "dev-libs/oniguruma"
    "media-libs/libpng"
    "sys-libs/readline"
    "dev-db/sqlite"
    "dev-libs/openssl"
    "dev-libs/libxml2"
    "dev-libs/libzip"
    "dev-util/re2c"
    "sys-devel/bison"
    "dev-build/autoconf"
    "sys-libs/zlib"
  ];
in
{
  home.homeDirectory = "/home/nanasess";

  programs.git.signing.signer = "/mnt/c/Users/${config.home.username}/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe";

  home.packages = with pkgs; [
    emacs30-gtk3
  ];

  home.sessionVariables = {
    BROWSER = "wslview";
  };

  # WezTerm 設定を Windows 側にコピー
  home.activation.weztermConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${../modules/wezterm/wezterm.lua} /mnt/c/Users/${config.home.username}/.wezterm.lua
    install -Dm644 ${../modules/locale-eaw/eaw-console-wezterm.lua} /mnt/c/Users/${config.home.username}/.eaw-console-wezterm.lua
  '';

  # UDEV Gothic JPDOC フォントを Windows 側にコピー (WezTerm font_dirs 用)
  home.activation.weztermFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fontdir="/mnt/c/Users/${config.home.username}/.local/share/fonts"
    mkdir -p "$fontdir"
    install -Dm644 ${pkgs.udev-gothic}/share/fonts/udev-gothic/UDEVGothicJPDOC-*.ttf "$fontdir/"
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

  home.file.".local/bin/check-system-packages" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      echo "=== Gentoo パッケージ差分チェック ==="
      missing=0
      for pkg in ${lib.concatStringsSep " " gentooPackages}; do
        if ! equery list "$pkg" &>/dev/null; then
          echo "MISSING: $pkg"
          missing=$((missing + 1))
        fi
      done
      if [ "$missing" -eq 0 ]; then
        echo "OK: すべてのパッケージがインストールされています"
      else
        echo "---"
        echo "$missing 個のパッケージが未インストールです"
        exit 1
      fi
    '';
  };

  home.file.".local/bin/op" = {
    executable = true;
    text = ''
      #!/bin/bash
      OP_EXE="/mnt/c/Users/${config.home.username}/AppData/Local/Microsoft/WinGet/Links/op.exe"
      OP_LINUX="${config.home.homeDirectory}/.nix-profile/bin/op"

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
