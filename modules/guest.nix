{ lib, ... }:
{
  # This is a container config
  boot.isNspawnContainer = true;

  # Disable nix inside the container. The container's system profile is managed by the host
  nix.enable = lib.mkDefault false;

  # Received from systemd-nspawn
  networking.hostName = lib.mkDefault "";

  # Use systemd-networkd and systemd-resolved
  networking.resolvconf.enable = false;
  networking.useHostResolvConf = false;
  networking.useNetworkd = true;

  # Remove default network config, use systemd-networkd virtual container networking
  networking.useDHCP = false;
}
