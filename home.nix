{ config, pkgs, lib, ... }:

{
  home.username = "nanasess";
  home.stateVersion = "24.05";

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "terraform"
      "1password-cli"
      "1password"
    ];

  programs.home-manager.enable = true;

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    # CLI tools
    ripgrep
    fd
    fzf
    eza
    jq
    tree
    htop
    vim
    ffmpeg
    whois
    pandoc
    lftp
    pigz
    zip
    socat
    stunnel
    sharutils
    dnsutils
    inetutils

    # DB CLI
    postgresql_18
    mariadb.client
    pgcli
    litecli

    # Development
    gh
    uv
    terraform
    azure-cli
    awscli2
    hugo
    apacheHttpd

    # Japanese input
    skktools

    # Fonts
    noto-fonts
    noto-fonts-color-emoji
    udev-gothic-nf
  ]
  ++ lib.optionals stdenv.isLinux [
    wakatime-cli
    _1password-cli
    _1password-gui
    wl-clipboard
    xrandr
    libnotify
    json-glib
    google-cloud-sdk
    mycli
  ]
  ++ lib.optionals stdenv.isDarwin [
    coreutils
  ];

  programs.git = {
    enable = true;
    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0gg8ApM4YFGtY3k6gn/qjvdPE2Vr0MdbSHNa4traq+";
      signByDefault = true;
      format = "ssh";
    };
    lfs.enable = true;
    settings = {
      user = {
        name = "Kentaro Ohkouchi";
        email = "nanasess@fsm.ne.jp";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      commit.verbose = true;
      "credential \"https://github.com\"".helper = "!${config.home.homeDirectory}/.nix-profile/bin/gh auth git-credential";
      "credential \"https://gist.github.com\"".helper = "!${config.home.homeDirectory}/.nix-profile/bin/gh auth git-credential";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
  };

  programs.zoxide = {
    enable = true;
  };

  programs.mise = {
    enable = true;
    globalConfig = {
      tools = {
        node = "lts";
        php = "8.5";
      };
    };
  };

  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    PAGER = "less";
    LESSCHARSET = "utf-8";
    LESS = "-R";
    JQ_COLORS = "1;36:0;33:0;33:0;36:0;32:1;39:1;39";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [
      "~/.ssh/conf.d/*.conf"
    ];
    matchBlocks."*" = {
      extraOptions = {
        "IdentityAgent" = "~/.1password/agent.sock";
      };
    };
  };

  home.file.".signature".text = ''
    Kentaro Ohkouchi
  '';

  home.file.".myclirc".source = ./dotfiles/myclirc;

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  xdg.configFile."phpactor/phpactor.yml".source = ./dotfiles/phpactor.yml;

  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

}
