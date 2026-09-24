# NixOS ホスト (k-2 / wsl-nixos) 共通のシステム設定。
# ホスト固有の unfree 許可 (nixpkgs.config.allowUnfreePredicate) は関数で
# マージできないため各ホストに置く。1password / 1password-cli を許可すること。
{ pkgs, ... }:

{
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
  # home.nix / hosts/<host>/home.nix から参照する。
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
}
