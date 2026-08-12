{ config, pkgs, lib, ghostty, ... }:

let
  # apt で管理するパッケージ一覧
  # dpkg --get-selections | grep -v deinstall で確認
  aptPackages = [
    # TODO: 実環境から精査して追加
  ];

  # apt で入っていてはいけないパッケージ (Nix 側と衝突するもの)。
  # 未インストールであることを check-system-packages が検証する。
  aptConflictPackages = [
    # ibus-skk: Ubuntu 24.04 の 1.4.3 には ▼変換中に母音を打つと確定文字列が消える
    # バグがあり (詳細は pkgs/ibus-skk.nix)、modules/ibus-skk の Nix ビルド 1.4.4 に
    # 置き換えている。component 名 (org.freedesktop.IBus.SKK) とエンジン名 (skk) が
    # 同一なので、両方が IBUS_COMPONENT_PATH の探索対象にあると二重登録になる。
    #   sudo apt remove ibus-skk
    "ibus-skk"
  ];

  # GNOME セッションの XDG_DATA_DIRS には ~/.nix-profile/share が含まれないため、
  # .desktop の Icon=<name> がテーマ検索で解決できずアイコンが出ない
  # (CLAUDE.md「Nix GUI アプリのランチャー登録」参照)。
  # XDG_DATA_HOME (~/.local/share) 配下は GTK が常に検索するので、アイコンだけ
  # ここへリンクする。Icon= に絶対パスを書く手もあるが解像度が固定になるため、
  # 複数サイズを張って HiDPI でのスケーリングを効かせる。
  #
  # sizes には「パッケージが持っていて、かつ /usr/share/icons/hicolor/index.theme
  # が定義しているサイズ」だけを渡すこと。index.theme に無いディレクトリ
  # (ghostty の 1024x1024 や *@2 など) は張っても GTK に引かれない。
  iconLinks = { package, icon, sizes }: lib.listToAttrs (map
    (size:
      let file = "${icon}.${if size == "scalable" then "svg" else "png"}";
      in lib.nameValuePair
        "icons/hicolor/${size}/apps/${file}"
        { source = "${package}/share/icons/hicolor/${size}/apps/${file}"; })
    sizes);
in
{
  home.homeDirectory = "/home/nanasess";

  programs.git.signing.signer = "/opt/1Password/op-ssh-sign";

  programs.ghostty = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.ghostty;
    settings = ghostty.settings;
  };

  home.file.".local/share/applications/com.mitchellh.ghostty.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Name=Ghostty
    Type=Application
    Comment=A terminal emulator
    Exec=${config.home.homeDirectory}/.nix-profile/bin/ghostty --gtk-single-instance=true
    Icon=com.mitchellh.ghostty
    Categories=System;TerminalEmulator;
    Keywords=terminal;tty;pty;
    StartupNotify=true
    StartupWMClass=com.mitchellh.ghostty
    Terminal=false
  '';

  # ランチャー用アイコンの配置 (詳細は let ブロックの iconLinks を参照)。
  # emacs は modules/emacs の emacs.desktop / emacsclient.desktop (Icon=emacs) 用。
  # apt の emacs-common が /usr/share/icons/hicolor に同名アイコンを置いており
  # 未配置でも表示自体はされるが、それは apt 版に依存した偶然なのでここで
  # nixpkgs 側 (実際に起動する emacs30-pgtk) のアイコンを優先させる。
  xdg.dataFile =
    iconLinks
      {
        package = pkgs.ghostty;
        icon = "com.mitchellh.ghostty";
        sizes = [ "16x16" "32x32" "128x128" "256x256" "512x512" ];
      }
    // iconLinks {
      package = pkgs.emacs30-pgtk;
      icon = "emacs";
      sizes = [ "16x16" "24x24" "32x32" "48x48" "128x128" "scalable" ];
    };

  home.file.".local/bin/check-system-packages" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      echo "=== apt パッケージ差分チェック ==="
      missing=0
      for pkg in ${lib.concatStringsSep " " aptPackages}; do
        if ! dpkg -s "$pkg" 2>/dev/null | grep -q 'Status: install ok installed'; then
          echo "MISSING: $pkg"
          missing=$((missing + 1))
        fi
      done
      echo "=== apt 競合パッケージチェック ==="
      conflict=0
      for pkg in ${lib.concatStringsSep " " aptConflictPackages}; do
        if dpkg -s "$pkg" 2>/dev/null | grep -q 'Status: install ok installed'; then
          echo "CONFLICT: $pkg (Nix 側と衝突するため削除してください: sudo apt remove $pkg)"
          conflict=$((conflict + 1))
        fi
      done

      echo "---"
      if [ "$missing" -eq 0 ] && [ "$conflict" -eq 0 ]; then
        echo "OK: すべてのパッケージがインストールされています"
      else
        [ "$missing" -eq 0 ] || echo "$missing 個のパッケージが未インストールです"
        [ "$conflict" -eq 0 ] || echo "$conflict 個の競合パッケージが残っています"
        exit 1
      fi
    '';
  };

  home.packages = with pkgs; [
    # Wayland セッションでは pgtk ビルドを使う。XWayland (X11) 経由を避けることで
    # GTK の長年のバグ (X11 接続喪失時に daemon ごとクラッシュ / GNOME #85715) を
    # 回避し、HiDPI スケーリングと IME 連携も Wayland ネイティブになる。
    emacs30-pgtk
    walker
    elephant
    libqalculate
    # GNOME のUIフォント設定 (gsettings: Adwaita Sans) の実体。未導入だと
    # pgtk Emacs の GTK メニュー/ツールバー/タイトルバーが豆腐になる。
    adwaita-fonts
  ];

  home.file.".local/bin/walker-wrapper" = {
    executable = true;
    text = ''
      #!/bin/bash
      export PATH="${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      exec walker "$@"
    '';
  };

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
      # systemd ユーザーサービスの PATH には ~/.nix-profile/bin が含まれない
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

  xdg.configFile."walker/config.toml".source = ./walker/config.toml;

  # Walker v2.x の旧 themes ファイル (v0.x の単一ファイル形式) はスキーマ非互換のため
  # activation 時に削除する。v2.x はサブディレクトリ形式 (themes/<name>/style.css 等) を使用。
  home.activation.cleanupLegacyWalkerThemes = config.lib.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "${config.xdg.configHome}/walker/themes/default.css" \
          "${config.xdg.configHome}/walker/themes/default.toml" \
          "${config.xdg.configHome}/walker/themes/default_window.toml"
  '';

  home.activation.disableGnomeTerminalBell = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    profile_uuid=$(${pkgs.glib}/bin/gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
    if [ -n "$profile_uuid" ]; then
      profile_path="/org/gnome/terminal/legacy/profiles:/:$profile_uuid"
      ${pkgs.dconf}/bin/dconf write "$profile_path/audible-bell" false
    fi
  '';

  dconf.settings = {
    # ibus-skk の辞書設定。yaskkserv2 (skkserv) を辞書サーバとして参照する。
    # エンジン本体は modules/ibus-skk (Nix ビルドの 1.4.4) が提供する。エンジン名 skk は
    # apt 版と同一なのでこの dconf パス (desktop/ibus/engine/skk) はそのまま引き継がれる。
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

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Walker";
      command = "${config.home.homeDirectory}/.local/bin/walker-wrapper";
      binding = "<Control><Shift>semicolon";
    };
  };
}
