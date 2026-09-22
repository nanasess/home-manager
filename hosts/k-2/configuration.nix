# k-2: Intel MacBook Pro 13" 2020 (MacBookPro16,2, T2 チップ) の NixOS システム設定。
#
# Ubuntu 24.04 (t2linux カーネル) からの移行先。経緯と手順は issue #151。
# T2 固有の部分 (linux-t2 カーネル / apple-bce / Touch Bar / T2 オーディオ /
# WiFi・BT ファームウェア) は nixos-hardware の apple-t2 モジュールが担い、
# ここではそれ以外のシステム構成を宣言する。ユーザー環境は ./home.nix (home-manager)。
{ config, pkgs, lib, ... }:

let
  # nixpkgs / apt には 1.4.4 が無いため上流をローカルでビルドする (pkgs/ibus-skk.nix)。
  # Ubuntu では IBUS_COMPONENT_PATH で登録していたが (modules/ibus-skk/ubuntu.nix)、
  # NixOS は i18n.inputMethod.ibus.engines で ibus 本体ごと束ねるので不要。
  ibus-skk = pkgs.callPackage ../../pkgs/ibus-skk.nix { };
  # ChatGPT デスクトップアプリ (Linux 版)。nixpkgs の chatgpt は Darwin 専用なので
  # OpenAI 配布の deb を再パッケージする (pkgs/chatgpt)。更新は pkgs/chatgpt/update.sh。
  chatgpt = pkgs.callPackage ../../pkgs/chatgpt { };
