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
          modules = [ ./home.nix ./hosts/wsl-gentoo.nix ./modules/onedrive.nix ./modules/portage.nix ./modules/yaskkserv2.nix ./modules/locale-eaw ./modules/emacs ./modules/zsh ./modules/ghostty ./modules/wakatime ./modules/claude ];
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
      });

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );
    };
}
