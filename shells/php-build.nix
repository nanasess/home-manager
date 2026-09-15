# mise の php プラグイン (jdx/vfox-php) が PHP をソースビルドするための環境。
#
#   nix develop .#php-build --profile ~/.local/state/nix/profiles/php-build \
#     -c mise install php@8.5
#
# NixOS (k-2) には cc / make / /usr/include といった FHS 前提のビルド環境が無く、
# mise install php が「missing system dependencies」で止まる。wsl-gentoo では
# 同じ依存を portage (hosts/wsl-gentoo.nix) で入れている。
#
# プラグインが要求するもの (plugins/php/metadata.lua の systemDependencies):
#   - 必須ツール: cc, make, autoconf, bison >= 3.0, re2c, pkg-config
#   - ライブラリ: pkg-config で検出。無いと configure が失敗するもの (libxml2,
#     sqlite, openssl, curl, zlib, oniguruma, icu) と、検出時にだけ拡張が有効になる
#     もの (gd 一式, libzip, libpq, readline, gettext)。
#
# 落とし穴:
#   - ext/gettext と ext/readline の config.m4 は pkg-config を使わず
#     `for i in $PHP_XXX /usr/local /usr` でヘッダを探すため、NixOS では
#     `--with-gettext=DIR` / `--with-readline=DIR` を明示しないと
#     「Cannot locate header file libintl.h」で configure が失敗する。
#     nixpkgs の php も同じ回避をしている (pkgs/top-level/php-packages.nix)。
#     プラグインは PHP_EXTRA_CONFIGURE_OPTIONS を configure に追記するので
#     そこから渡す (後勝ちなのでプラグイン既定の --with-gettext を上書きできる)。
#   - プラグインは --with-pdo-pgsql を `pg_config` の有無で決める。nixpkgs では
#     pg_config が libpq とは別 derivation (libpq.pg_config)。
#   - cc-wrapper がリンク先ライブラリのストアパスを RPATH に焼き込むため、
#     この環境の closure が GC されると mise の PHP が起動しなくなる。
#     --profile で GC root を作って使うこと。flake update でライブラリが変わった
#     ときは古い世代がプロファイルに残る限り動くが、`nix profile wipe-history`
#     後は `mise install php@<ver> --force` で再ビルドが要る。
{ mkShell
, autoconf
, bison
, re2c
, pkg-config
, gnumake
, libpq
, libxml2
, openssl
, oniguruma
, icu
, zlib
, libzip
, curl
, sqlite
, libpng
, freetype
, libjpeg
, libwebp
, gd
, libsodium
, gmp
, readline
, glibc
}:

mkShell {
  nativeBuildInputs = [
    autoconf
    bison
    re2c
    pkg-config
    gnumake
    libpq.pg_config
  ];

  buildInputs = [
    libxml2
    openssl
    oniguruma
    icu
    zlib
    libzip
    curl
    sqlite
    # gd (--with-external-gd) とその画像フォーマット
    gd
    libpng
    freetype
    libjpeg
    libwebp
    libpq
    libsodium
    gmp
    readline
  ];

  # libintl.h は glibc が提供する (AC_CHECK_LIB(c, bindtextdomain) で検出される)。
  # sodium / gmp はプラグインの Linux 向け configure では有効化されない
  # (macOS の brew 検出のみ) ので、ここで明示する。gmp も /usr 探索型なので DIR 指定。
  PHP_EXTRA_CONFIGURE_OPTIONS = builtins.concatStringsSep " " [
    "--with-gettext=${glibc.dev}"
    "--with-readline=${readline.dev}"
    "--with-sodium"
    "--with-gmp=${gmp.dev}"
  ];
}
