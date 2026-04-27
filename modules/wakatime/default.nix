{ config, pkgs, ... }:

{
  home.packages = [ pkgs.wakatime-cli ];

  # ~/.wakatime.cfg は API キー本体を保存しない。
  #
  # wakatime-cli (>= 2.x) の api_key_vault_cmd は docs 通り space-split で
  # exec され、`sh -c` 経由ではないためシェル展開 (`$(id -u)`, `$XDG_RUNTIME_DIR`) は
  # 効かない。そのためラッパースクリプトに展開を委ねる。
  #
  # 値の供給チェーン:
  #   1Password Environments の "dotfiles" Environment
  #     → $WAKATIME_API_KEY env var (Zsh 起動時に source)
  #     → /run/user/$UID/wakatime-api-key (Zsh 起動時に書き出し / tmpfs / 0600)
  #     → 本ラッパー が cat
  #     → wakatime-cli が API キーとして使用
  home.file.".local/bin/wakatime-vault-read" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      cache="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wakatime-api-key"
      if [ -r "$cache" ]; then
        cat "$cache"
      else
        echo "[wakatime-vault-read] $cache が存在しません。新しい Zsh セッションを開いてください。" >&2
        exit 1
      fi
    '';
  };

  home.file.".wakatime.cfg".text = ''
    [settings]
    api_key_vault_cmd = ${config.home.homeDirectory}/.local/bin/wakatime-vault-read
  '';
}
