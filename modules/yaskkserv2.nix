{ config, pkgs, ... }:
let
  # nixpkgs / apt には無いため上流をローカルでビルドする (pkgs/yaskkserv2.nix)。
  # これにより wsl-gentoo と ubuntu で同一バイナリを共有し、両ホストとも
  # sudo emerge / apt を経ずに yaskkserv2 + yaskkserv2_make_dictionary を得る。
  yaskkserv2 = pkgs.callPackage ../pkgs/yaskkserv2.nix { };
  # 配信辞書はユーザーパスに置く (sudo 不要)。yaskkserv2_make_dictionary で
  # SKK-JISYO.all.utf8 からビルドする (詳細は README.md「SKK 辞書サーバ」節)。
  dictionaryPath = "${config.xdg.dataHome}/yaskkserv2/all";
in
{
  # yaskkserv2 (skkserv) を systemd ユーザーサービスとして宣言管理する。
  # Emacs nskk の辞書本体をこのサーバへ逃がし、nskk が全辞書を起動時にトライ索引
  # (nskk--prolog-trie-indices) へ全件展開して live ヒープが ~650MiB に膨れ、
  # full GC が 20-50 秒かかる問題を解消する (init.el の nskk 設定参照)。
  #
  # systemd ユーザーサービスなので /etc 書き込みも sudo も OpenRC も不要。ユーザー
  # 権限で動き ~/.config / ~/.local/share を直接読む。バイナリは Nix ビルド
  # (pkgs/yaskkserv2.nix) なので wsl-gentoo でも portage は不要。
  #
  # 事前準備 (sudo 不要。詳細は README.md「SKK 辞書サーバ」節):
  #   nix build '.#homeConfigurations."nanasess@<host>".activationPackage'
  #   yaskkserv2_make_dictionary \             # 配信辞書を SKK-JISYO.all.utf8 から
  #     --dictionary-filename ~/.local/share/yaskkserv2/all \   # ビルド (辞書更新時のみ)
  #     --utf8 "$HOME/OneDrive - Skirnir Inc/emacs/ddskk/SKK-JISYO.all.utf8"
  # その後 `home-manager switch` でサービスが起動する。

  # yaskkserv2_make_dictionary を PATH に通し、辞書の (再) ビルドを手元で行えるように。
  home.packages = [ yaskkserv2 ];

  # サーバ設定。--config-filename でこのファイルを直接読ませる (/etc は経由しない)。
  # google 連携を有効化。notfound = ローカル辞書で見つからない語のみ Google 日本語
  # 入力 CGI へ問い合わせる。通信は HTTPS (google-use-http = disable のまま)。
  # 注意: 変換キー (よみ) が Google に送信される。オフライン/プライバシー重視に
  # 戻すなら google-japanese-input = disable / google-suggest = disable に。
  xdg.configFile."yaskkserv2/yaskkserv2.conf".text = ''
    dictionary = ${dictionaryPath}
    port = 1178
    # 127.0.0.1 に限定 (LAN へ露出しない)。WSL2 では localhostForwarding により
    # Windows 側からも localhost:1178 で到達できる。
    listen-address = 127.0.0.1
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
      ExecStart = "${yaskkserv2}/bin/yaskkserv2 --no-daemonize --midashi-utf8 --config-filename ${config.xdg.configHome}/yaskkserv2/yaskkserv2.conf";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
