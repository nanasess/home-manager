{ config, pkgs, lib, ... }:

{
  home.homeDirectory = "/Users/nanasess";

  programs.git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
}
