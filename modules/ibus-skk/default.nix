{ config, pkgs, ... }:
let
  # nixpkgs / apt には 1.4.4 が無いため上流をローカルでビルドする (pkgs/ibus-skk.nix)。
  ibus-skk = pkgs.callPackage ../../pkgs/ibus-skk.nix { };

  # IBus のエンジン登録先。実体は ~/.local/share/ibus/component。
  componentDir = "${config.xdg.dataHome}/ibus/component";

  # IBus 本体がハードコードで見るディレクトリ。IBUS_COMPONENT_PATH を設定すると
  # ここが探索対象から外れるため、明示的に併記して mozc など他エンジンを保つ。
  systemComponentDir = "/usr/share/ibus/component";
in
{
  # Ubuntu 24.04 の ibus-skk 1.4.3 を Nix ビルドの 1.4.4 に置き換える
  # (バグの詳細は pkgs/ibus-skk.nix のコメント参照)。
  #
  # ここで問題になるのが「エンジンの登録経路」。IBus のコンポーネント探索は
  # XDG_DATA_DIRS を一切見ず、ibus_registry_load() が
  #
  #   IBUS_COMPONENT_PATH が設定されていれば → そのパスのみ
  #   未設定なら                             → /usr/share/ibus/component のみ
  #
  # という実装になっている (g_get_user_data_dir() は FIXME でコメントアウト)。
  # そのため Ghostty / pavucontrol で使っている「XDG_DATA_HOME に置く」回避策
  # (docs/nix-desktop-integration.md) は IBus には効かない。
  #
  # 一方 ibus-daemon は GNOME では systemd ユーザーサービス
  # (org.freedesktop.IBus.session.GNOME.service) として起動するため、
  # ~/.config/environment.d/ 経由の環境変数が届く。よって
  # systemd.user.sessionVariables で IBUS_COMPONENT_PATH を注入する。
  #
  # 前提: apt の ibus-skk は削除しておくこと。component 名 (org.freedesktop.IBus.SKK) と
  # エンジン名 (skk) が同一なので、両方が探索対象にあると二重登録になる。
  # hosts/ubuntu.nix の check-system-packages が競合として検出する。
  #
  # 反映手順 (home-manager switch 後): 再ログインが確実。現在のセッションを維持する場合は
  #   systemctl --user daemon-reload   # environment.d を読み直す
  #   systemctl --user restart org.freedesktop.IBus.session.GNOME.service
  #
  # systemctl --user import-environment IBUS_COMPONENT_PATH は使えない。この変数は
  # environment.d にしか書かれずシェルには入らないため、「クライアント側で設定済みの値を
  # 取り込む」import-environment には渡すものが無い。ibus restart も daemon の自己 re-exec
  # なので environ を引き継いでしまう。

  xdg.dataFile."ibus/component/skk.xml".source =
    "${ibus-skk}/share/ibus/component/skk.xml";

  # component XML の <exec> / <icon> は Nix ストアの絶対パスを指すので、
  # パッケージ自体を home.packages に入れる必要はない (bin/ には何も入らない)。
  systemd.user.sessionVariables = {
    IBUS_COMPONENT_PATH = "${componentDir}:${systemComponentDir}";
  };
}
