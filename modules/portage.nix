{ ... }:
{
  # Portage 設定を ~/.config/portage/ 以下に書き出す
  # /etc/portage/ の各ファイルから個別にシンボリックリンクする（初回セットアップは Issue #40 参照）
  #
  # /etc/portage/ 内で root 管理のまま残すもの:
  # - gnupg/ (GnuPG 鍵。root 所有・600 が必要)
  # - make.profile (プロファイルシンボリックリンク。eselect profile で管理)
  # - profile/ (package.use.force 等)

  # binrepos.conf: --getbinpkg 用（空でも存在が必要）
  xdg.configFile."portage/binrepos.conf".text = ''
    [binhost]
    sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/
  '';

  # repos.conf: eselect-repo で生成された設定を含む
  # eselect-repo.conf~ (バックアップ) は除外
  xdg.configFile."portage/repos.conf/eselect-repo.conf".text = ''
    # created by eselect-repo

    [gentoo]
    location = /var/db/repos/gentoo
    sync-type = git
    sync-uri = https://github.com/gentoo-mirror/gentoo.git

    [dark-sushier]
    location = /var/db/repos/dark-sushier
    sync-type = git
    sync-uri = https://github.com/dark-sushier/portage-overlay.git

    [guru]
    location = /var/db/repos/guru
    sync-type = git
    sync-uri = https://github.com/gentoo-mirror/guru.git

    [jaredallard]
    location = /var/db/repos/jaredallard-overlay
    sync-type = git
    sync-uri = https://github.com/jaredallard/overlay.git

    [tatsh-overlay]
    location = /var/db/repos/tatsh-overlay
    sync-type = git
    sync-uri = https://github.com/Tatsh/tatsh-overlay.git

    [supertux88]
    location = /var/db/repos/supertux88
    sync-type = git
    sync-uri = https://github.com/SuperTux88/gentoo-overlay.git
  '';

  xdg.configFile."portage/make.conf".text = ''
    # These settings were set by the catalyst build script that automatically
    # built this stage.
    # Please consult /usr/share/portage/config/make.conf.example for a more
    # detailed example.

    ## default USE flags
    ## emerge --info | grep ^USE
    USE="keyring wayland gnome"
    PHP_TARGETS="php8-2"

    COMMON_FLAGS="-march=znver3 -O2 -pipe"
    CHOST="x86_64-pc-linux-gnu"

    # see https://wiki.gentoo.org/wiki/Gentoo_in_WSL/ja#X11_.E3.81.BE.E3.81.9F.E3.81.AF_Wayland_.E3.82.92.E4.BD.BF.E7.94.A8.E3.81.99.E3.82.8B.E3.82.B0.E3.83.A9.E3.83.95.E3.82.A3.E3.82.AB.E3.83.AB.E3.83.97.E3.83.AD.E3.82.B0.E3.83.A9.E3.83.A0
    VIDEO_CARDS="d3d12"

    CFLAGS="''${COMMON_FLAGS}"
    CXXFLAGS="''${COMMON_FLAGS}"
    FCFLAGS="''${COMMON_FLAGS}"
    FFLAGS="''${COMMON_FLAGS}"

    MAKEOPTS="-j28 -l16"

    BINPKG_FORMAT="gpkg"
    EMERGE_DEFAULT_OPTS="''${EMERGE_DEFAULT_OPTS} --getbinpkg"

    # NOTE: This stage was built with the bindist Use flag enabled

    # This sets the language of build output to English.
    # Please keep this setting intact when reporting bugs.
    LC_MESSAGES=C.utf8

    EGIT_OVERRIDE_REPO_EMACS="https://github.com/emacs-mirror/emacs.git"
    GENTOO_MIRRORS="http://ftp.iij.ad.jp/pub/linux/gentoo/ \
        https://ftp.jaist.ac.jp/pub/Linux/Gentoo/ \
        https://repo.jing.rocks/gentoo \
        rsync://repo.jing.rocks/gentoo"
  '';

  # #48 移行済みパッケージを除外
  xdg.configFile."portage/package.accept_keywords".text = ''
    dev-python/sqlglot
    app-editors/emacs **
    net-misc/onedrive
    sys-devel/gcc:15
    app-admin/cf-terraforming
    dev-python/pipx
    dev-python/userpath
    dev-php/symfony-cli
    dev-python/pyfzf
    app-emacs/emacs-common
    dev-python/click
    media-libs/mesa
  '';

  xdg.configFile."portage/package.mask".text = ''
    >app-editors/emacs-31
  '';

  xdg.configFile."portage/package.unmask".text = ''
    >=www-client/google-chrome-126.0.6478.55
    >=virtual/dotnet-sdk-9.0
    # mycli-1.41.2の依存関係
    dev-python/click
  '';

  # #48 移行済みパッケージを除外（terraform, 1password, op-cli-bin）
  xdg.configFile."portage/package.license".text = ''
    www-client/google-chrome google-chrome
  '';

  # package.use: #49 検証中
  xdg.configFile."portage/package.use/emacs".text = ''
    app-editors/emacs xft -gsettings gconf gtk -athena -Xaw3d dynamic-loading gif gui gzip-el harfbuzz imagemagick jpeg json libxml2 livecd m17n-lib mailutils png svg tiff toolkit-scroll-bars wide-int xwidgets cairo jit tree-sitter X webp sqlite ssl tools -pgtk
    # required by app-editors/emacs-29.3-r2::gentoo[jit]
    # required by @selected
    # required by @world (argument)
    >=sys-devel/gcc-13.2.1_p20240210 jit
  '';

  xdg.configFile."portage/package.use/ffmpeg".text = ''
    media-video/ffmpeg libass lzma opus pulseaudio theora vpx
    media-libs/libsdl2 gles2 pipewire pulseaudio
    media-libs/libvpx postproc
    media-video/pipewire gstreamer
    media-sound/mpg123-base pulseaudio
    media-sound/pulseaudio-daemon gstreamer
  '';

  xdg.configFile."portage/package.use/gnupg".text = ''
    app-crypt/gpgme -qt5 -qt6
    app-crypt/gnupg -usb
  '';

  xdg.configFile."portage/package.use/onedrive".text = ''
    net-misc/onedrive libnotify dmd-2_105
    sys-devel/gcc d
  '';
}
