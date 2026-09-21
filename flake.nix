{
  description = "Home Manager configuration";

  inputs = {
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
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixgl, nixos-hardware, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # GNOME デスクトップを持つホスト (ubuntu / k-2) 共通の home-manager モジュール。
      gnomeHomeModules = [
        ./home.nix
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
          modules = [ ./home.nix ./hosts/wsl-gentoo.nix ./modules/onedrive.nix ./modules/portage.nix ./modules/yaskkserv2.nix ./modules/emacs ./modules/zsh ./modules/ghostty ./modules/wakatime ./modules/claude ];
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
