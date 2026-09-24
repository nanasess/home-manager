{ config, pkgs, lib, ghostty, ... }:

# WSL ホスト共通の home-manager 設定 (wsl-gentoo / wsl-nixos、Issue #183)。
# Windows 側へのファイル配置、WSLg 向けの shim、1Password CLI の振り分けなど、
# ディストリに依存しない部分をまとめる。ディストリ固有の設定は hosts/ 側に置く。
{
  # 既定値は置かず各ホストで明示する (ディストリごとに入手経路が違うため)。
  options.wsl.opLinux = lib.mkOption {
    type = lib.types.str;
    example = "/run/wrappers/bin/op";
    description = ''
      setgid onepassword-cli 付きの Linux 版 op のパス。`op run` だけはこちらで実行する
      (~/.local/bin/op シム参照)。/nix/store には setgid を付与できないため、
      ディストリ側が用意したものを指す。
    '';
  };

  config = {
    programs.git.signing.signer = "/mnt/c/Users/${config.home.username}/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe";

    # ~/.gnupg/gpg-agent.conf を宣言する (旧: 手書きで portage の /usr/bin/pinentry-tty を参照)。
    # Mew は --pinentry-mode loopback でパスフレーズを渡すため allow-loopback-pinentry が必要。
    # GPG_TTY は modules/zsh で export 済みなので zsh 連携は重複させない。
    services.gpg-agent = {
      enable = true;
      pinentry.package = pkgs.pinentry-tty;
      enableZshIntegration = false;
      # 既定 (true) だと grab が入る。GUI pinentry 専用で tty では無意味なので旧設定に合わせる
      grabKeyboardAndMouse = false;
      extraConfig = ''
        allow-loopback-pinentry
        allow-emacs-pinentry
      '';
    };

    home.packages = with pkgs; [
      # WSLg では Weston が Wayland コンポジタとして動作し、Wayland ネイティブアプリは
      # XWayland を経由せず Weston に直接接続する。pgtk ビルドにすることで XWayland の
      # レイヤを外し、GTK の X11 接続喪失クラッシュ (GNOME #85715) を原理的に回避する。
      emacs31-pgtk
      # 字形本体の Noto。home.nix 共通から移動 (Ubuntu のみ OS 静的 Noto に委譲する方針)。
      noto-fonts
      # WSL から Windows 既定ブラウザを開く opener (内部で powershell.exe Start を呼ぶ)。
      # BROWSER から参照する。portage の /usr/bin/wsl-open ではなく Nix で宣言して
      # ホスト間の入手経路を揃える (CLAUDE.md「プラットフォーム非依存化の判断基準」)。
      wsl-open
      # WSLg クリップボードの BMP を PNG に変換する wl-paste shim (下記) が使う。
      # portage の /usr/bin/magick に依存させず Nix で入手経路を固定する。
      imagemagick
    ];

    home.sessionVariables = {
      # 従来の wslview (wslu) は upstream が archive され nixpkgs からも削除済みで、
      # 実体が無いまま参照だけが残っていた。BROWSER を argv[0] として spawn する
      # 呼び出し側 (Claude Code の URL オープン等) では ENOENT で無反応になるため
      # wsl-open へ置き換える。
      BROWSER = "wsl-open";
    };

    # UDEV Gothic JPDOC / NF フォントを Windows 側にコピー
    # (install-ghostty-windows-fonts がここから C:\Windows\Fonts へコピーする)
    home.activation.windowsFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      fontdir="/mnt/c/Users/${config.home.username}/.local/share/fonts"
      mkdir -p "$fontdir"
      install -m644 ${pkgs.udev-gothic}/share/fonts/truetype/UDEVGothicJPDOC-*.ttf "$fontdir/"
      install -m644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-*.ttf "$fontdir/"
    '';

    # Ghostty Windows port (PR #12167) 向け設定を %LOCALAPPDATA%\ghostty\ にコピー
    # Windows 版は LOCALAPPDATA 配下の config.ghostty を読む
    # また Windows 版には themes/ が同梱されていないため、Nix パッケージ付属の
    # themes/ を %LOCALAPPDATA%\ghostty\themes\ に同期する (テーマ指定が効かない問題の対処)
    home.activation.ghosttyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ghostty_dir="/mnt/c/Users/${config.home.username}/AppData/Local/ghostty"
      install -Dm644 ${ghostty.configFile} "$ghostty_dir/config.ghostty"
      mkdir -p "$ghostty_dir/themes"
      ${pkgs.rsync}/bin/rsync -rt --delete \
        ${pkgs.ghostty}/share/ghostty/themes/ "$ghostty_dir/themes/"
    '';

    # GhostInTheWSL (Codavo/ghostinthewsl) 向け設定を %LOCALAPPDATA%\ghostinthewsl\ にコピー
    # README は %APPDATA% と記載するが誤り。実装 (src/os/xdg.zig) では XDG ベースで解決し、
    # Windows では $XDG_CONFIG_HOME 未設定時に %LOCALAPPDATA% (AppData\Local) を見る。
    # (Windows port (%LOCALAPPDATA%\ghostty) と同じ env var)
    # 探索順: config.ghostinthewsl (exe隣) → %LOCALAPPDATA%\ghostinthewsl\config (legacy)
    #   → %LOCALAPPDATA%\ghostinthewsl\config.ghostinthewsl。後勝ちで XDG が exe隣を上書きする。
    # themes/ も同梱されない想定のため Nix パッケージ付属の themes/ を同期する。
    home.activation.ghostinthewslConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      gitw_dir="/mnt/c/Users/${config.home.username}/AppData/Local/ghostinthewsl"
      install -Dm644 ${ghostty.ghostinthewslConfigFile} "$gitw_dir/config.ghostinthewsl"
      mkdir -p "$gitw_dir/themes"
      ${pkgs.rsync}/bin/rsync -rt --delete \
        ${pkgs.ghostty}/share/ghostty/themes/ "$gitw_dir/themes/"
    '';

    # noctty (amanthanvi/noctty、旧 winghostty) 向け設定を %LOCALAPPDATA%\noctty\ にコピー
    # 設定探索は src/config/file_load.zig。Windows では XDG ベース解決で
    # $XDG_CONFIG_HOME 未設定時に %LOCALAPPDATA% を見る (src/os/xdg.zig、他 2 つと同じ)。
    # loadDefaultFiles が読むのは %LOCALAPPDATA%\ghostty\config (拡張子なし・legacy) と
    # %LOCALAPPDATA%\noctty\config.ghostty の 2 つだけ。Ghostty Windows port 用に置いている
    # %LOCALAPPDATA%\ghostty\config.ghostty (拡張子あり) は loadDefaultFiles の対象外なので
    # 混線しない (preferredXdgPath = 設定を開く UI 用の解決にのみ登場する)。
    # themes/ は同期しない。noctty は exe の隣に share/ghostty/themes/ を同梱しており
    # (src/config/theme.zig の探索 2 番目)、theme = "iTerm2 Solarized Light" もその中にある。
    home.activation.nocttyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      noctty_dir="/mnt/c/Users/${config.home.username}/AppData/Local/noctty"
      install -Dm644 ${ghostty.nocttyConfigFile} "$noctty_dir/config.ghostty"
    '';

    # noctty の同梱 ConPTY (conpty.dll + OpenConsole.exe) を自前ビルドへ配置するヘルパー
    #
    # noctty は in-box conhost の代わりに Microsoft の ConPTY 再頒布物を使う機構を持つ
    # (noctty#129 / #132)。exe と同じディレクトリに 2 ファイルを置くだけで自動的に
    # 切り替わる (src/pty.zig の loadBundled が exe_dir を見る。config オプションは無く
    # NOCTTY_CONPTY=inbox で強制無効化のみ)。
    #
    # これは見た目の問題ではなく実測差がある (#143):
    # - in-box conhost は APC を握り潰すため kitty graphics (画像表示) が一切通らない。
    #   さらに Primary DA を横取りして自分で答えるので、端末判定が conhost 相当になる。
    # - バルク描画も in-box では Plain scroll 0.065s / Unicode 0.176s だが、同梱では
    #   0.023s / 0.123s (同一バイナリの A/B。前者は GhostInTheWSL と同値)。
    #
    # 公式リリースには scripts/package-windows.ps1 が Install-ConPtyRedist で入れるが、
    # zig build は staging しない。zig-out を消すと道連れになるので、ビルドし直したら
    # これを実行する。
    #
    # 取得元とハッシュはすべて checkout 内の dist/windows/conpty-redist.json から読む。
    # noctty 側が pin を上げれば追随するので、ここに版を焼き込まない。
    # 検証は src/update/conpty_redist.zig と同じ 3 ガード (schemaVersion / packageId /
    # license) + nupkg と展開後 2 ファイルの SHA256。
    home.file.".local/bin/install-noctty-conpty" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        CURL=${pkgs.curl}/bin/curl
        JQ=${pkgs.jq}/bin/jq
        UNZIP=${pkgs.unzip}/bin/unzip
        SHA=${pkgs.coreutils}/bin/sha256sum

        repo="''${1:-/mnt/c/Users/${config.home.username}/source/repos/nanasess/noctty}"
        pin="$repo/dist/windows/conpty-redist.json"
        dest="$repo/zig-out/bin"
        cache="''${XDG_CACHE_HOME:-$HOME/.cache}/noctty-conpty"

        die() { echo "ERROR: $*" >&2; exit 1; }
        sha_is() { [ -r "$1" ] && [ "$("$SHA" "$1" | cut -d' ' -f1)" = "$2" ]; }

        [ -r "$pin" ] || die "pin が読めません: $pin"
        [ -d "$dest" ] || die "配置先がありません: $dest (先に zig build を実行)"

        schema=$("$JQ" -r '.schemaVersion' "$pin")
        pkgid=$("$JQ" -r '.packageId' "$pin")
        license=$("$JQ" -r '.license' "$pin")
        [ "$schema" = "1" ] || die "未対応の schemaVersion: $schema"
        [ "$pkgid" = "Microsoft.Windows.Console.ConPTY" ] || die "想定外の packageId: $pkgid"
        [ "$license" = "MIT" ] || die "想定外の license: $license"

        version=$("$JQ" -r '.version' "$pin")
        url=$("$JQ" -r '.nupkg.url' "$pin")
        nupkg_sha=$("$JQ" -r '.nupkg.sha256' "$pin")
        dll_path=$("$JQ" -r '.architectures.x64.conptyDll.entryPath' "$pin")
        dll_sha=$("$JQ" -r '.architectures.x64.conptyDll.sha256' "$pin")
        exe_path=$("$JQ" -r '.architectures.x64.openConsoleExe.entryPath' "$pin")
        exe_sha=$("$JQ" -r '.architectures.x64.openConsoleExe.sha256' "$pin")

        echo "pin: $pkgid $version"

        if sha_is "$dest/conpty.dll" "$dll_sha" && sha_is "$dest/OpenConsole.exe" "$exe_sha"; then
          echo "OK: 配置済み (SHA256 一致)。何もしません"
          exit 0
        fi

        mkdir -p "$cache/$version"
        nupkg="$cache/$version/package.nupkg"
        if ! sha_is "$nupkg" "$nupkg_sha"; then
          echo "取得: $url"
          "$CURL" -fsSL -o "$nupkg" "$url" || die "ダウンロード失敗"
          sha_is "$nupkg" "$nupkg_sha" || die "nupkg の SHA256 が pin と不一致"
        fi
        echo "nupkg SHA256 一致"

        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        "$UNZIP" -o -q "$nupkg" "$dll_path" "$exe_path" -d "$tmp" || die "展開失敗"
        sha_is "$tmp/$dll_path" "$dll_sha" || die "conpty.dll の SHA256 が pin と不一致"
        sha_is "$tmp/$exe_path" "$exe_sha" || die "OpenConsole.exe の SHA256 が pin と不一致"
        echo "ペイロード SHA256 一致"

        locked="配置失敗。noctty 起動中はロックされます。全ウィンドウを閉じて再実行してください"
        install -m644 "$tmp/$dll_path" "$dest/conpty.dll" || die "$locked"
        install -m755 "$tmp/$exe_path" "$dest/OpenConsole.exe" || die "$locked"

        echo "配置完了: $dest/{conpty.dll,OpenConsole.exe}"
        echo "反映には noctty の全ウィンドウを閉じて再起動が必要です"
        echo "確認: bash ~/check-graphics-protocol.sh の T3 が PASS になれば有効"
      '';
    };


    # LibreHardwareMonitor -> Mackerel カスタムメトリック (modules/mackerel/)
    # Windows 上の mackerel-agent が data.json を取得しメトリック化する。
    # 主 conf は apikey 平文 + Program Files 読取専用のため home-manager では触らず、
    # プラグイン本体と include フラグメントだけをユーザープロファイル配下へ配置する。
    # 主 conf 側に手動で include = 'C:\Users\nanasess\mackerel\conf.d\*.conf' を一度追記する。
    home.activation.mackerelLhm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      deploy_dir="/mnt/c/Users/${config.home.username}/mackerel"
      install -Dm644 ${../mackerel/lhm-metrics.ps1} "$deploy_dir/lhm-metrics.ps1"
      install -Dm644 ${../mackerel/lhm.conf} "$deploy_dir/conf.d/lhm.conf"
    '';

    # WSL 固有の zsh 設定
    programs.zsh.initContent = lib.mkAfter ''
      # VS Code PATH (WSL)
      export PATH="/mnt/c/Users/''${USER}/AppData/Local/Programs/Microsoft VS Code/bin":$PATH

      # X11/Wayland symlinks for WSLg
      if [ ! -L /tmp/.X11-unix ]; then
        rm -rf /tmp/.X11-unix
        ln -s /mnt/wslg/.X11-unix /tmp/.X11-unix
      fi
      if [ ! -L "''${XDG_RUNTIME_DIR}/wayland-0" ]; then
        rm -rf "''${XDG_RUNTIME_DIR}/wayland-0*"
        ln -s /mnt/wslg/runtime-dir/wayland-0* "$XDG_RUNTIME_DIR"
      fi

      # keyboard layout
      if [ -z "$WAYLAND_DISPLAY" ]; then
        if which setxkbmap > /dev/null; then setxkbmap -layout us; fi
      fi
    '';

    # Ghostty Windows port は C:\Windows\Fonts のみをスキャンするため
    # (src/font/SharedGridSet.zig の findWindowsFont 参照)、
    # ユーザーフォント (~/.local/share/fonts) からシステムフォントに
    # ワンショットでコピーするヘルパー (UAC 昇格が発生する)
    #
    # PowerShell スクリプトは UTF-16LE + base64 化して -EncodedCommand で
    # 直接引数として渡す。中間 .ps1 ファイルを作らないので、ユーザー書込可能な
    # 場所のファイルを昇格実行する際の TOCTOU リスクを回避できる
    home.file.".local/bin/install-ghostty-windows-fonts" = {
      executable = true;
      text = ''
        #!/bin/bash
        set -e
        user='${config.home.username}'
        src_dir="/mnt/c/Users/$user/.local/share/fonts"
        PSH='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

        if [ ! -x "$PSH" ]; then
          echo "ERROR: $PSH が見つかりません" >&2
          exit 1
        fi

        if ! ls "$src_dir"/UDEVGothic*.ttf >/dev/null 2>&1; then
          echo "ERROR: $src_dir に UDEVGothic*.ttf が見つかりません" >&2
          echo "まず home-manager の設定を適用してください (README のホスト一覧参照)" >&2
          exit 1
        fi

        read -r -d "" ps_script <<'EOF' || true
        $ErrorActionPreference = 'Stop'
        $src = Join-Path $env:USERPROFILE '.local\share\fonts'
        $dst = Join-Path $env:WINDIR 'Fonts'
        $files = Get-ChildItem -Path $src -Filter 'UDEVGothic*.ttf'
        if ($files.Count -eq 0) {
            Write-Host "ERROR: UDEVGothic*.ttf not found in $src"
            Read-Host 'Press Enter to close'
            exit 1
        }
        foreach ($f in $files) {
            Copy-Item -Path $f.FullName -Destination $dst -Force
            Write-Host "Copied: $($f.Name)"
        }
        Write-Host ""
        Write-Host "Done. Copied $($files.Count) file(s) to $dst"
        Start-Sleep -Seconds 2
        EOF

        # PowerShell -EncodedCommand は UTF-16LE base64 を要求する
        encoded=$(printf '%s' "$ps_script" | iconv -t UTF-16LE | base64 -w 0)

        echo "UAC 昇格プロンプトが出ます。[はい] で許可してください。"
        "$PSH" -NoProfile -Command \
          "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-EncodedCommand','$encoded'"

        echo ""
        echo "--- コピー結果の確認 ---"
        ls /mnt/c/Windows/Fonts/UDEVGothic*.ttf 2>/dev/null || echo "(まだ見つかりません — UAC を拒否したか、別の理由で失敗しています)"
      '';
    };

    # WSLg のクリップボードブリッジは Windows 側の画像を image/bmp としてのみ広告し、
    # CF_PNG を落とす。しかもその BMP は BITMAPINFOHEADER.biCompression == 3
    # (BI_BITFIELDS) で、Claude Code が同梱する sharp/libvips はこれをデコードできない。
    # Claude Code は先頭が 'BM' のとき PNG 変換を試み、失敗した例外を無言で握り潰すため、
    # Ctrl+V が「何も起きない」状態になる (anthropics/claude-code#50552。詳細な解析付きで
    # 報告されたが修正されないまま stale クローズ。#77102 / #36420 も重複扱いで閉じられた)。
    #
    # 対処: image/png を「追加で」広告し、要求されたら ImageMagick で BMP から変換して返す。
    # 既存の image/bmp 経路には手を入れないので、BMP を直接扱う他アプリの挙動は変わらない。
    # ~/.local/bin は PATH 上で ~/.nix-profile/bin より前にあるため、この shim が優先される。
    home.file.".local/bin/wl-paste" = {
      executable = true;
      text = ''
        #!/bin/sh
        real=${pkgs.wl-clipboard}/bin/wl-paste
        magick=${pkgs.imagemagick}/bin/magick
        grep=${pkgs.gnugrep}/bin/grep

        # 引数を走査して介入すべきかを決める。位置と短縮形に依存しないようにする。
        # --primary / --seat / --watch はクリップボード以外や別モードを対象にするため、
        # 介入すると要求と違うデータを返してしまう。素通しして本物に委ねる。
        mode=""
        want=""
        passthrough=""
        pending=""
        for arg in "$@"; do
          if [ "$pending" = "type" ]; then
            want="$arg"
            pending=""
            continue
          fi
          case "$arg" in
            -l | --list-types) mode="list" ;;
            -t | --type) pending="type" ;;
            --type=*) want="''${arg#--type=}" ;;
            -p | --primary | -s | --seat | --seat=* | -w | --watch) passthrough="yes" ;;
          esac
        done

        if [ -n "$passthrough" ]; then
          exec "$real" "$@"
        fi

        # 型一覧: bmp しか無いときだけ png を追加で見せる
        if [ "$mode" = "list" ]; then
          types=$("$real" "$@") || exit $?
          printf '%s\n' "$types"
          if printf '%s\n' "$types" | "$grep" -qx 'image/bmp' &&
             ! printf '%s\n' "$types" | "$grep" -qx 'image/png'; then
            printf 'image/png\n'
          fi
          exit 0
        fi

        # png 要求: 本物の png があれば委譲、無ければ bmp から変換
        if [ "$want" = "image/png" ]; then
          types=$("$real" -l 2>/dev/null) || exit 1
          if printf '%s\n' "$types" | "$grep" -qx 'image/png'; then
            exec "$real" "$@"
          fi
          if printf '%s\n' "$types" | "$grep" -qx 'image/bmp'; then
            # パイプで繋ぐと終了状態が magick のものになり、取得失敗を握り潰す。
            # 一時ファイルに落として取得側の終了状態を確かめてから変換する。
            tmp=$(mktemp) || exit 1
            trap 'rm -f "$tmp"' EXIT HUP INT TERM
            "$real" --type image/bmp > "$tmp" || exit 1
            "$magick" bmp:"$tmp" png:-
            exit $?
          fi
          exit 1
        fi

        exec "$real" "$@"
      '';
    };

    home.file.".local/bin/op" = {
      executable = true;
      text = ''
        #!/bin/bash
        OP_EXE="/mnt/c/Users/${config.home.username}/AppData/Local/Microsoft/WinGet/Links/op.exe"
        # Linux GUI との通信には setgid onepassword-cli 付きの op が要る。
        # Nix /nix/store では setgid が付与できないため、ディストリ側が用意した
        # setgid バイナリを参照する (hosts/ の wsl.opLinux)。
        OP_LINUX="${config.wsl.opLinux}"

        # op run は Linux のバイナリを実行するため、Windows の op.exe では動作しない
        if [ "$1" = "run" ] && [ -x "$OP_LINUX" ]; then
          exec "$OP_LINUX" "$@"
        fi

        if [ ! -f "$OP_EXE" ]; then
          echo "[ERROR] op.exe not found at $OP_EXE" >&2
          exit 1
        fi

        OP_VARS=$(env | grep ^OP_ | cut -d= -f1 | tr '\n' ':')
        export WSLENV="''${WSLENV:-}:''${OP_VARS%:}"
        exec "$OP_EXE" "$@"
      '';
    };
  };
}
