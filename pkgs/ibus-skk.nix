{ lib
, stdenv
, fetchFromGitHub
, autoreconfHook
, pkg-config
, intltool
, vala
, wrapGAppsHook3
, glib
, gtk3
, ibus
, libskk
, libgee
}:

# ibus-skk を Nix でパッケージ化する。nixpkgs には ibus-skk が無く、apt / Debian も
# 1.4.3 で止まっているため (Debian unstable / Ubuntu 開発版とも 1.4.3-4)、上流の
# 1.4.4 を直接ビルドする。
#
# 1.4.3 には「▼変換中に母音 (1 打鍵で確定するキー) を打つと、確定するはずの変換結果が
# 消えて後続の仮名だけが入力される」バグがある。原因は 1 回の process_key_event 中に
# commit_text が 2 回呼ばれること (src/engine.vala の candidates.selected シグナル内と
# 末尾の 2 箇所) で、クライアントには最後の 1 回しか反映されない。子音+母音のように
# 2 打鍵かかる場合はキーイベントごとに commit_text が 1 回ずつになるため再現しない。
# 1.4.4 の "Don't split sending CommitText when auto-start conversion [#71]" が
# シグナル側の commit_text を削除してこれを修正している。
stdenv.mkDerivation rec {
  pname = "ibus-skk";
  version = "1.4.4";

  src = fetchFromGitHub {
    owner = "ueno";
    repo = "ibus-skk";
    rev = "ibus-skk-${version}";
    hash = "sha256-AQmzUB0e3ZH0hS7wQIaM/nICdx40avYVoJdn3SlD624=";
  };

  # 上流は configure を同梱しない (autogen.sh は gnome-autogen.sh 前提) ため autoreconf する。
  # configure.ac の IT_PROG_INTLTOOL は autoreconf では解決されないので intltoolize を先に走らせる。
  nativeBuildInputs = [
    autoreconfHook
    pkg-config
    intltool
    vala
    wrapGAppsHook3
  ];

  buildInputs = [
    glib
    gtk3
    ibus
    libskk
    libgee
  ];

  preAutoreconf = ''
    intltoolize --force --copy --automake
  '';

  postPatch = ''
    # 上流の既定は <layout>jp</layout> で、SKK を有効にすると JIS 配列が強制される。
    # Ubuntu 側では /usr/share/ibus/component/skk.xml を手で default に書き換えて運用
    # していた (dpkg --verify が改変を検出。2026-03-06) ので、その状態を宣言的に再現する。
    # 元の挙動 (JIS 配列強制) に戻したい場合はこの substituteInPlace を消す。
    substituteInPlace src/skk.xml.in.in \
      --replace-fail '<layout>jp</layout>' '<layout>default</layout>'
  '';

  meta = with lib; {
    description = "SKK engine for IBus (上流 1.4.4。apt / nixpkgs 未提供のため自前ビルド)";
    homepage = "https://github.com/ueno/ibus-skk";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
  };
}
