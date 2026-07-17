{ config, pkgs, lib, ... }:

{
  home.username = "nanasess";
  home.stateVersion = "24.05";

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "terraform"
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
    poppler-utils
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
    symfony-cli
    apacheHttpd

    # LSP servers (lsp-bridge から利用)
    phpactor
    bash-language-server
    typescript-language-server
    yaml-language-server
    vscode-langservers-extracted
    dockerfile-language-server
    nixd

    # Japanese input
    skktools

    # Fonts
    # noto-fonts (字形本体) はホスト側で管理する。Nix の noto-fonts は可変フォント版
    # (NotoSans[wdth,wght].ttf) で、Linux の Emacs ftcrhb バックエンドが realize できず
    # 各スクリプトが豆腐になるため。Ubuntu は OS の静的 Noto (272本) に委譲し、
    # noto-fonts を入れない。WSL Gentoo / macOS は各ホストで追加する。
    noto-fonts-color-emoji
    udev-gothic
    udev-gothic-nf
    # nerd-icons が参照する "Symbols Nerd Font Mono" を提供する。
    # 未導入だと doom-modeline 等のアイコン (U+F0000 台) が豆腐になる。
    nerd-fonts.symbols-only
  ]
  ++ lib.optionals stdenv.isLinux [
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
    LESSCOLORIZER = "pygmentize -O style=solarized-light";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [
      "~/.ssh/conf.d/*.conf"
    ];
    settings."*" = {
      IdentityAgent = "~/.1password/agent.sock";
      # Ghostty の TERM=xterm-ghostty をそのまま送ると、terminfo エントリを
      # 持たないリモートで zsh/readline の行編集・履歴表示が崩れる。
      # GhostInTheWSL は Windows 側から WSL の PTY に直結するため WSL 側で
      # shell integration が有効にならず、Ghostty 公式の
      # shell-integration-features = ssh-terminfo に頼れない。
      # TERM は SetEnv の例外でリモート sshd の AcceptEnv 不要 (man ssh_config)。
      SetEnv.TERM = "xterm-256color";
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
