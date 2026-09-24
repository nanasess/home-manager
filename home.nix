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
    # k1LoW/mo — Markdown をブラウザで開くビューア。バイナリ名は `mo`。
    # nixpkgs の `mo` は別物 (tests-always-included/mo, Bash 用 Moustache) なので混同しないこと。
    mo-viewer
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
    # SQL Server (EcAuth など)。Microsoft 公式の go-sqlcmd で ODBC ドライバ不要
    sqlcmd

    # Development
    gh
    uv
    terraform
    azure-cli
    awscli2
    # MFA 必須 (EnforceMFAPolicy) の IAM ユーザーで STS セッションを作り、環境変数で
    # コンテナ等に渡す (例: `aws-vault exec <profile> -- docker compose up`)。
    # nixpkgs は保守が続く ByteNess 版。長期キーは op-desktop バックエンドで 1Password に置く。
    # AWS_VAULT_BACKEND / AWS_VAULT_OP_VAULT_ID / AWS_VAULT_OP_DESKTOP_ACCOUNT_ID は
    # 公開リポジトリに UUID を置かないため 1Password Environments (.env.local) から供給する。
    # MFA コードは ~/.aws/config の mfa_process で 1Password の TOTP を読む。
    aws-vault
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
    # noto-fonts を入れない。WSL Gentoo はホスト側で追加する。
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
      "credential \"https://github.com\"".helper = "!${config.home.profileDirectory}/bin/gh auth git-credential";
      "credential \"https://gist.github.com\"".helper = "!${config.home.profileDirectory}/bin/gh auth git-credential";
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

  # 区切りは RFC 3676 の "-- " (末尾空白あり)。'' 文字列だと末尾空白が
  # フォーマッタやエディタで消されやすいので通常の文字列で書く。
  home.file.".signature".text = "-- \n大河内健太郎\n";

  home.file.".myclirc".source = ./dotfiles/myclirc;

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  xdg.configFile."phpactor/phpactor.yml".source = ./dotfiles/phpactor.yml;

  # AWS の長期アクセスキーを ~/.aws/credentials に平文で置かず、1Password から供給する。
  # ~/.aws/config のプロファイルに以下を書いて使う (--profile 指定のまま動く):
  #   credential_process = /home/nanasess/.local/bin/aws-credential-op <vault> <item>
  # アイテムは API Credential で "access key id" / "secret access key" フィールドを持つこと。
  # op は PATH から解決する (WSL は ~/.local/bin/op シム → op.exe、k-2 は wrapper)。
  # op run + 環境変数ではなく credential_process にしているのは、--profile を付けると
  # aws CLI が環境変数のクレデンシャルを無視し、プロファイル側の s3 設定
  # (multipart_chunksize 等) と両立しないため。
  home.file.".local/bin/aws-credential-op" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      if [ $# -ne 2 ]; then
        echo "usage: aws-credential-op <vault> <item>" >&2
        exit 2
      fi
      op item get "$2" --vault "$1" --reveal --format json \
        --fields 'label=access key id,label=secret access key' \
        | ${pkgs.jq}/bin/jq -e '
            (map({(.label): .value}) | add) as $f
            | {Version: 1,
               AccessKeyId: $f["access key id"],
               SecretAccessKey: $f["secret access key"]}
            | if .AccessKeyId and .SecretAccessKey then . else error("fields not found") end'
    '';
  };

  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/about" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
      # Slack が実行時に ~/.config/mimeapps.list へ自力で書き込むエントリ。
      # 宣言しておかないと home-manager が同ファイルを管理下に置いた時点で
      # 消え、slack:// リンク (チャンネル招待等) が開かなくなる。
      "x-scheme-handler/slack" = "slack.desktop";
    };
  };

}
