# Ghostty 系ターミナルの共有設定。
#
# Windows 側で動く実装が 3 つあり、いずれも同じ `settings` から設定を生成する。
# **常用は noctty**、他の 2 つは比較・退避用として維持している (経緯は #143、旧 #116)。
#
# | 実装 | 位置づけ | WSL への接続 |
# |---|---|---|
# | noctty (amanthanvi/noctty) | **主 (常用)** | ConPTY 経由で `wsl.exe` を spawn |
# | GhostInTheWSL (Codavo/ghostinthewsl) | 従 (退避先) | Hyper-V ソケット + vsock で Linux PTY に直結 |
# | Ghostty Windows port (PR #12167) | 従 (参照実装) | ConPTY 経由 |
#
# noctty を主にした判断 (#143):
# - #116 で唯一残った不可理由「ConPTY 由来のバルク描画 2.8 倍差」は、noctty の
#   同梱 ConPTY に切り替えると消える (Plain scroll は GhostInTheWSL と同値)。
#   同じ切り替えで kitty graphics も通るようになる
# - 開発の継続性の差が決定的。過去 30 日で noctty 72 コミット / GhostInTheWSL 0。
#   自分が出した PR は noctty で最短 1 時間マージ、GhostInTheWSL では 30 日放置
# - IME・フォントのスタイル解決・ホイール座標も noctty が優位
#
# **同梱 ConPTY は自前ビルドには入らない**。`zig build` は staging しないので、
# ビルドし直したら `install-noctty-conpty` (hosts/wsl-gentoo.nix) を実行すること。
# 忘れると画像プロトコルとバルク描画性能が同時に失われる。

{ pkgs, lib, ... }:

