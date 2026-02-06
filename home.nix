{ config, pkgs, lib, ... }:

{
  home.username = "nanasess";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # CLI tools
    ripgrep
    fd
    fzf
    eza
    jq
    tree
    htop
    cmigemo

    # Development
    git-lfs
    gh
    sheldon

    # Fonts
    noto-fonts
    noto-fonts-color-emoji
  ]
  ++ lib.optionals stdenv.isLinux [
    wakatime-cli
  ]
  ++ lib.optionals stdenv.isDarwin [
    coreutils
  ];

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

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    PAGER = "less";
    LESSCHARSET = "utf-8";
    LESS = "-R";
    JQ_COLORS = "1;36:0;33:0;33:0;36:0;32:1;39:1;39";
  };

  home.file.".signature".text = ''
    Kentaro Ohkouchi
  '';
}
