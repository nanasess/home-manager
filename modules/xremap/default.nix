{ config, pkgs, ... }:
let
  # nixpkgs の既定 (pkgs.xremap) は wlroots build。GNOME Wayland ではアプリ判定に
  # gnome feature (GNOME Shell 拡張との D-Bus 連携) が必要なため variant を差し替える。
  # variant 名は nixpkgs の pkgs/by-name/xr/xremap/package.nix の `variants` に定義がある。
  xremap = pkgs.xremap.override { withVariant = "gnome"; };

  # xremap がフォーカス中アプリの WMClass を取得するための GNOME Shell 拡張。
  # https://extensions.gnome.org/extension/5060/xremap/
  xremapExtension = pkgs.gnomeExtensions.xremap;
  extensionUuid = "xremap@k0kubun.com";

  configPath = "${config.xdg.configHome}/xremap/config.yml";
in
{
  # Chrome のタブ移動を Ctrl+H / Ctrl+L に割り当てる。
  #
  # Chrome 自体にキーバインドの変更機能は無く (chrome://settings にも chrome://flags にも
  # 項目が無い)、タブ移動は Ctrl+PageUp / Ctrl+PageDown 固定。拡張機能で実現する手もあるが、
  # コンテンツスクリプト方式では chrome:// 系ページや新規タブページで効かず、Ctrl+L
  # (アドレスバー) を奪えるかも不確実。そこで evdev/uinput レベルで置換する xremap を使う。
  #
  # xremap はカーネルの入力レイヤでキーを差し替えるため、Chrome に届く時点では
  # Ctrl+PageUp / Ctrl+PageDown になっている。よって chrome:// でもページ読込前でも効く。
  #
  # ■ アプリ判定に GNOME Shell 拡張が必要な理由
  #
  # xremap は「フォーカス中アプリ」を知らないと application.only を判定できない。X11 なら
  # xremap 自身が X から WM_CLASS を読めるが、Wayland ではコンポジタごとの手段が要る。
  # GNOME Wayland には汎用 API が無いため、xremap は Shell 拡張を D-Bus
  # (com.k0kubun.Xremap) 越しに呼ぶ。Chrome 151 は Ubuntu 24.04 でネイティブ Wayland
  # 動作 (xprop / xlsclients に現れない) なので、この経路が必須になる。
  #
  # 拡張の置き場所は ~/.local/share/gnome-shell/extensions/。GNOME セッションの
  # XDG_DATA_DIRS に ~/.nix-profile/share が入らない問題 (CLAUDE.md「Nix GUI アプリの
  # ランチャー登録」) はここにも当てはまるため、xdg.dataFile でリンクする。
  #
  # ■ 前提となる root 権限の設定 (home-manager では宣言できない)
  #
  #   sudo gpasswd -a nanasess input
  #   echo 'KERNEL=="uinput", GROUP="input", TAG+="uaccess", MODE:="0660", OPTIONS+="static_node=uinput"' \
  #     | sudo tee /etc/udev/rules.d/99-input.rules
  #   echo uinput | sudo tee /etc/modules-load.d/uinput.conf
  #   sudo udevadm control --reload-rules && sudo udevadm trigger
  #   sudo modprobe uinput
  #
  # 最後の modprobe を省かないこと。modules-load.d は systemd-modules-load.service が
  # 早期ブートで処理する仕組みなので、ファイルを置いた時点ではロードされない。
  # (この T2 Mac のカーネルでは uinput が組み込みで /dev/uinput が静的ノードとして
  # 既に存在するため実質 no-op だが、他機での再現手順として必要。)
  #
  # 反映には再ログインが必要 (input グループの反映 + Wayland では GNOME Shell を
  # 再起動できないため拡張のロードにログインし直しが要る)。
  #
  # ■ セキュリティ上のトレードオフ
  #
  # input グループ加入は、このユーザーアカウントに全アプリのキー入力を読む権限を与える
  # (xremap の doc/running_without_sudo.md も明記)。画面ロック中もリマップは有効。
  # 承知のうえで採用している。

  home.packages = [ xremap ];

  xdg.configFile."xremap/config.yml".text = ''
    # ■ Caps Lock を Ctrl として扱う必要がある理由
    #
    # GNOME 側で xkb-options = ['ctrl:nocaps', 'altwin:swap_lalt_lwin'] を設定しており、
    # 普段 Ctrl として押しているのは物理的には Caps Lock キー。ctrl:nocaps の変換は
    # XKB レイヤ (evdev より上) で行われるため、evdev を直接読む xremap には
    # KEY_CAPSLOCK としか見えず、下の keymap の C-h / C-l にマッチしない
    # (実測: xremap のデバッグログに KEY_LEFTCTRL は 1 度も現れず KEY_CAPSLOCK のみ)。
    #
    # そこで modmap で capslock → leftctrl に変換する。README のとおり
    # 「modmap の出力は keymap を通る」ので、この順で C-h が成立する。
    # application で Chrome に限定してあるため、他アプリのキー入力経路は一切変わらない。
    # 万一アプリ判定が失敗しても capslock がそのまま流れて XKB が Ctrl にするだけなので、
    # 縮退動作は「今までどおり」になる。
    modmap:
      - name: CapsLock as Ctrl (Chrome only)
        application:
          only: [google-chrome]
        remap:
          capslock: leftctrl

    # keymap は「修飾キー付きの組み合わせ」を置換する (単キーの入れ替えは modmap)。
    # 物理 Ctrl キーを使った場合もこの keymap にマッチする。
    keymap:
      # exact_match は既定の false のままにしてある (意図的)。
      #
      # false だと Ctrl+Shift+H のように修飾キーが増えた組み合わせにもマッチするが、
      # 余った修飾キーは解放されず保持される実装なので (event_handler.rs の
      # `extra_modifiers.retain(|key| ... && !extra_modifiers_pressed.contains(key))`)、
      # 出力は Ctrl+Shift+PageUp = Chrome のタブ並び替えになる。H / L のニーモニックと
      # 整合する有用な副産物であり、これで潰れる Chrome 標準ショートカットも無い。
      #
      # exact_match: true を足すとこの動作が消えるだけなので、レビューで指摘されても
      # 「バグではなく意図」であることを確認してから判断すること。
      - name: Chrome tab switching
        application:
          # WMClass 完全一致。実測値は次のコマンドで確認できる:
          #   busctl --user call org.gnome.Shell /com/k0kubun/Xremap com.k0kubun.Xremap WMClasses
          # (GNOME Wayland では xremap --list-windows は使えない)
          only: [google-chrome]
        remap:
          # キー名は xremap の parse_key() が大文字化して KEY_ を補うため、
          # pageup / pagedown が KEY_PAGEUP / KEY_PAGEDOWN に解決される。
          C-h: C-pageup
          C-l: C-pagedown

          # Ctrl+L をタブ移動に取られた分、アドレスバーを Command (⌘) + L に逃がす。
          # MacBook の ⌘ は evdev では KEY_LEFTMETA (実測: ⌘+Tab のログが
          # KEY_LEFTMETA + KEY_TAB。KEY_LEFTALT は一度も出ない)。xremap では
          # Super-/Win- が KEY_LEFTMETA / KEY_RIGHTMETA に対応する。
          #
          # なお xkb-options の altwin:swap_lalt_lwin により、XKB レイヤでは ⌘ が Alt に
          # なっている。ただし xremap は XKB より下の evdev を見るので影響を受けず、
          # ここで ⌘+L を消費するため Chrome には Alt+L も届かない。
          Super-l: C-l
  '';

  # GNOME Shell の拡張探索パスへ配置する (上記コメント参照)。
  xdg.dataFile."gnome-shell/extensions/${extensionUuid}".source =
    "${xremapExtension}/share/gnome-shell/extensions/${extensionUuid}";

  dconf.settings = {
    "org/gnome/shell" = {
      # このキーは配列まるごと置換なので、Ubuntu 既定の拡張も明示的に併記する。
      # 抜かすと ding (デスクトップアイコン) / dock / tiling-assistant が無効になる。
      enabled-extensions = [
        "ding@rastersoft.com"
        "ubuntu-dock@ubuntu.com"
        "tiling-assistant@ubuntu.com"
        extensionUuid
      ];
    };
  };

  systemd.user.services.xremap = {
    Unit = {
      Description = "xremap - key remapper (Chrome tab switching)";
      Documentation = [ "https://github.com/xremap/xremap" ];
      # GNOME Shell 拡張の D-Bus に依存するのでセッション確立後に起動する。
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # --watch=config,device の両方が要る。
      #   device — 後から接続したキーボード (Bluetooth 等) も自動で対象にする
      #   config — config.yml の変更を検知して設定を再読み込みする
      #
      # 裸の --watch は device のみ (xremap の CLI 定義が default_missing_value = "device")。
      # ExecStart が参照するのは安定パス ~/.config/xremap/config.yml なので、設定内容が
      # 変わってもユニットファイルは変化せず home-manager はサービスを再起動しない。
      # config を external すると `home-manager switch` だけでは反映されず、毎回
      # `systemctl --user restart xremap.service` が要る状態になる (実際にそうなった)。
      #
      # home-manager のシンボリックリンク差し替えでも検知できる。ConfigWatcher は
      # 親ディレクトリを IN_CREATE | IN_MOVED_TO で監視し、ファイル名を照合して watch を
      # 張り直す実装 (src/platform_linux/config_watcher.rs)。
      ExecStart = "${xremap}/bin/xremap --watch=config,device ${configPath}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    # default.target ではなく graphical-session.target。GNOME Shell が無い状態で
    # 起動しても WMClass を取得できず、application.only が永久にマッチしない。
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
