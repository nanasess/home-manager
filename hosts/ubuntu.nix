{ config, pkgs, lib, ghostty, ... }:

let
  # apt で管理するパッケージ一覧
  # dpkg --get-selections | grep -v deinstall で確認
  aptPackages = [
    # TODO: 実環境から精査して追加
  ];
in
{
  home.homeDirectory = "/home/nanasess";

  programs.git.signing.signer = "/opt/1Password/op-ssh-sign";

  programs.ghostty = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.ghostty;
    settings = ghostty.settings;
  };

  home.file.".local/share/applications/com.mitchellh.ghostty.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Name=Ghostty
    Type=Application
    Comment=A terminal emulator
    Exec=${config.home.homeDirectory}/.nix-profile/bin/ghostty --gtk-single-instance=true
    Icon=com.mitchellh.ghostty
    Categories=System;TerminalEmulator;
    Keywords=terminal;tty;pty;
    StartupNotify=true
    StartupWMClass=com.mitchellh.ghostty
    Terminal=false
  '';

  home.file.".local/bin/check-system-packages" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      echo "=== apt パッケージ差分チェック ==="
      missing=0
      for pkg in ${lib.concatStringsSep " " aptPackages}; do
        if ! dpkg -s "$pkg" 2>/dev/null | grep -q 'Status: install ok installed'; then
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

  home.packages = with pkgs; [
    emacs30
    walker
    elephant
    libqalculate
  ];

  home.file.".local/bin/walker-wrapper" = {
    executable = true;
    text = ''
      #!/bin/bash
      export PATH="${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      exec walker "$@"
    '';
  };

  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant data provider service (Walker backend)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.walker = {
    Unit = {
      Description = "Walker application launcher (gapplication service)";
      After = [ "graphical-session.target" "elephant.service" ];
      Requires = [ "elephant.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.configFile."walker/config.toml".source = ./walker/config.toml;

  # Walker v2.x の旧 themes ファイル (v0.x の単一ファイル形式) はスキーマ非互換のため
  # activation 時に削除する。v2.x はサブディレクトリ形式 (themes/<name>/style.css 等) を使用。
  home.activation.cleanupLegacyWalkerThemes = config.lib.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "${config.xdg.configHome}/walker/themes/default.css" \
          "${config.xdg.configHome}/walker/themes/default.toml" \
          "${config.xdg.configHome}/walker/themes/default_window.toml"
  '';

  home.activation.disableGnomeTerminalBell = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    profile_uuid=$(${pkgs.glib}/bin/gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
    if [ -n "$profile_uuid" ]; then
      profile_path="/org/gnome/terminal/legacy/profiles:/:$profile_uuid"
      ${pkgs.dconf}/bin/dconf write "$profile_path/audible-bell" false
    fi
  '';

  dconf.settings = {
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Walker";
      command = "${config.home.homeDirectory}/.local/bin/walker-wrapper";
      binding = "<Control><Shift>semicolon";
    };
  };
}