let
  # 全ホスト共通の Ghostty 設定
  # Linux (home-manager programs.ghostty.settings) と Windows port
  # (%LOCALAPPDATA%\ghostty\config.ghostty) で共有する
  settings = {
    # UDEV Gothic JPDOC をプライマリ、NF を Nerd Font フォールバックとして使用
    # (WezTerm 設定と合わせる。modules/wezterm/wezterm.lua 参照)
    font-family = [
      "UDEV Gothic JPDOC"
      "UDEV Gothic NF"
    ];
    font-size = 13;
    keybind = [
      "ctrl+l=next_tab"
      "ctrl+h=previous_tab"
    ];
    theme = "iTerm2 Solarized Light";
    # マウス選択で通常クリップボードにコピー (Ctrl+V で貼付可能)
    # Linux では selection clipboard にも入るので中クリックペーストも維持される
    # Windows のデフォルトは false, Linux のデフォルトは true (selection のみ)
    copy-on-select = "clipboard";
  };

  # Windows で動作する版に共通のフォントフォールバック
  # - Segoe UI Symbol を追加フォールバック
  #   Ghostty 自動フォールバックリスト (CodepointResolver.zig) に seguisym.ttf が
  #   含まれておらず、U+23F5 (⏵) 等の記号が豆腐になるため明示指定
  windowsFontFamily = settings.font-family ++ [ "Segoe UI Symbol" ];

  # Windows port (PR #12167) 固有の追加設定
  # - command: 起動時に WSL の Gentoo-systemd ディストリをログインシェルで立ち上げる
  #   "direct:" プレフィックスを付けて /bin/sh -c ラップを回避 (Windows には sh が無い)
  #   --cd ~ でホームディレクトリに入る (WezTerm の default_cwd と等価)
  windowsSettings = settings // {
    command = "direct:wsl.exe -d Gentoo-systemd --cd ~";
    font-family = windowsFontFamily;
  };

  # GhostInTheWSL (Codavo/ghostinthewsl) 固有の設定 — **従 (退避先)**
  #
  # 2026-08-02 を最後に上流が停止しており (#143)、常用は noctty へ移した。
  # vsock 直結という設計はこれにしか無いため、noctty 側に致命的な回帰が出たときの
  # 退避先として設定を維持する。
  #
  # ConPTY を経由せず Hyper-V ソケットのブリッジで WSL2 の Linux PTY に直結するため、
  # Windows port のような command = "direct:wsl.exe ..." は不要 (ブリッジが WSL 接続を担う)。
  # - working-directory: デフォルト (inherit 相当) だと起動プロセス (Windows 側 exe) の
  #   cwd を引き継ぎ、/mnt/c/.../zig-out/bin で WSL シェルが起動してしまう。
  #   そこに blocked な .envrc があると direnv が zsh 初期化中に出力し、p10k instant
  #   prompt の警告を誘発する。
  #   GhostInTheWSL では `home` は無効 (src/Surface.zig の WorkingDirectory.value() が
  #   .home/.inherit に対し null を返し、ブリッジの cwd が空 → Windows cwd へフォールバック
  #   するだけで、upstream のような passwd home 解決が繋がっていない)。
  #   .path の明示パスのみブリッジへ cwd として渡るため、WSL ホームを直接指定する。
  ghostinthewslSettings = settings // {
    font-family = windowsFontFamily;
    working-directory = "/home/nanasess";
  };

  # noctty (amanthanvi/noctty、旧 winghostty) 固有の設定 — **主 (常用)**
  #
  # ConPTY 経由で wsl.exe を spawn する構造 (vsock ブリッジを持たない) のため、
  # WSL への接続方法は GhostInTheWSL ではなく Ghostty Windows port と同じになる。
  # よって windowsSettings をそのまま使う。
  # - command: WSL はプロファイルピッカーには出るが、明示指定しない限り既定シェルには
  #   ならない (docs/windows.md#shells: `wsl.exe --status` が健全と報告しても起動が
  #   失敗しうるため、暗黙の既定にしない設計)。
  #   "direct:" プレフィックスは src/config/command.zig で対応済み。
  # - working-directory は指定しない。--cd ~ で WSL 側のホームに入るため不要。
  #   (ghostinthewslSettings の working-directory はブリッジ固有の回避策であり、
  #   ConPTY 経由の noctty に POSIX パスを渡しても意味がない)
  # - 同梱 ConPTY はここでは設定できない。config オプションが無く、conpty.dll と
  #   OpenConsole.exe を exe の隣に置くかどうかで決まる (src/pty.zig の loadBundled)。
  #   配置は install-noctty-conpty (hosts/wsl-gentoo.nix) が行う。
  # - *-inherit-working-directory: 新規ウィンドウ/タブ/split が「起動プロセスの
  #   Windows cwd」を引き継いでしまうため 3 つとも無効化する。
  #   継承の可否は文脈ごとに別オプションで決まる
  #   (src/apprt/surface.zig:757-763 の shouldInheritWorkingDirectory:
  #    .window/.tab/.split → window-/tab-/split-inherit-working-directory)。
  #   既定はいずれも true (Config.zig:1981/1986/1991) なので、タブだけ直したい
  #   場合でも tab- を明示する必要がある。
  #   noctty は WSL 直起動を prepareCommand (src/config/windows_shell.zig:257-280) で
  #   書き換える: ユーザーが書いた --cd と裸の ~ を prepareWslDirect が無条件に除去し
  #   (:712-721)、代わりに解決済み cwd を --cd として注入する (:735-740)。
  #   解決順は「継承/明示 cwd > working-directory = home」なので、この設定が既定の
  #   true のままだと command の --cd ~ は常に無視される。
  #   初回タブは cwd 未確定で --cd ~ になるが、その際 safeCurrentDirectoryWithCurrent
  #   (:230-241) が起動プロセスの Windows cwd を端末の pwd として採用する
  #   ("using inherited windows cwd")。zig-out\bin から起動していると新規タブが
  #   それを継承して /mnt/c/.../zig-out/bin で zsh が立ち上がり、blocked な .envrc に
  #   direnv が反応して p10k instant prompt 警告を誘発する。
  #   OSC 7 自体は modules/zsh で shell integration を手動ロードするようにしたので
  #   WSL 側から届くようになった (自動注入は Windows 側 env の境界で届かない)。
  #   noctty 側の受け口も用意されている (windows_shell.zig の osc7PathToLocal /
  #   isWslPath が POSIX パスを WSL 形式のまま保持し、後続の WSL シェルへ継承する)
  #   が、実機での継承挙動は未検証のため無効化は維持する。常に
  #   working-directory = home (= wsl.exe --cd ~) を使わせる。
  #   新規タブが期待どおりの cwd で開くことを確認できたら、この 3 行は外せる。
  nocttySettings = windowsSettings // {
    window-inherit-working-directory = false;
    tab-inherit-working-directory = false;
    split-inherit-working-directory = false;
  };

  # home-manager の programs.ghostty が内部で使っているのと同じフォーマッタ
  # (listsAsDuplicateKeys = true で keybind = ... 行を複数行に展開)
  renderConfig = lib.generators.toKeyValue {
    mkKeyValue = lib.generators.mkKeyValueDefault { } " = ";
    listsAsDuplicateKeys = true;
  };

  configFile = pkgs.writeText "ghostty-config.ghostty" (renderConfig windowsSettings);
  ghostinthewslConfigFile = pkgs.writeText "config.ghostinthewsl" (renderConfig ghostinthewslSettings);
  nocttyConfigFile = pkgs.writeText "noctty-config.ghostty" (renderConfig nocttySettings);
in
{
  # settings / configFile / ghostinthewslConfigFile / nocttyConfigFile を
  # 他のモジュール (hosts/*.nix) から参照できるように公開
  _module.args.ghostty = {
    inherit settings configFile ghostinthewslConfigFile nocttyConfigFile;
  };

  # xterm-ghostty の terminfo を ~/.terminfo に配置する。
  #
  # wsl-gentoo は端末が Windows 側で動く (Ghostty Windows port / GhostInTheWSL) ため
  # WSL 側に ghostty パッケージを入れておらず、TERM=xterm-ghostty だけが渡ってくる。
  # terminfo が無いと zsh/readline が行編集・履歴表示を崩すので、terminfo だけを
  # 独立 output (クロージャ 4.9 KiB、ghostty 本体を引き込まない) から供給する。
  #
  # 配置先を ~/.terminfo にする理由: ncurses は system 版 (Gentoo/Ubuntu の
  # /usr/bin) と Nix 版のどちらも ~/.terminfo を無条件に検索するため、
  # TERMINFO_DIRS の設定なしで確実に引ける。home.packages 経由だと
  # ~/.nix-profile/share/terminfo が検索パスに入る保証がない (非 NixOS のため)。
  #
  # 別名 g/ghostty は張らない。Ghostty が渡す TERM は常に xterm-ghostty。
  home.file.".terminfo/x/xterm-ghostty".source =
    "${pkgs.ghostty.terminfo}/share/terminfo/x/xterm-ghostty";
}
