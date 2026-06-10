{ config, ... }:
{
  # yaskkserv2 (skkserv) を systemd ユーザーサービスとして宣言管理する。
  # Emacs nskk の辞書本体をこのサーバへ逃がし、nskk が全辞書を起動時にトライ索引
  # (nskk--prolog-trie-indices) へ全件展開して live ヒープが ~650MiB に膨れ、
  # full GC が 20-50 秒かかる問題を解消する (init.el の nskk 設定参照)。
  #
  # systemd ユーザーサービスなので /etc 書き込みも sudo も OpenRC も不要。ユーザー
  # 権限で動き ~/.config を直接読める。ebuild 同梱の system unit (User=nobody、
  # /etc/yaskkserv2.conf を読む、--midashi-utf8 無し) は使わない (disabled のまま)。
  #
  # 事前準備 (sudo が要る部分。詳細は README.md「SKK 辞書サーバ」節):
  #   sudo emerge -av app-i18n/yaskkserv2        # バイナリ + SKK-JISYO.L
  #   sudo install -d /usr/lib/yaskkserv2        # 配信辞書を SKK-JISYO.all.utf8 から
  #   sudo yaskkserv2_make_dictionary \          #   ビルド (辞書更新時のみ再実行)
  #     --dictionary-filename /usr/lib/yaskkserv2/all \
  #     --utf8 "$HOME/OneDrive - Skirnir Inc/emacs/ddskk/SKK-JISYO.all.utf8"
  # その後 `home-manager switch` でサービスが起動する。

  # サーバ設定。--config-filename でこのファイルを直接読ませる (/etc は経由しない)。
  # google 連携を有効化。notfound = ローカル辞書で見つからない語のみ Google 日本語
  # 入力 CGI へ問い合わせる。通信は HTTPS (google-use-http = disable のまま)。
  # 注意: 変換キー (よみ) が Google に送信される。オフライン/プライバシー重視に
  # 戻すなら google-japanese-input = disable / google-suggest = disable に。
  xdg.configFile."yaskkserv2/yaskkserv2.conf".text = ''
    dictionary = /usr/lib/yaskkserv2/all
    port = 1178
    listen-address = 0.0.0.0
    max-connections = 16
    google-japanese-input = notfound
    google-suggest = enable
    google-use-http = disable
  '';

  systemd.user.services.yaskkserv2 = {
    Unit = {
      Description = "Yet Another SKK server (yaskkserv2) for Emacs nskk";
      Documentation = [ "https://github.com/wachikun/yaskkserv2" ];
      After = [ "network.target" ];
    };
    Service = {
      # --midashi-utf8: SKK-JISYO.all.utf8 は EUC-JP 不可文字を含むため UTF-8 で
      # 統一し、nskk 側 nskk-server-coding-system 'utf-8 (init.el) と整合させる。
      ExecStart = "/usr/bin/yaskkserv2 --no-daemonize --midashi-utf8 --config-filename ${config.home.homeDirectory}/.config/yaskkserv2/yaskkserv2.conf";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
