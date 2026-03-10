{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/home/nanasess";

  home.packages = with pkgs; [
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
