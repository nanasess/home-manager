{ config, pkgs, lib, ghostty, ... }:

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
    # Windows 側の op.exe ではなく Linux 側で動かす必要がある
    # `op run` 用 (~/.local/bin/op シム参照)
    _1password-cli
    # ~/.config/zsh/.env.local (FIFO) への secrets 注入用
    # Windows 側 1Password は Linux 側 FIFO に書き込めないため WSLg で Linux 版 GUI を起動する
    _1password-gui
  ];

  home.sessionVariables = {
    BROWSER = "wslview";
  };

  # WezTerm 設定を Windows 側にコピー
  home.activation.weztermConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 ${../modules/wezterm/wezterm.lua} /mnt/c/Users/${config.home.username}/.wezterm.lua
    install -Dm644 ${../modules/locale-eaw/eaw-console-wezterm.lua} /mnt/c/Users/${config.home.username}/.eaw-console-wezterm.lua
  '';

  # UDEV Gothic JPDOC / NF フォントを Windows 側にコピー
  # (WezTerm font_dirs / Ghostty Windows font directory scan の両方から参照される)
  home.activation.weztermFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fontdir="/mnt/c/Users/${config.home.username}/.local/share/fonts"
    mkdir -p "$fontdir"
    install -m644 ${pkgs.udev-gothic}/share/fonts/udev-gothic/UDEVGothicJPDOC-*.ttf "$fontdir/"
    install -m644 ${pkgs.udev-gothic-nf}/share/fonts/udev-gothic-nf/UDEVGothicNF-*.ttf "$fontdir/"
  '';

  # Ghostty Windows port (PR #12167) 向け設定を %LOCALAPPDATA%\ghostty\ にコピー
  # Windows 版は LOCALAPPDATA 配下の config.ghostty を読む
  # また Windows 版には themes/ が同梱されていないため、Nix パッケージ付属の
  # themes/ を %LOCALAPPDATA%\ghostty\themes\ に同期する (テーマ指定が効かない問題の対処)
  home.activation.ghosttyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ghostty_dir="/mnt/c/Users/${config.home.username}/AppData/Local/ghostty"
    install -Dm644 ${ghostty.configFile} "$ghostty_dir/config.ghostty"
    mkdir -p "$ghostty_dir/themes"
    ${pkgs.rsync}/bin/rsync -rt --delete \
      ${pkgs.ghostty}/share/ghostty/themes/ "$ghostty_dir/themes/"
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

  # Ghostty Windows port は C:\Windows\Fonts のみをスキャンするため
  # (src/font/SharedGridSet.zig の findWindowsFont 参照)、
  # ユーザーフォント (~/.local/share/fonts) からシステムフォントに
  # ワンショットでコピーするヘルパー (UAC 昇格が発生する)
  #
  # PowerShell スクリプトは UTF-16LE + base64 化して -EncodedCommand で
  # 直接引数として渡す。中間 .ps1 ファイルを作らないので、ユーザー書込可能な
  # 場所のファイルを昇格実行する際の TOCTOU リスクを回避できる
  home.file.".local/bin/install-ghostty-windows-fonts" = {
    executable = true;
    text = ''
      #!/bin/bash
      set -e
      user='${config.home.username}'
      src_dir="/mnt/c/Users/$user/.local/share/fonts"
      PSH='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

      if [ ! -x "$PSH" ]; then
        echo "ERROR: $PSH が見つかりません" >&2
        exit 1
      fi

      if ! ls "$src_dir"/UDEVGothic*.ttf >/dev/null 2>&1; then
        echo "ERROR: $src_dir に UDEVGothic*.ttf が見つかりません" >&2
        echo "まず 'home-manager switch --flake \".#nanasess@wsl-gentoo\"' を実行してください" >&2
        exit 1
      fi

      read -r -d "" ps_script <<'EOF' || true
      $ErrorActionPreference = 'Stop'
      $src = Join-Path $env:USERPROFILE '.local\share\fonts'
      $dst = Join-Path $env:WINDIR 'Fonts'
      $files = Get-ChildItem -Path $src -Filter 'UDEVGothic*.ttf'
      if ($files.Count -eq 0) {
          Write-Host "ERROR: UDEVGothic*.ttf not found in $src"
          Read-Host 'Press Enter to close'
          exit 1
      }
      foreach ($f in $files) {
          Copy-Item -Path $f.FullName -Destination $dst -Force
          Write-Host "Copied: $($f.Name)"
      }
      Write-Host ""
      Write-Host "Done. Copied $($files.Count) file(s) to $dst"
      Start-Sleep -Seconds 2
      EOF

      # PowerShell -EncodedCommand は UTF-16LE base64 を要求する
      encoded=$(printf '%s' "$ps_script" | iconv -t UTF-16LE | base64 -w 0)

      echo "UAC 昇格プロンプトが出ます。[はい] で許可してください。"
      "$PSH" -NoProfile -Command \
        "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-EncodedCommand','$encoded'"

      echo ""
      echo "--- コピー結果の確認 ---"
      ls /mnt/c/Windows/Fonts/UDEVGothic*.ttf 2>/dev/null || echo "(まだ見つかりません — UAC を拒否したか、別の理由で失敗しています)"
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
