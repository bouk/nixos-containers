{ pkgs }:
pkgs.writeShellApplication {
  name = "nixos-deploy-container";
  runtimeInputs = with pkgs; [ openssh nix ];
  text = builtins.readFile ./script.sh;
}
