{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/home/nanasess";

  dconf.settings = {
    "org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9" = {
      audible-bell = false;
    };
  };
}
