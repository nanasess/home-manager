{ config, ... }:
# ibus-skk の辞書設定 (ホスト非依存)。エンジン本体の登録経路はホストごとに異なる:
#   - Ubuntu: ./ubuntu.nix (Nix ビルドの 1.4.4 を IBUS_COMPONENT_PATH で登録)
#   - NixOS : hosts/k-2/configuration.nix の i18n.inputMethod.ibus.engines
# どちらもエンジン名は skk なので、この dconf パス (desktop/ibus/engine/skk) は共通。
{
  dconf.settings = {
    # yaskkserv2 (skkserv) を辞書サーバとして参照する。
    # encoding=UTF-8 が必須: yaskkserv2 は --midashi-utf8 で UTF-8 通信専用のため。
    # ibus-skk (libskk) の既定は EUC-JP で、省略すると見出し語が化けて変換不能になる
    # (ueno/ibus-skk src/engine.vala が encoding= を Skk.SkkServ へ渡す)。
    # このコメントを消して encoding を外すと ibus-skk の漢字変換が壊れる。
    "desktop/ibus/engine/skk" = {
      dictionaries = [
        "file=${config.home.homeDirectory}/.config/ibus-skk/user.dict,mode=readwrite,type=file"
        "host=127.0.0.1,port=1178,type=server,encoding=UTF-8"
      ];
    };
  };
}