in
{
  imports = [ ./hardware-configuration.nix ];

  # ---------------------------------------------------------------------------
  # T2 (nixos-hardware apple-t2)
  # ---------------------------------------------------------------------------

  # WiFi / Bluetooth (BCM4364B3 "Trinidad") のファームウェアを Apple の復旧イメージから
  # 宣言的に抽出する。vmTools.runInLinuxVM で HFS+ をマウントするため QEMU が動く
  # (KVM が無くても TCG で完走する。Ubuntu 上での事前ビルドで確認済み)。
  #
  # version は ventura に固定。既定の sonoma は抽出スクリプト (get-wifi) が BCM4388
  # (Willamette) のエントリで AssertionError を起こして失敗する (2026-09-14、
  # nixos-hardware 24cfdc1)。ventura 版に brcmfmac4364b3-pcie.apple,trinidad.* と
  # brcmbt4364b3-apple,trinidad.* が入っていることは確認済み。
  #
  # 失敗する場合の保険として、Ubuntu 時代の /lib/firmware/brcm を USB に退避してある
  # (issue #151)。その場合は boot.kernelParams の firmware_class.path= でリポジトリ外の
  # ディレクトリを指す (public リポジトリに Apple のファームウェアは置かない)。
  hardware.apple-t2.firmware = {
    enable = true;
    version = "ventura";
  };

  # Touch Bar (tiny-dfr)。nixos-hardware 側の enableTinyDfr は nixpkgs 本体の
  # モジュールに統合され削除されたため、こちらを使う。
  hardware.apple.touchBar.enable = true;

  # サスペンド (modules/t2-suspend の NixOS 版。Ubuntu では sudo で /etc に配置していた)。
  #  - hibernation は BCE コントローラが電源復帰できず失敗するので封じる
  #  - 蓋閉じ → suspend。外部モニタ接続 (docked) 時は無視 (gsettings と整合)
  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
  };
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  # Touch Bar の復帰フック (issue #151 コメント 2026-09-16)。
  #
  # サスペンド中は apple-bce が VHCI ごと USB デバイスを外し、復帰時に再列挙する。
  # このとき Touch Bar (05ac:8302) は制御転送に応答しない状態で上がってきて、nixpkgs の
  # 99-touchbar-tiny-dfr.rules が試みる bConfigurationValue 1→0→2 が両方
  # -ETIMEDOUT になり、デバイスは未構成 (appletbdrm も hid-multitouch も無し)、
  # tiny-dfr は backlight 消失で panic → BindsTo で stop されたまま、という結果になる
  # (kernel 6.12.31+ で driver core が device_lock() を外したことによる udev との競合。
  # t2linux/wiki#635、omarchy discussion #5862)。短いサスペンドでも毎回起きる。
  #
  # 実測では USB リセット (USBDEVFS_RESET) を 1 回通した後なら SET_CONFIGURATION が
  # 通るので、復帰後に「usbreset → bConfigurationValue=2」を打ち直す。config 2 で
  # Touch Bar Display Touchpad の input が出ると udev の SYSTEMD_WANTS で tiny-dfr が
  # 起動するが、生き残っていた場合に備えて restart もかける。
  systemd.services.touchbar-resume = {
    description = "Re-enumerate the Touch Bar after resume";
    # suspend.target は systemd-suspend.service の完了 (= 復帰) 後に到達するので、
    # WantedBy + After でその直後に走る
    wantedBy = [ "suspend.target" ];
    after = [ "suspend.target" ];
    path = [ pkgs.usbutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      # apple-bce の VHCI 再構築は非同期なので、Touch Bar が sysfs に出るまで待つ
      dev=
      for _ in $(seq 30); do
        for d in /sys/bus/usb/devices/[0-9]*-*; do
          if [ "$(cat "$d/idVendor" 2>/dev/null)" = 05ac ] \
             && [ "$(cat "$d/idProduct" 2>/dev/null)" = 8302 ]; then
            dev=$d
            break 2
          fi
        done
        sleep 1
      done
      if [ -z "$dev" ]; then
        echo "Touch Bar (05ac:8302) not found after resume"
        exit 0
      fi
      # 99-touchbar-tiny-dfr.rules の 1→0→2 (timeout 5s x 2) が終わるのを待ってから触る
      udevadm settle --timeout=30 || true
      if [ "$(cat "$dev/bConfigurationValue")" = 2 ]; then
        echo "Touch Bar already in configuration 2"
        exit 0
      fi
      echo "Touch Bar is stuck (bConfigurationValue='$(cat "$dev/bConfigurationValue")'), resetting"
      usbreset 05ac:8302
      sleep 1
      echo 2 > "$dev/bConfigurationValue"
      sleep 3
      systemctl restart tiny-dfr.service
    '';
  };

  services.thermald.enable = true;

  # ---------------------------------------------------------------------------
  # ブート
  # ---------------------------------------------------------------------------

  # ESP (300MB) は macOS と共用で小さいため、systemd-boot のように世代ごとに
  # カーネル + initrd を ESP に積む方式は採らない。GRUB を ESP に置き、カーネルは
  # root 側の /boot から読ませる (Ubuntu と同じ構成)。
  #
  # GRUB はリムーバブルパス EFI/BOOT/BOOTX64.EFI に置く (efiInstallAsRemovable)。
  # Apple の Startup Manager (Option キー) は UEFI の Boot#### エントリを列挙せず、
  # ESP の EFI/BOOT/BOOTX64.EFI だけを「EFI Boot」として出す。初回インストールは
  # canTouchEfiVariables = true で EFI/NixOS-boot-efi/grubx64.efi + NVRAM エントリを
  # 作っていたため、「EFI Boot」= Ubuntu の shim のままで、shim の fallback が
  # BootOrder を Ubuntu 先頭に書き戻して NixOS に入れなくなった (issue #151)。
  # canTouchEfiVariables は efiInstallAsRemovable と排他 (nixpkgs の assertion) なので
  # 既定の false のままにし、NVRAM は NixOS では管理しない。NVRAM 側の掃除と
  # NixOS エントリの追加は docs/nixos-t2.md の手順で 1 回だけ手動で行う。
  # 注意: install-grub.pl は efiInstallAsRemovable / canTouchEfiVariables を
  # /boot/grub/state の比較に含めないため、この 2 つだけ変えても switch は grub-install を
  # 再実行しない。切り替え時は nixos-rebuild switch --install-bootloader で強制する。
  # Ubuntu の shim は EFI/ubuntu/ に残り、GRUB メニューの Ubuntu エントリから戻れる。
  boot.loader = {
    efi.efiSysMountPoint = "/boot/efi";
    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
      # 併存する Ubuntu / macOS をメニューに出す (ロールバック経路)。
      useOSProber = true;
      configurationLimit = 20;
    };
  };

  # ---------------------------------------------------------------------------
  # ネットワーク
  # ---------------------------------------------------------------------------

  networking.hostName = "k-2";
  networking.networkmanager = {
    enable = true;
    # L2TP/IPsec (PSK + MS-CHAPv2) のリモートアクセス VPN 用。strongSwan / xl2tpd を
    # 同梱しており、NixOS モジュール側で /etc/ipsec.secrets の include
    # (NixOS/nixpkgs#64965) も処理される。Ubuntu の network-manager-l2tp(-gnome) 相当。
    plugins = [ pkgs.networkmanager-l2tp ];
    # T2 チップは apple-bce 経由の内部 USB (Apple T2 Controller / iBridge, cdc_ncm) で
    # 仮想イーサネット (enp230s0f1u1, MAC ac:de:48:00:11:22) を露出する。外部ポートでは
    # なく常時キャリア ON のため、放っておくと NetworkManager が起動直後から「有線接続」
    # として DHCP を試み続ける (USB イーサネットを挿していないのに有線が有効に見える原因)。
    # MAC は T2 Mac 共通の固定値なので、これで管理対象から外す。実物の USB イーサネット
    # アダプタは別 MAC なので従来どおり接続時に自動接続される。
    unmanaged = [ "mac:ac:de:48:00:11:22" ];
  };
  # nm-l2tp は接続のたびに PSK を /etc/ipsec.d/ipsec.nm-l2tp.secrets へ書き出す
  # (nixpkgs の NM モジュールが /etc/ipsec.secrets にその include を入れるのはこのため)。
  # ところが /etc/ipsec.d 自体は誰も作らず、接続直後に
  # "failed to connect: 'Could not write /etc/ipsec.d/ipsec.nm-l2tp.secrets'" で切断される。
  systemd.tmpfiles.rules = [ "d /etc/ipsec.d 0755 root root -" ];
  # strongSwan 6.0 は /etc/strongswan.conf が無いと library_init() が
  # "no files found matching '/etc/strongswan.conf'" で失敗し、starter はそれを
  # "charon has quit: integrity test of libstrongswan failed" (exit 64) と報告する。
  # services.strongswan は使わない (nm-l2tp が接続ごとに自前の charon を起動する) ので、
  # 既定値のままの空ファイルだけ置く。
  environment.etc."strongswan.conf".text = "";
  # iPhone の USB テザリング。iPhone は挿しただけでは USB 構成 1 (PTP のみ) に留まり、
  # テザリング用のイーサネット interface (ipheth) が現れない。usbmuxd の udev ルールが
  # 構成を切り替えて初めて ipheth が bind し、NetworkManager に有線接続として見える。
  # Ubuntu Desktop は usbmuxd を同梱していたので意識せず動いていた。
  services.usbmuxd.enable = true;
  # 自宅ルータ (F660A, DHCP の第 1 ネームサーバ) は EDNS0 クエリに FORMERR を返す。
  # 既定の resolv.conf には options edns0 が入り、glibc は FORMERR を回答として受け取り
  # 次のサーバへ回らないため名前解決ができなくなる (dig +edns=0 @192.168.100.1 で再現)。
  # edns0 を出さなければ通常のクエリで応答する。
  networking.resolvconf.dnsExtensionMechanism = false;

  # ---------------------------------------------------------------------------
  # ロケール / 入力
  # ---------------------------------------------------------------------------

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = [
      pkgs.ibus-engines.mozc
      ibus-skk
    ];
  };

  # ---------------------------------------------------------------------------
  # デスクトップ (GNOME)
  # ---------------------------------------------------------------------------

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  services.pulseaudio.enable = false;
  hardware.bluetooth.enable = true;

  # xremap (modules/xremap) 用。Ubuntu では udev ルールと input グループを sudo で
  # 用意していたが、NixOS では uinput グループ + udev ルールをここで宣言する。
  hardware.uinput.enable = true;

  fonts.packages = with pkgs; [
    # Ubuntu では OS の静的 Noto CJK (fonts-noto-cjk) に委譲していた。nixpkgs の既定は
    # 可変フォント版で Emacs (ftcrhb) が realize できず豆腐になるため (home.nix の
    # コメント参照)、静的版を選ぶ。
    noto-fonts-cjk-sans-static
    noto-fonts-cjk-serif-static
    # GNOME の UI フォント (Adwaita Sans)。
    adwaita-fonts
  ];

  # ---------------------------------------------------------------------------
  # サービス / プログラム
  # ---------------------------------------------------------------------------

  virtualisation.docker.enable = true;

  # zsh をログインシェルにするには NixOS 側でも有効化が必要 (/etc/shells 登録)。
  # 設定本体は modules/zsh (home-manager)。
  programs.zsh.enable = true;

  # Claude Code はネイティブインストーラー (~/.local/bin/claude、bun 製の汎用 ELF) を
  # 他ホストと同じ経路 (自己更新あり) で使う。NixOS 既定の stub-ld は汎用 ELF を
  # 「動かない理由」のメッセージで止めるだけなので、nix-ld で実行可能にする
  # (既定ライブラリに stdenv.cc.cc / zlib / openssl 等が入る)。
  # nixpkgs の claude-code (autoPatchelf 版) は flake update 待ちになるため採らない。
  programs.nix-ld.enable = true;

  # Playwright が公式配布する Chromium (~/.cache/ms-playwright、`playwright install`) を
  # nix-ld で動かすための実行時ライブラリ。EcAuth (E2ETests) は @playwright/test 1.63
  # を要求するが nixpkgs の playwright-driver は 1.61 でブラウザのリビジョンが合わず
  # (chromium-1243 vs 1228)、宣言的に追従すると更新のたびに hash 更新が要る。
  # 代わりにライブラリ集合だけ用意して公式バイナリを使う (`playwright install-deps` 相当)。
  # 集合は nixpkgs の pkgs/development/web/playwright/chromium.nix の buildInputs と同じ。
  # 既定の基本ライブラリ (上記) はモジュール側の定義とリストとしてマージされる。
  # 検証: E2ETests/tests-examples/demo-todo-app.spec.ts 24 passed (2026-09-15)。
  programs.nix-ld.libraries = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    gobject-introspection
    libGL
    libgbm
    libgcc
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
    pciutils
    vulkan-loader
  ];

  # 1Password。SSH agent (~/.1password/agent.sock) と commit 署名 (op-ssh-sign) は
  # home.nix / hosts/k-2/home.nix から参照する。
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "nanasess" ];
  };
  # nixpkgs の Chrome はストアパスから起動するため、1Password のブラウザ連携が
  # 許可リストで弾く。バイナリ名 (chrome) を許可する。
  # 要確認: 実機で拡張から接続できなければ wiki.nixos.org/wiki/1Password を参照。
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      chrome
    '';
    mode = "0755";
  };

  # Chrome の 1Password 拡張を企業ポリシー (ExtensionInstallForcelist) で強制導入する。
  # programs.chromium は Chromium 用モジュールだが /etc/opt/chrome/policies/managed/
  # にも同じポリシーを書くので Google Chrome に効く (Chromium 本体は入らない)。
  # 拡張とデスクトップアプリの接続承認 (初回のみ) は 1Password 側の認証フローなので残る。
  programs.chromium = {
    enable = true;
    extensions = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1Password – Password Manager
    ];
  };

  # GUI アプリは home-manager の pkgs (home.nix の allowUnfreePredicate) と分けて
  # システム側で管理する。unfree の許可はこのファイルの nixpkgs.config に集約。
  environment.systemPackages = with pkgs; [
    google-chrome
    slack
    spotify
    chatgpt
    dbeaver-bin
    gnome-tweaks
    vim
    git
    # NVRAM の整理 (docs/nixos-t2.md)。efiInstallAsRemovable で NixOS は NVRAM を
    # 管理しないため、Ubuntu の fallback で BootOrder が戻ったときに手で直す。
    efibootmgr
    # Touch Bar が復帰後に死んだときの手動復旧 (usbreset。docs/nixos-t2.md「サスペンド」)
    usbutils
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "1password"
      "1password-cli"
      # nixos-hardware apple-t2 の WiFi/BT ファームウェア (Apple 復旧イメージ由来)。
      # 実体 (pname brcm-firmware) と、それを zstd 圧縮した派生 (名前が
      # brcm-firmware-<macOS version>-zstd で lib.getName が分解できない) の両方が要る。
      "brcm-firmware"
      "brcm-firmware-ventura-zstd"
      "chatgpt"
      "google-chrome"
      "slack"
      "spotify"
    ];

  # ---------------------------------------------------------------------------
  # バックアップ (restic → Synology DS720+ "home-backup")
  # ---------------------------------------------------------------------------
  #
  # NixOS + home-manager で再現できるものは取らず、flake の外にある状態だけを
  # restic で NAS に送る。復旧は docs/nixos-t2.md の再インストール → nixos-rebuild
  # → restic-nas restore。NAS 側の設定 (backup ユーザー / SFTP / Btrfs スナップショット)
  # と復旧手順は docs/restic-nas.md。
  #
  # 転送は DSM 組み込みの SFTP のみで、NAS 側に追加ソフトは要らない。DSM の SFTP は
  # 非 admin ユーザーに「権限のある共有フォルダを / 直下に並べた仮想ルート」を見せる
  # ので、リポジトリのパスは /volume1/restic/... ではなく /restic/... になる。
  #
  # 秘密情報は /root/secrets/ (0700、Nix 管理外、手動配置):
  #   restic-nas.pass      リポジトリのパスフレーズ
  #   restic-nas_ed25519   NAS の backup ユーザー用 SSH 秘密鍵 (パスフレーズなし)
  # systemd から動くため 1Password の SSH agent は使えず、この 2 ファイルだけは復号値を
  # ディスクに置く (CLAUDE.md「1Password とクレデンシャル管理」の例外運用)。正本は
  # 1Password の op://synology/restic-key/{restic-nas.pass,private_key} に控えてあり、
  # 復旧時は op read で取り出す (docs/restic-nas.md)。
  # 鍵は backup ユーザー専用で、NAS 上の他の共有フォルダ (TimeMachine 等) には届かない。
  services.restic.backups.nas = {
    # /etc, /var/lib も取るので root で動かす
    user = "root";
    repository = "sftp:backup@192.168.100.15:/restic/k-2";
    passwordFile = "/root/secrets/restic-nas.pass";
    initialize = true;
    extraOptions = [
      # ホスト鍵は programs.ssh.knownHosts (/etc/ssh/ssh_known_hosts) で検証する。
      # ConnectTimeout は NAS 不達 (外出先) で ssh が長く待って suspend を阻止しないため
      "sftp.command='ssh backup@192.168.100.15 -i /root/secrets/restic-nas_ed25519 -o BatchMode=yes -o ConnectTimeout=10 -s sftp'"
    ];
    paths = [
      "/home/nanasess"
      # VPN (l2tp) の接続定義と秘密。NetworkManager が生成するので flake には無い
      "/etc/NetworkManager/system-connections"
      # Bluetooth のペアリング鍵
      "/var/lib/bluetooth"
    ];
    exclude = [
      # 再生成できるキャッシュ / パッケージストア
      "/home/nanasess/.cache"
      "/home/nanasess/.nuget"
      "/home/nanasess/.npm"
      "/home/nanasess/.local/share/NuGet"
      "/home/nanasess/.local/share/pnpm"
      "/home/nanasess/.local/share/uv"
      "/home/nanasess/.local/share/flatpak"
      # Claude Code 本体 (自己更新する)。設定とメモリは ~/.config/claude で別
      "/home/nanasess/.local/share/claude"
      # ChatGPT の Codex ランタイム (自己更新、CLAUDE.md 参照)
      "/home/nanasess/.codex"
      # クラウド側が正
      "/home/nanasess/OneDrive - Skirnir Inc"
      # Electron アプリの状態 (ログインし直せば戻る)
      "/home/nanasess/.config/Slack"
      "/home/nanasess/.config/Codex"
      "/home/nanasess/.config/google-chrome/*/Cache"
      "/home/nanasess/.config/google-chrome/*/Code Cache"
      "/home/nanasess/.config/google-chrome/*/Service Worker/CacheStorage"
      # elpaca のビルド成果物 (elpaca.lock から再現できる)
      "/home/nanasess/.emacs.d/elpaca"
      "/home/nanasess/.emacs.d/eln-cache"
      # git-repos 配下の依存 / ビルド成果物。コミット済みのものは .git 側に残る
      "**/node_modules"
      "**/vendor"
      "**/.venv"
      "**/target"
      "**/.direnv"
      "**/result"
    ];
    extraBackupArgs = [
      # CACHEDIR.TAG のあるディレクトリを除外 (mise / cargo / pip 等が置く)
      "--exclude-caches"
      "--one-file-system"
    ];
    # inhibitsSleep は使わない。復帰直後に Persistent の追いつき実行が走ると、logind が
    # まだ suspend 操作を終えておらず systemd-inhibit が
    # "The operation inhibition has been requested for is already running" で失敗し、
    # 復帰のたびにその回を落とす (2026-09-22 実機で確認。suspend exit と同じ秒に発火)。
    # 差分バックアップは十数秒で終わり、restic は中断に強い (次回の unlock でロックを外す)。
    timerConfig = {
      OnCalendar = "hourly";
      # NAS に届かない時間帯 (外出先 / suspend 中) の分は起動時にまとめて追いつく
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
    pruneOpts = [
      "--keep-hourly 24"
      "--keep-daily 14"
      "--keep-weekly 8"
      "--keep-monthly 12"
    ];
  };

  # NAS のホスト鍵。restic の sftp が root で動くため、ユーザーの known_hosts ではなく
  # システム側に置く。鍵が変わったら (NAS 再インストール等) ここを更新する。
  programs.ssh.knownHosts."192.168.100.15".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMX+S3/FfXieCNkRdNSvhg9lAKecozjGcG0unLIKa11l";

  # ---------------------------------------------------------------------------
  # ユーザー / Nix
  # ---------------------------------------------------------------------------

  users.users.nanasess = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      # xremap (evdev 読み取り / uinput 書き込み)。セキュリティ上のトレードオフは
      # modules/xremap/default.nix のコメント参照。
      "input"
      "uinput"
    ];
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "nanasess" ];
    # t2linux コミュニティの Hydra。linux-t2 カーネルを自前ビルドしないために使う
    # (https://wiki.t2linux.org/distributions/nixos/faq/#substituter-setup)。
    # nixos-install 時はまだ効かないので --option で同じ値を渡すこと (issue #151)。
    # substituters は既定値 (cache.nixos.org) を置き換えるので明示的に併記する。
    substituters = [
      "https://cache.nixos.org/"
      "https://cache.soopy.moe"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # 最初にインストールした NixOS のリリース。変更しないこと。
  system.stateVersion = "26.05";
}
