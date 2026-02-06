{ config, pkgs, lib, ... }:

{
  home.username = "nanasess";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Kentaro Ohkouchi";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };
}
