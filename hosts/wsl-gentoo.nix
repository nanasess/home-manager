# WSL 共通部分は modules/wsl。ここには Gentoo 固有の設定だけを置く。
{ lib, ... }:

let
  # Gentoo (portage) で管理するパッケージ一覧
  # Issue #48 の「3. Gentoo に残す」参照
  gentooPackages = [
    "app-admin/sudo"
    "app-eselect/eselect-repository"
    "app-portage/gentoolkit"
    "app-portage/mirrorselect"
    "dev-util/pkgdev"
    "dev-util/pkgcheck"
    "www-client/google-chrome"
    "x11-apps/mesa-progs"
    "x11-apps/xeyes"
    "app-shells/zsh"
    "sys-apps/plocate"
    # 日常の git は Nix 版が PATH で優先されるが、repos.conf の全リポジトリが
    # sync-type = git のため emerge --sync に portage 側の git が必要
    "dev-vcs/git"

    # SKK 辞書サーバ yaskkserv2 は Nix ビルド (pkgs/yaskkserv2.nix) で ubuntu と
    # 共通化したため portage 管理から外した。常駐は systemd ユーザーサービス
    # (modules/yaskkserv2.nix)、辞書は ~/.local/share/yaskkserv2/all (sudo 不要)。

    # 1Password (CLI は GURU overlay、GUI は jaredallard overlay)
    # Nix /nix/store では setgid を付与できず Linux GUI と通信できないため、
    # portage 経由で /usr/bin/op (setgid onepassword-cli) を導入する。
    # GUI は ~/.config/zsh/.env.local (FIFO) への secrets 注入と
    # SSH agent (~/.1password/agent.sock) を提供する。
    # GUI は app-admin/1password::jaredallard を正とする (modules/portage.nix 参照。
    # GURU gui-apps/1password は古くダウングレードすると起動不可のため不採用)
    "app-misc/1password-cli"
    "app-admin/1password"

    # mise PHP ビルド依存（asdf-php workflow.yml 参照）
    "dev-db/postgresql"
    "media-libs/gd"
    "net-misc/curl"
    "dev-libs/libedit"
    "dev-libs/icu"
    "media-libs/libjpeg-turbo"
    "dev-libs/oniguruma"
    "media-libs/libpng"
    "sys-libs/readline"
    "dev-db/sqlite"
    "dev-libs/openssl"
    "dev-libs/libxml2"
    "dev-libs/libzip"
    "dev-util/re2c"
    "sys-devel/bison"
    "dev-build/autoconf"
    "sys-libs/zlib"
  ];
in
{
  home.homeDirectory = "/home/nanasess";

  # portage の app-misc/1password-cli (GURU overlay) が setgid onepassword-cli 付きで
  # 提供する (gentooPackages 参照)。
  wsl.opLinux = "/usr/bin/op";

  home.file.".local/bin/check-system-packages" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      echo "=== Gentoo パッケージ差分チェック ==="
      missing=0
      for pkg in ${lib.concatStringsSep " " gentooPackages}; do
        if ! equery list "$pkg" &>/dev/null; then
          echo "MISSING: $pkg"
          missing=$((missing + 1))
        fi
      done
      if [ "$missing" -eq 0 ]; then
        echo "OK: すべてのパッケージがインストールされています"
      else
        echo "---"
        echo "$missing 個のパッケージが未インストールです"
        exit 1
      fi
    '';
  };
}
