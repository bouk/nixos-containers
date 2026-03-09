{
  description = "Imperatively deploy declarative NixOS containers via systemd-nspawn";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosModules = {
        host = import ./modules/host.nix;
        guest = import ./modules/guest.nix;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          nixos-deploy-container = pkgs.callPackage ./nixos-deploy-container/package.nix { };
          default = self.packages.${system}.nixos-deploy-container;
        }
      );
    };
}
