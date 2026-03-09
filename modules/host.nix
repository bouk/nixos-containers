{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.bouk.containers;
in

{
  options = {
    bouk.containers = mkOption {
      type = types.attrsOf (
        types.submodule (
          { ... }:
          {
            options = {
              serviceConfig = mkOption {
                type = types.attrs;
                default = { };
                description = "Options to set in the container's systemd service";
              };
              nspawnConfig = mkOption {
                type = types.attrs;
                default = { };
                description = "Options to set in the container's nspawn config";
              };
            };
          }
        )
      );
      default = { };
      description = "Configuration for systemd-nspawn containers";
    };
  };

  config = {
    systemd.services = mapAttrs' (
      name: value:
      nameValuePair "systemd-nspawn@${name}" (mkMerge [
        value.serviceConfig
        {
          wantedBy = [ "multi-user.target" ];

          overrideStrategy = "asDropin";
          serviceConfig = {
            ExecReload = "systemd-run --quiet --machine=%i --collect --no-ask-password --pipe --service-type=exec /nix/var/nix/profiles/system/bin/switch-to-configuration test";
          };

          restartTriggers = [
            (toJSON config.systemd.nspawn.${name})
          ];

          stopIfChanged = false;
        }
      ])
    ) cfg;

    systemd.tmpfiles.rules = flatten (
      mapAttrsToList (name: cfg: [
        "d /nix/var/nix/profiles/per-container/${name} 0755 root root -"
        "d /var/lib/machines/${name} 0755 root root -"
      ]) cfg
    );

    systemd.nspawn = mapAttrs (
      name: value:
      mkMerge [
        value.nspawnConfig
        {
          execConfig = {
            NotifyReady = true;
            Boot = false;
            Parameters = "/nix/var/nix/profiles/system/init";
          };
          filesConfig = {
            BindReadOnly = [
              "/nix/store:/nix/store:rootidmap"
              "/nix/var/nix/profiles/per-container/${name}:/nix/var/nix/profiles:rootidmap"
            ];
          };
        }
      ]
    ) cfg;
  };
}
