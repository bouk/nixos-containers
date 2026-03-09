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

      overlays.default = final: prev: {
        nixos-deploy-container = final.callPackage ./nixos-deploy-container/package.nix { };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; overlays = [ self.overlays.default ]; };
        in
        {
          nixos-deploy-container = pkgs.nixos-deploy-container;
          default = pkgs.nixos-deploy-container;
        }
      );
    };
}
