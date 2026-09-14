{ config, pkgs, ... }:
# Walker (アプリケーションランチャー) + Elephant (データプロバイダ) の共通モジュール。
# GNOME セッションを持つホスト (ubuntu / k-2) で共有する。
let
  # GNOME のカスタムキーバインドから起動するとき、コマンドの環境には Nix プロファイルの
  # bin が無い場合がある (Ubuntu のセッションでは ~/.nix-profile/bin が PATH に入らない)。
  # store パスを直接 exec するので PATH には依存しないが、walker → elephant の
  # `which("elephant")` 解決のため elephant の bin は明示的に足しておく。
  walkerWrapper = pkgs.writeShellScript "walker-wrapper" ''
    export PATH="${pkgs.elephant}/bin:${config.home.profileDirectory}/bin:$PATH"
    exec ${pkgs.walker}/bin/walker "$@"
  '';
in
{
  home.packages = with pkgs; [
    walker
    elephant
    # walker の計算機プロバイダ (qalc)。
    libqalculate
  ];

  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant data provider service (Walker backend)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.walker = {
    Unit = {
      Description = "Walker application launcher (gapplication service)";
      After = [ "graphical-session.target" "elephant.service" ];
      Requires = [ "elephant.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      # walker は起動時に `which("elephant")` で elephant を検出する。
      # systemd ユーザーサービスの PATH には Nix プロファイルの bin が含まれない
      # ため、elephant の bin を明示的に PATH に追加する。
      Environment = [ "PATH=${pkgs.elephant}/bin:/usr/local/bin:/usr/bin:/bin" ];
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.configFile."walker/config.toml".source = ./config.toml;

  # Walker v2.x の旧 themes ファイル (v0.x の単一ファイル形式) はスキーマ非互換のため
  # activation 時に削除する。v2.x はサブディレクトリ形式 (themes/<name>/style.css 等) を使用。
  home.activation.cleanupLegacyWalkerThemes = config.lib.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "${config.xdg.configHome}/walker/themes/default.css" \
          "${config.xdg.configHome}/walker/themes/default.toml" \
          "${config.xdg.configHome}/walker/themes/default_window.toml"
  '';

  dconf.settings = {
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Walker";
      command = "${walkerWrapper}";
      binding = "<Control><Shift>semicolon";
    };
  };
}
