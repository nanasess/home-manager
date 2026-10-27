{
  description = "Home Manager configuration";

  inputs = {
    # k-2 の linux-t2 は T2 パッチを当てたカーネル。upstream の nixos-hardware は nixpkgs の
    # linux_6_18 にパッチを当てるため、nixpkgs を上げると linux-config で落ちることがあった
    # (nixos-hardware#2027)。現在はカーネルのバージョンを固定する fork に向けている
    # (下の nixos-hardware)。上げる前に kernel.configfile をビルドし、linux-t2 が
    # cache.soopy.moe にあるかも確認する (flake-update-pr Skill の手順 3)。
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # T2 Mac (k-2) 用: linux-t2 カーネル / apple-bce / WiFi・BT ファームウェア。
    # upstream の apple/t2 は nixpkgs のカーネル更新でパッチが当たらなくなるため
    # (nixos-hardware#2027)、カーネルのバージョンを固定する PR #1934 の head に一時的に向ける。
    # force-push が多いのでブランチ名ではなくコミットで固定する。#1934 がマージされたら
    # github:NixOS/nixos-hardware に戻す (issue #227)。
    nixos-hardware = {
      url = "github:soopyc/nixos-hardware/7082b484432124bd8d53790a11b808429b73fb6b";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # azure-cli だけ fabric が壊れる前の nixos-unstable (2026-10-17) から取る一時措置。
    # invoke 3.0 への更新で fabric が broken になり azure-cli が評価できない
    # (NixOS/nixpkgs#575989)。修正 PR NixOS/nixpkgs#576874 が nixos-unstable に
    # 入ったら、この input と azureCliPinModule を削除する。
    nixpkgs-azure-cli.url = "github:nixos/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";
    # WSL2 上の NixOS (wsl-nixos、Issue #183)。
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixgl, nixos-hardware, nixpkgs-azure-cli, nixos-wsl, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # azure-cli を nixpkgs-azure-cli から取る (inputs のコメント参照)。home.nix と一緒に
      # 全ホストの home-manager に読み込む。
      azureCliPinModule = {
        nixpkgs.overlays = [
          (final: prev: {
            azure-cli = nixpkgs-azure-cli.legacyPackages.${prev.stdenv.hostPlatform.system}.azure-cli;
          })
        ];
      };

      # GNOME デスクトップを持つホスト (ubuntu / k-2) 共通の home-manager モジュール。
      gnomeHomeModules = [
        ./home.nix
        azureCliPinModule
        ./modules/onedrive.nix
        ./modules/yaskkserv2.nix
        ./modules/bluetooth-audio
        ./modules/walker
        ./modules/xremap
        ./modules/emacs
        ./modules/zsh
        ./modules/ghostty
        ./modules/wakatime
        ./modules/claude
      ];
    in
    {
      homeConfigurations = {
        "nanasess@wsl-gentoo" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [ ./home.nix azureCliPinModule ./hosts/wsl-gentoo.nix ./modules/wsl ./modules/onedrive.nix ./modules/portage.nix ./modules/yaskkserv2.nix ./modules/emacs ./modules/zsh ./modules/ghostty ./modules/wakatime ./modules/claude ];
        };
        "nanasess@ubuntu" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = gnomeHomeModules ++ [
            ./hosts/ubuntu.nix
            ./modules/t2-suspend
            ./modules/ibus-skk/ubuntu.nix
            {
              nixGL.packages = nixgl.packages;
            }
          ];
        };
      };

      # NixOS ホスト。home-manager は NixOS モジュールとして読み込む (issue #151)。
      nixosConfigurations = {
        # Intel MacBook Pro 13" 2020 (MacBookPro16,2, T2)。Ubuntu 24.04 からの移行先。
        "k-2" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            nixos-hardware.nixosModules.apple-t2
            ./hosts/k-2/configuration.nix
            home-manager.nixosModules.home-manager
            {
              # /etc/profiles/per-user/<user> にパッケージを置く。home.nix 側の
              # パス参照は config.home.profileDirectory を使うこと (~/.nix-profile 直書き不可)。
              home-manager.useUserPackages = true;
              # home-manager 管理下に入れるパスに通常ファイルが既にあると activation が
              # 「would be clobbered」で中断し、その世代のリンクが全て入らない
              # (home-manager-nanasess.service の失敗は nixos-rebuild では見落としやすい)。
              # k-2 では xdg-user-dirs-update が作った ~/.config/user-dirs.dirs で実際に
              # 起きた (PR #160)。既存ファイルを <name>.hm-backup に退避して続行させる。
              home-manager.backupFileExtension = "hm-backup";
              # useGlobalPkgs は使わない: home.nix の nixpkgs.config (allowUnfreePredicate)
              # が無効化されて評価エラーになるため。
              home-manager.users.nanasess.imports = gnomeHomeModules ++ [
                ./hosts/k-2/home.nix
                ./modules/ibus-skk
              ];
            }
          ];
        };

        # WSL2 上の NixOS (NixOS-WSL)。wsl-gentoo からの移行先 (issue #183)。
        # 初回導入用の tarball は config.system.build.tarballBuilder で作る (README)。
        "wsl-nixos" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/wsl-nixos/configuration.nix
            home-manager.nixosModules.home-manager
            {
              # 各設定の理由は k-2 と同じ。
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.users.nanasess.imports = [
                ./home.nix
                azureCliPinModule
                ./hosts/wsl-nixos/home.nix
                ./modules/wsl
                ./modules/onedrive.nix
                ./modules/yaskkserv2.nix
                ./modules/emacs
                ./modules/zsh
                ./modules/ghostty
                ./modules/wakatime
                ./modules/claude
              ];
            }
          ];
        };
      };

      # 自作 derivation は packages にも出して CI (nix flake check) でビルド検証する。
      packages = forAllSystems (system: {
        ibus-skk = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/ibus-skk.nix { };
        yaskkserv2 = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/yaskkserv2.nix { };
        mew = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/mew.nix { };
        # unfree なので legacyPackages (allowUnfree 無し) では評価時点で弾かれる。
        # この 1 件だけ許可した nixpkgs を import する。`nix build .#chatgpt` で単体ビルドできる。
        chatgpt =
          (import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "chatgpt";
          }).callPackage ./pkgs/chatgpt { };
      });

      # mise の php プラグイン (ソースビルド) 用のビルド環境。NixOS には FHS 前提の
      # ツールチェーンが無いので `nix develop .#php-build -c mise install php@8.5` で使う
      # (README「mise PHP のセットアップ」、shells/php-build.nix)。
      devShells = forAllSystems (system: {
        php-build = nixpkgs.legacyPackages.${system}.callPackage ./shells/php-build.nix { };
      });

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );
    };
}
