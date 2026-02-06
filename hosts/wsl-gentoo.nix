{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/home/nanasess";

  home.sessionVariables = {
    BROWSER = "wslview";
  };
}
