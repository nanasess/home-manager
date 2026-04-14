{ config, pkgs, lib, ... }:

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
    settings = {
      font-family = "Ubuntu Sans Mono";
      font-size = 13;
      keybind = [
        "ctrl+l=next_tab"
        "ctrl+h=previous_tab"
      ];
      theme = "Solarized Dark Patched";
    };
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

  xdg.configFile."walker/config.toml".source = ./walker/config.toml;

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
