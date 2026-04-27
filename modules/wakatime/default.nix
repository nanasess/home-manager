{ config, lib, pkgs, ... }:

let
  # WakaTime API キーキャッシュの保存先を解決するシェル断片。
  # 書き込み側 (Zsh envExtra) と読み込み側 (ラッパー) の両方で使い、
  # パスの導出ロジックを完全に一致させる。
  #
  # 優先順:
  #   1. $XDG_RUNTIME_DIR (Linux systemd-logind / Wayland 環境で設定済み)
  #   2. /run/user/$UID (Linux 標準の per-user tmpfs。Gentoo / Ubuntu)
  #   3. $TMPDIR (macOS の /var/folders/.../T/ 等。user-private、再起動で消去)
  #
  # 結果は変数 _wakatime_cache に格納される。
  resolveCachePath = ''
    if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
      _wakatime_cache="$XDG_RUNTIME_DIR/wakatime-api-key"
    elif [ -d "/run/user/$(id -u)" ]; then
      _wakatime_cache="/run/user/$(id -u)/wakatime-api-key"
    else
      _wakatime_cache="''${TMPDIR:-/tmp}/wakatime-api-key.$(id -u)"
    fi
  '';
in
{
  home.packages = [ pkgs.wakatime-cli ];

  # Zsh 起動時に $WAKATIME_API_KEY をキャッシュへ書き出す。
  # umask 077 はサブシェルで囲んでセッション全体への副作用を防ぐ。
  # mkAfter で modules/zsh/default.nix の .env.local 読み込み後に実行されるよう順序付け。
  programs.zsh.envExtra = lib.mkAfter ''
    if [[ -n "$WAKATIME_API_KEY" ]]; then
      ${resolveCachePath}
      (umask 077; printf '%s' "$WAKATIME_API_KEY" > "$_wakatime_cache")
      unset _wakatime_cache
    fi
  '';

  # ~/.wakatime.cfg は API キー本体を保存しない。
  #
  # wakatime-cli (>= 2.x) の api_key_vault_cmd は docs 通り space-split で
  # exec され、`sh -c` 経由ではないためシェル展開 (`$(id -u)`, `$XDG_RUNTIME_DIR`) は
  # 効かない。そのためラッパースクリプトに展開を委ねる。
  #
  # 値の供給チェーン:
  #   1Password Environments の "dotfiles" Environment
  #     → $WAKATIME_API_KEY env var (Zsh 起動時に source)
  #     → 上記 envExtra で resolveCachePath が導出するキャッシュパス (mode 0600)
  #     → 本ラッパー が cat
  #     → wakatime-cli が API キーとして使用
  home.file.".local/bin/wakatime-vault-read" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      ${resolveCachePath}
      if [ -r "$_wakatime_cache" ]; then
        cat "$_wakatime_cache"
      else
        echo "[wakatime-vault-read] $_wakatime_cache が存在しません。新しい Zsh セッションを開いてください。" >&2
        exit 1
      fi
    '';
  };

  home.file.".wakatime.cfg".text = ''
    [settings]
    api_key_vault_cmd = ${config.home.homeDirectory}/.local/bin/wakatime-vault-read
  '';
}
