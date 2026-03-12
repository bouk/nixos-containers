{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.bouk.containers;

  containersWithDeployGroup = filterAttrs (_: value: value.deployGroup != "root") cfg;
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
              deployGroup = mkOption {
                type = types.str;
                default = "root";
                description = "Group allowed to deploy this container (write profile dir + restart service)";
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
    assertions = mapAttrsToList (name: value: {
      assertion = hasAttr value.deployGroup config.users.groups;
      message = "bouk.containers.${name}.deployGroup: group \"${value.deployGroup}\" does not exist in users.groups";
    }) containersWithDeployGroup;

    networking.useNetworkd = true;

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

    systemd.tmpfiles.rules = flatten ([
      "d /nix/var/nix/profiles/per-container 0755 root root -"
    ] ++ mapAttrsToList (name: value: [
        "d /nix/var/nix/profiles/per-container/${name} 0775 root ${value.deployGroup} -"
        "d /var/lib/machines/${name} 0755 root root -"
      ]) cfg
    );

    security.polkit.enable = mkIf (containersWithDeployGroup != { }) true;

    security.polkit.extraConfig = concatStrings (
      mapAttrsToList (name: value: ''
        // Allow the ${value.deployGroup} group to restart the ${name} container
        // (used by the deploy-container script after updating the system profile)
        polkit.addRule(function(action, subject) {
          if (action.id === "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") === "systemd-nspawn@${name}.service" &&
              subject.isInGroup(${builtins.toJSON value.deployGroup})) {
            return polkit.Result.YES;
          }
        });
        // Allow the ${value.deployGroup} group to open a shell inside the ${name} container
        // (via machinectl shell / machinectl login)
        polkit.addRule(function(action, subject) {
          if ((action.id === "org.freedesktop.machine1.shell" ||
               action.id === "org.freedesktop.machine1.login" ||
               action.id === "org.freedesktop.machine1.manage-machines") &&
              action.lookup("machine") === ${builtins.toJSON name} &&
              subject.isInGroup(${builtins.toJSON value.deployGroup})) {
            return polkit.Result.YES;
          }
        });
      '') containersWithDeployGroup
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
