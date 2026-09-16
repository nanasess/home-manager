{ config, lib, pkgs, ... }:
# ibus-skk の辞書設定 (ホスト非依存)。エンジン本体の登録経路はホストごとに異なる:
#   - Ubuntu: ./ubuntu.nix (Nix ビルドの 1.4.4 を IBUS_COMPONENT_PATH で登録)
#   - NixOS : hosts/k-2/configuration.nix の i18n.inputMethod.ibus.engines
# どちらもエンジン名は skk なので、この dconf パス (desktop/ibus/engine/skk) は共通。
{
  dconf.settings = {
    # GNOME の入力ソースに ibus-skk を登録する (設定 > キーボード > 入力ソース)。
    # i18n.inputMethod.ibus.engines / IBUS_COMPONENT_PATH でエンジンを入れただけでは
    # GNOME 側の入力ソース一覧には出ず、手動追加が要るので宣言化する。
    # 先頭が既定の入力ソースになる。per-window はウィンドウごとに入力ソースを記憶する。
    "org/gnome/desktop/input-sources" = {
      per-window = true;
      sources = [
        (lib.hm.gvariant.mkTuple [ "ibus" "skk" ])
        (lib.hm.gvariant.mkTuple [ "xkb" "us" ])
      ];
    };
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
      # エンジン起動時の入力モードを latin (半角英数) にする。既定は hiragana。
      # ibus-skk は gschema を持たず IBus.Config 経由で dconf を直接読む。キー名は
      # src/preferences.vala の "initial_input_mode" を ibus の dconf バックエンドが
      # '_' → '-' に変換したもの。値は libskk の Skk.InputMode (int32):
      #   0=hiragana 1=katakana 2=hankaku-katakana 3=latin 4=wide-latin
      initial-input-mode = 3;
    };
  };

  # sudo のパスワードプロンプトの間だけ IBus を US 配列 (直接入力) に切り替える。
  # SKK をかな入力モードにしたまま sudo を打つとパスワードが仮名に化けるため。
  #
  # - `ibus engine xkb:us::eng` は使えない: xkb エンジンへの切替時に setxkbmap を
  #   spawn するので Wayland (setxkbmap 無し) では失敗する。IBus 自身のバスに gdbus で
  #   SetGlobalEngine を投げれば GNOME Shell 配下でも切り替わる (k-2 で確認)。
  # - 復帰時に skk エンジンは作り直されるため、入力モードは initial-input-mode (latin)
  #   に戻る。sudo 前がかなモードでも sudo 後は半角英数になる。
  # - タイムスタンプが有効 (`sudo -n true` 成功) ならプロンプトは出ないので素通し。
  #   IBus が動いていない環境 (wsl-gentoo 等) も素通し。
  # - Ctrl-C でプロンプトを抜けても always 節でエンジンを戻す。
  programs.zsh.initContent = ''
    sudo() {
      local ibus_addr prev
      if command sudo -n true 2>/dev/null \
         || ! ibus_addr=$(ibus address 2>/dev/null) || [[ -z "$ibus_addr" ]]; then
        command sudo "$@"
        return
      fi
      prev=$(ibus engine 2>/dev/null)
      if [[ -z "$prev" || "$prev" == xkb:* ]]; then
        command sudo "$@"
        return
      fi
      _ibus_set_engine "$ibus_addr" xkb:us::eng
      { command sudo "$@" } always { _ibus_set_engine "$ibus_addr" "$prev" }
    }
    _ibus_set_engine() {
      ${pkgs.glib.bin}/bin/gdbus call --address "$1" \
        --dest org.freedesktop.IBus --object-path /org/freedesktop/IBus \
        --method org.freedesktop.IBus.SetGlobalEngine "$2" >/dev/null 2>&1
    }
  '';
}
