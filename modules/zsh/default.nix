{ config, pkgs, lib, ... }:

let
  # Ghostty の zsh shell integration から「複数行 PS1 への OSC 133 継続マーク挿入」を
  # 取り除いたコピー。
  #
  # 上流の _ghostty_precmd は PS1 に改行があると
  #   mark2=$'%{\e]133;A;k=s\a%}'
  #   PS1=${PS1//$'\n'/$'\n'${mark2}}
  # で改行の直後にマークを差し込む。これは「PS1 の改行が素のリテラルである」前提の
  # 実装で、powerlevel10k では成立しない。p10k の PS1 は 2 行目へ移る改行を
  # パラメータ展開の内側に持つ (${${_p9k__g+\n}:-\n} の形) ため、差し込まれた mark2 の
  # `%}` の `}` が展開の閉じ括弧として先に食われ、余った `}` がプロンプトへリテラル
  # 出力される。最小再現 (zsh -f):
  #   setopt prompt_subst
  #   P=$'${${g+\n}:-\n}END'
  #   P=${P//$'\n'/$'\n'$'%{\e]133;A;k=s\a%}'}
  #   print -r -- "${(V)${(e)P}}"   # → \n%{<OSC>%:-\n%{<OSC>%}}END  ← `}` が残る
  # 実機では新規タブの 1 個目のプロンプト行頭に `}}` が出る。2 回目以降は p10k が PS1 を
  # 作り直して ps1_changed=1 になり、上流自身が挿入をスキップするため出ない
  # (= 「新規タブのときだけ出る」ように見える)。
  #
  # ps1_changed の初期値を 1 にすると、その「テーマが PS1 を作り直した」経路を常に通る。
  # ps1_changed はこの分岐からしか読まれないので他への副作用は無い。PS1 先頭の mark1
  # (133;A;cl=line) と markB、preexec の 133;C、precmd の 133;D、PS2 側のマークはそのまま
  # 残るので、jump_to_prompt / コマンド出力の選択 / プロンプト上での終了確認スキップは
  # 効く。失うのは「リサイズ時に複数行プロンプトの継続行を再描画する」ヒントだけ。
  #
  # --replace-fail なので、上流がこの行を変えたらビルドが落ちて気づける。
  ghosttyZshIntegration =
    pkgs.runCommand "ghostty-integration-no-ps1-newline-mark" { } ''
      substitute \
        ${pkgs.ghostty}/share/ghostty/shell-integration/zsh/ghostty-integration \
        $out \
        --replace-fail 'builtin local ps1_changed=0' 'builtin local ps1_changed=1'
    '';
in
{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    envExtra = ''
      export CLAUDE_CONFIG_DIR=$HOME/.config/claude

      # 1Password Environments から秘匿情報を読み込む（タイムアウト付き）
      #
      # 対話シェル限定にする理由: .zshenv は zsh の全起動 (非対話の `zsh -c`,
      # scp/rsync/git-over-ssh, WSL の `wsl.exe -- <cmd>` 経由のプローブ等) で
      # source される。ここで FIFO を読む・stderr に警告を出すと、コマンド出力を
      # 捕捉するツールを壊す。実害例: ghostinthewsl の `wslinfo --vm-id` 出力に
      # 警告が混入し VM-ID パース失敗 → vsock ConnectFailed (Windows 起動直後、
      # 1Password GUI 未起動時)。非対話シェルで秘匿情報が必要なら op run/op read を
      # 明示的に使う (プロジェクト方針)。
      if [[ -o interactive ]]; then
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
      autoload -U compinit
      compinit

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
        if [[ -z "''${TERM}" ]]; then
          TERM=xterm-256color
        fi

        # COLORTERM
        # Ghostty / WezTerm はネイティブに COLORTERM=truecolor をセットするが、
        # WSL (wsl.exe 経由) で伝播が落ちるため未設定時のみ補完する。
        # Claude Code の light テーマ等、24bit RGB を使う TUI の量子化を防ぐ。
        if [[ -z "''${COLORTERM}" ]]; then
          export COLORTERM=truecolor
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

        # git-worktree-manager シェル統合 (switch/create/checkout 後の自動 cd)
        # https://github.com/nanasess/git-worktree-manager/pull/24
        if command -v worktree > /dev/null; then
          eval "$(worktree shell-init)"

          # タブ補完 (サブコマンド / タスク名)。compinit 後に eval する必要がある。
          # https://github.com/nanasess/git-worktree-manager/pull/32
          #
          # 成功時のみ eval する理由: completion 未対応バージョンでは
          # "Unknown command" とヘルプ全文が *stdout* に出るため、
          # eval "$(...)" 形式だと起動のたびにそれを実行しようとしてエラーが出る。
          if _wt_completion=$(worktree completion zsh 2>/dev/null); then
            eval "$_wt_completion"
          fi
          unset _wt_completion
        fi

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

        # Ghostty shell integration (OSC 133 / OSC 7)
        #
        # noctty / GhostInTheWSL / Ghostty Windows port はいずれも Windows 側の
        # プロセスとして動くため、Ghostty が自動注入に使う GHOSTTY_RESOURCES_DIR と
        # GHOSTTY_SHELL_FEATURES が WSL 側のシェルに届かない (ConPTY 経由では TERM
        # すら自動では渡らない。TERM だけは modules/ghostty の env = WSLENV=TERM で
        # 明示的に伝播させており、この判定条件が成立するのはそのため)。noctty 自身も
        # src/config/windows_shell.zig の shellIntegrationDiagnostic で
        # 「WSL は Linux シェル側で有効化せよ」と案内しているので手動でロードする。
        #
        # feature フラグ非依存で得られるもの:
        # - OSC 133 (semantic prompt) — Ctrl+Shift+PageUp/Down の jump_to_prompt,
        #   Ctrl+三連クリックでのコマンド出力選択, プロンプト上での終了確認スキップ,
        #   リサイズ時に reflow ではなく redraw
        # - OSC 7 (cwd 報告)
        #
        # title feature は有効にしない。上の chpwd フックが送る "%m:%2~" 形式を
        # noctty のタブラベル (compactHostLabel) が前提にしているのに対し、
        # ghostty の title feature は "…/%3~" 形式でホスト名を落とすため競合する。
        #
        # Linux ネイティブの ghostty も同じスクリプトを手動ロードする。あちらは ZDOTDIR
        # 差し替えによる自動注入を持つが、注入されるのは Nix ストアの素のスクリプトで、
        # p10k と組み合わせるとプロンプトに `}` が漏れる (let の ghosttyZshIntegration の
        # コメント参照)。自動注入を hosts/ubuntu.nix の shell-integration = none で止め、
        # 全ホストでパッチ済みスクリプトに一本化している。
        if [[ "$TERM" == xterm-ghostty ]]; then
          export GHOSTTY_SHELL_FEATURES="''${GHOSTTY_SHELL_FEATURES:-cursor}"
          source ${ghosttyZshIntegration}
        fi
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
