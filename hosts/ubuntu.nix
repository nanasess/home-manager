{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/home/nanasess";

  home.packages = with pkgs; [
    walker
  ];

  dconf.settings = {
    "org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9" = {
      audible-bell = false;
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Walker";
      command = "${config.home.homeDirectory}/.nix-profile/bin/walker";
      binding = "<Control><Shift>semicolon";
    };
  };
}
