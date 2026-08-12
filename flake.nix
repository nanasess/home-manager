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
  };

  outputs = { self, nixpkgs, home-manager, nixgl, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      homeConfigurations = {
        "nanasess@wsl-gentoo" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [ ./home.nix ./hosts/wsl-gentoo.nix ./modules/onedrive.nix ./modules/portage.nix ./modules/yaskkserv2.nix ./modules/locale-eaw ./modules/emacs ./modules/zsh ./modules/ghostty ./modules/wakatime ./modules/claude ];
        };
        "nanasess@ubuntu" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [
            ./home.nix
            ./hosts/ubuntu.nix
            ./modules/onedrive.nix
            ./modules/yaskkserv2.nix
            ./modules/t2-suspend
            ./modules/bluetooth-audio
            ./modules/emacs
            ./modules/zsh
            ./modules/ghostty
            ./modules/wakatime
            ./modules/claude
            {
              nixGL.packages = nixgl.packages;
            }
          ];
        };
      };

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt
      );
    };
}
