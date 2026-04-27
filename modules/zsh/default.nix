{ config, pkgs, lib, ... }:

{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    envExtra = ''
      export CLAUDE_CONFIG_DIR=$HOME/.config/claude

      # 1Password Environments から秘匿情報を読み込む（タイムアウト付き）
      if [[ -p "$ZDOTDIR/.env.local" ]]; then
        _OP_ENV_CONTENT=$(timeout 1 cat "$ZDOTDIR/.env.local" 2>/dev/null)
        if [[ -n "$_OP_ENV_CONTENT" ]]; then
          set -a
          source <(printf '%s\n' "$_OP_ENV_CONTENT")
          set +a
        else
          echo "\e[33m[WARNING] Could not load secrets: 1Password is not running.\e[0m" >&2
          echo "\e[33m          Please start 1Password and open a new shell.\e[0m" >&2
        fi
        unset _OP_ENV_CONTENT
      elif [[ -f "$ZDOTDIR/.env.local" ]]; then
        set -a
        source "$ZDOTDIR/.env.local"
        set +a
      fi

      # WakaTime API キーを tmpfs にキャッシュ
      # (wakatime-cli の api_key_vault_cmd は 2 秒タイムアウトハードコードなので
      #  op read を直接呼ぶと WSL では起動コストで失敗する。
      #  ここで一度 env var をキャッシュし、cfg 側は cat するだけにする)
      if [[ -n "$WAKATIME_API_KEY" ]]; then
        umask 077
        printf '%s' "$WAKATIME_API_KEY" > "/run/user/$(id -u)/wakatime-api-key"
      fi

      export ENHANCD_HYPHEN_NUM=50
    '';

    history = {
      size = 10000;
      save = 10000000;
      path = "$HOME/.config/zsh/.zsh-history";
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
      share = true;
    };

    shellAliases = {
      ls = "eza --color=always --all";
      less = "less -X";
      grep = "LANG=C grep";
    };

    completionInit = ''
      autoload -U compinit promptinit
      compinit
      promptinit; prompt gentoo

      eval "$(op completion zsh)"; compdef _op op

      autoload -U +X bashcompinit && bashcompinit
      complete -o nospace -C /usr/bin/terraform terraform

      if [ -f "$HOME/.config/azure-cli-env/az.completion" ]; then
        source "$HOME/.config/azure-cli-env/az.completion"
      fi

      zstyle ':completion:*:default' menu select=1
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
    '';

    initContent = lib.mkMerge [
      # Before compinit (order 550)
      (lib.mkOrder 550 ''
        # Powerlevel10k instant prompt
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')

      # After compinit (default order 1000)
      ''
        # Emacs keybinding
        bindkey -e
        bindkey "^[[H" beginning-of-line
        bindkey "^[[F" end-of-line

        # colors
        autoload -U colors
        colors

        # zsh options
        setopt auto_list auto_pushd pushd_ignore_dups extended_glob
        setopt hist_expand printeightbit correct

        cdpath=($HOME)

        # TERM
        if [ ! -n "''${TERM}" ]; then
          TERM=xterm-256color
        fi

        # GPG
        if [ -t 0 ]; then
          export GPG_TTY=$(tty)
        fi

        # EDITOR
        if which emacsclient > /dev/null; then
          export EDITOR=emacsclient
        fi

        # PATH
        export PATH=$HOME/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH
        export PATH=$HOME/.composer/vendor/bin:~/.npm-global/bin:$PATH
        export PATH=$HOME/.rbenv/bin:$PATH
        export PATH=$HOME/.symfony/bin:$HOME/.symfony5/bin:$PATH
        export PATH=$HOME/google-cloud-sdk/bin:$PATH

        # bun
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

        # pnpm
        export PNPM_HOME="$HOME/.local/share/pnpm"
        case ":$PATH:" in
          *":$PNPM_HOME:"*) ;;
          *) export PATH="$PNPM_HOME:$PATH" ;;
        esac

        # rbenv
        if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi

        # misc
        export BAT_THEME=ansi-light
        export WEBKIT_FORCE_SANDBOX=0
        export UID=''${UID} GID=''${GID}
        export ASPNETCORE_ENVIRONMENT=Development

        # terminal title on chpwd
        autoload -U add-zsh-hook
        add-zsh-hook -Uz chpwd (){ print -Pn "\e]2;%m:%2~\a" }

        # Emacs integration functions
        function dired () {
          emacsclient -e "(dired \"''${1:a}\")"
        }

        function cde () {
          EMACS_CWD=$(emacsclient -e "
           (expand-file-name
            (with-current-buffer
                (window-buffer (frame-selected-window))
              default-directory))" | sed 's/^"\(.*\)"$/\1/')
          echo "chdir to $EMACS_CWD"
          cd "$EMACS_CWD"
        }

        # Powerlevel10k theme
        [[ ! -f ${./.p10k.zsh} ]] || source ${./.p10k.zsh}
      ''
    ];

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh/themes/powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh";
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
      {
        name = "zsh-z";
        src = pkgs.zsh-z;
        file = "share/zsh-z/zsh-z.plugin.zsh";
      }
      {
        name = "enhancd";
        src = pkgs.fetchFromGitHub {
          owner = "b4b4r07";
          repo = "enhancd";
          rev = "v2.5.1";
          hash = "sha256-kaintLXSfLH7zdLtcoZfVNobCJCap0S/Ldq85wd3krI=";
        };
        file = "init.sh";
      }
      {
        name = "base16-shell";
        src = pkgs.fetchFromGitHub {
          owner = "chriskempson";
          repo = "base16-shell";
          rev = "588691ba71b47e75793ed9edfcfaa058326a6f41";
          hash = "sha256-X89FsG9QICDw3jZvOCB/KsPBVOLUeE7xN3VCtf0DD3E=";
        };
      }
    ];
  };
}
