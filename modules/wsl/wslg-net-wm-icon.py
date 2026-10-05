"""WSLg のタスクバーで X11 アプリがペンギンになるのを避けるため _NET_WM_ICON を付与する。

WSLg (weston-mirror の rdprail-shell) は X11 ウィンドウのアイコンを
  1. ウィンドウの _NET_WM_ICON
  2. WM_CLASS (2 番目の文字列) と一致するキーの .desktop
の順に探す。.desktop のキーはファイル名の最後の "." より後ろだけなので、
WM_CLASS が "com.onepassword.OnePassword" のように "." を含むアプリはどう名付けても
一致しない。そうしたアプリのウィンドウに、後から _NET_WM_ICON を設定する。
WSLg の XWM は _NET_WM_ICON の PropertyNotify でアイコンを取り直すので、
ウィンドウの表示後に設定しても反映される。

使い方: wslg-net-wm-icon <WM_CLASS>=<png> [...]
(同じ WM_CLASS を複数並べると、存在する最初のファイルを使う)
"""

import os
import select
import subprocess
import sys
from array import array

from Xlib import X, display, error

ICON_SIZE = 64


def load_icon(path):
    # _NET_WM_ICON は [幅, 高さ, ARGB 画素...] の CARDINAL 配列。
    # リトルエンディアンの ARGB は BGRA のバイト列と同じ並びになる。
    raw = subprocess.run(
        [os.environ.get("MAGICK", "magick"), path,
         "-resize", f"{ICON_SIZE}x{ICON_SIZE}", "-background", "none",
         "-gravity", "center", "-extent", f"{ICON_SIZE}x{ICON_SIZE}",
         "-depth", "8", "BGRA:-"],
        check=True, capture_output=True,
    ).stdout
    pixels = array("I")
    pixels.frombytes(raw)
    if sys.byteorder != "little":
        pixels.byteswap()
    return [ICON_SIZE, ICON_SIZE] + pixels.tolist()


def walk(win):
    try:
        children = win.query_tree().children
    except error.XError:
        return
    for child in children:
        yield child
        yield from walk(child)


def scan(d, root, icons, net_wm_icon, cardinal):
    for win in walk(root):
        try:
            wm_class = win.get_wm_class()
            if not wm_class or wm_class[1] not in icons:
                continue
            if win.get_full_property(net_wm_icon, cardinal) is not None:
                continue
            win.change_property(net_wm_icon, cardinal, 32, icons[wm_class[1]])
            print(f"set _NET_WM_ICON: {wm_class[1]} (0x{win.id:x})", flush=True)
        except error.XError:
            # 走査中に閉じられたウィンドウ
            continue
    d.flush()


def main():
    icons = {}
    for arg in sys.argv[1:]:
        wm_class, _, path = arg.partition("=")
        # 同じ WM_CLASS を複数渡したら先に見つかったものを使う (ディストリで置き場所が違う)
        if wm_class in icons:
            continue
        if not os.path.isfile(path):
            print(f"skip {wm_class}: {path} が無い", file=sys.stderr)
            continue
        icons[wm_class] = load_icon(path)
    if not icons:
        print("アイコンが 1 つも読めないので終了する", file=sys.stderr)
        return 0

    d = display.Display()
    root = d.screen().root
    net_wm_icon = d.intern_atom("_NET_WM_ICON")
    cardinal = d.intern_atom("CARDINAL")
    # ウィンドウの生成・マップで起こす。WM_CLASS は生成直後には無いことがあるので
    # イベントが来なくても定期的に走査し直す。
    root.change_attributes(event_mask=X.SubstructureNotifyMask)
    d.flush()

    while True:
        while d.pending_events():
            d.next_event()
        scan(d, root, icons, net_wm_icon, cardinal)
        select.select([d], [], [], 5)


if __name__ == "__main__":
    sys.exit(main())
