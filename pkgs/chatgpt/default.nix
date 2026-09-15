{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, asar
, coreutils
, makeWrapper
, wrapGAppsHook3
, alsa-lib
, at-spi2-atk
, at-spi2-core
, cairo
, cups
, dbus
, expat
, gdk-pixbuf
, glib
, gtk3
, libdrm
, libgbm
, libGL
, libnotify
, libpulseaudio
, libsecret
, libusb1
, libx11
, libxcb
, libxcomposite
, libxdamage
, libxext
, libxfixes
, libxkbcommon
, libxrandr
, libxshmfence
, nspr
, nss
, pango
, pciutils
, pipewire
, systemd
, vulkan-loader
, wayland
, xdg-utils
}:

# ChatGPT デスクトップアプリ (Linux 版、2026-08 公開プレビュー) を OpenAI 配布の deb から
# パッケージ化する。nixpkgs の `chatgpt` は Darwin (arm64) 専用で Linux 向けが無い。
#
# 中身は Electron (独自ランタイム "owl"、resources/owl-*.json) + 同梱の codex / rg /
# node (cua_node) / sky_linux_x64。codex, codex-code-mode-host, rg は static-pie なので
# autoPatchelf の対象外。それ以外の ELF は NEEDED に従って buildInputs から rpath を張り、
# Chromium が dlopen する GL / Vulkan / PipeWire / PulseAudio 等は runtimeDependencies で足す。
#
# deb の postinst は apt リポジトリと署名鍵の登録、AppArmor プロファイル (userns 許可) の
# 読み込みをするだけで、NixOS ではどちらも不要 (unprivileged userns は既定で有効)。
let
  source = import ./source.nix;
in
stdenv.mkDerivation {
  pname = "chatgpt";
  inherit (source) version;

  # latest/chatgpt_amd64.deb は中身が入れ替わるため、apt pool のバージョン付き URL に固定する。
  src = fetchurl { inherit (source) url hash; };

  nativeBuildInputs = [
    dpkg
    asar
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libusb1 # node-hid (app.asar.unpacked/node_modules/@worklouder/…)
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    stdenv.cc.cc.lib # libstdc++ (cua_node/bin/node, *.node)
    systemd # libudev
  ];

  # Chromium / Electron が実行時に dlopen するもの (nixpkgs electron-bin の electronLibPath に倣う)。
  runtimeDependencies = [
    libGL
    libnotify
    libpulseaudio
    libsecret
    libxshmfence
    pciutils
    pipewire
    vulkan-loader
    wayland
  ];

  # 見つからなくてよい依存:
  #  - libc.musl-x86_64.so.1: app.asar.unpacked / cua_node には他プラットフォーム向けの
  #    プリビルド (.node) も同梱されている。Mach-O / PE / 他アーキテクチャは autoPatchelf が
  #    自動で飛ばすが、linux-x64-musl 版は x86_64 ELF なので対象になる。実行時に選ばれるのは
  #    glibc 版。
  #  - libQt5* / libQt6*: libqt{5,6}_shim.so は Chromium が KDE 上でだけ dlopen する
  #    ファイルダイアログ連携。GNOME では使わないので Qt を依存に入れない。
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;
  # $out/lib/chatgpt 配下を wrapGAppsHook3 に一括ラップさせず、bin/chatgpt だけ自分で作る。
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    dpkg-deb --fsys-tarfile $src | tar --extract
    mkdir -p $out
    mv usr/lib usr/share $out/
    # Debian / Ubuntu 固有のもの: lintian override、swcatalog (apt 向け AppStream キャッシュ)。
    rm -rf $out/share/lintian $out/share/swcatalog

    # /usr/bin/chatgpt は codex-launcher (sh で ChatGPT を exec するだけ) への symlink。
    # 代わりに GTK/GIO の環境変数を持ったラッパーを置く。
    mkdir -p $out/bin
    makeWrapper $out/lib/chatgpt/ChatGPT $out/bin/chatgpt \
      "''${gappsWrapperArgs[@]}" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-wayland-ime=true}}"

    # アイコンは pixmaps ではなく hicolor に置く (1024x1024 PNG)。
    mkdir -p $out/share/icons/hicolor/1024x1024/apps
    mv $out/share/pixmaps/chatgpt.png $out/share/icons/hicolor/1024x1024/apps/
    rmdir $out/share/pixmaps

    # 同梱プラグイン (resources/plugins/openai-bundled) は起動時に ~/.codex/.tmp/ へ
    # Node の fs.cp でコピーされる。fs.cp はソースのモードを宛先に写すため、Nix ストア
    # (ディレクトリ 555) からコピーすると宛先も書き込み不可になり、直後の plugin.json
    # 書き込みが EACCES で失敗する (bundled_plugins_marketplace_resolve_failed)。
    # コピー直後に chmod -R u+w を挟む。app.asar は同じ長さの置換ができないので
    # 展開 → パッチ → 再パックする。--unpack-dir は元の app.asar.unpacked に含まれる
    # ディレクトリ (ネイティブモジュール入り)。元より多くのファイルが unpacked 側に
    # 出るが動作は同じ。--replace-fail なので、上流がこの箇所を変えたらここで失敗する。
    asar extract $out/lib/chatgpt/resources/app.asar app
    substituteInPlace app/.vite/build/main-*.js \
      --replace-fail \
        'await y.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0});return}' \
        'await y.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0});await dne(`${coreutils}/bin/chmod`,[`-R`,`u+w`,t]);return}'
    rm -r $out/lib/chatgpt/resources/app.asar $out/lib/chatgpt/resources/app.asar.unpacked
    asar pack app $out/lib/chatgpt/resources/app.asar \
      --unpack-dir '{node_modules/@parcel/watcher-linux-x64-glibc,node_modules/@worklouder/device-kit-oai,node_modules/better-sqlite3,node_modules/node-pty}'

    # 同梱の Vulkan loader は nixpkgs のものに差し替える (electron-bin と同じ)。
    rm $out/lib/chatgpt/libvulkan.so.1
    ln -s ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $out/lib/chatgpt/libvulkan.so.1

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = with lib; {
    description = "ChatGPT desktop app for Linux (OpenAI 配布の deb を再パッケージ)";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "chatgpt";
  };
}
