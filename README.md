# nixos-containers

Imperatively deploy declarative NixOS containers via `systemd-nspawn`.

Containers share the host's Nix store (read-only via bind mount) and have their system profile managed by the host at `/nix/var/nix/profiles/per-container/<name>/system`.

## How it works

- The **host module** (`bouk.containers`) creates `systemd-nspawn@.service` units and the required directory structure for each container.
- The **guest module** sets up the system config for containerization and enables `systemd-networkd` and `systemd-resolved`.
- The **`nixos-deploy-container`** script evaluates a container's system on your local machine, copies the derivation to the target host, builds it into a profile, and activates it.

On reload, the running container's switches to the new configuration without a full restart (equivalent to `nixos-rebuild switch`). A full restart only happens when the nspawn or service config changes.

## Setup

### 1. Add to your flake inputs

```nix
inputs = {
  bouk-nixos-containers.url = "github:bouk/nixos-containers";
};
```

### 2. Configure the host

Import the host module in your host NixOS configuration and declare containers:

```nix
{ inputs, ... }:
{
  imports = [ inputs.bouk-nixos-containers.nixosModules.host ];

  bouk.containers = {
    mycontainer = {
      # Optional: override the systemd service unit
      serviceConfig = { };

      # Optional: override the systemd.nspawn unit
      nspawnConfig = {
        networkConfig.VirtualEthernet = false; # Use host networking
      };
    };
  };
}
```

Each declared container gets:
- A `systemd-nspawn@<name>` service started on boot
- `/nix/var/nix/profiles/per-container/<name>/` for the system profile
- `/var/lib/machines/<name>/` as the container root

> **Note:** Until [NixOS/nixpkgs#498177](https://github.com/NixOS/nixpkgs/pull/498177) is merged, you also need to allow DHCP on the virtual ethernet interfaces so containers can get an address (unless you're using host networking):
>
> ```nix
> networking.firewall.interfaces."ve-+" = {
>   allowedUDPPorts = [ 67 ];
> };
> ```

### 3. Configure the guest (container)

Import the guest module in the container's NixOS configuration:

```nix
{ inputs, ... }:
{
  imports = [ inputs.bouk-nixos-containers.nixosModules.guest ];
}
```

The guest module:
- Sets `boot.isNspawnContainer = true`
- Disables Nix (the host manages the profile)
- Enables `systemd-networkd` and `systemd-resolved`

### 4. Add your container to `nixosConfigurations`

```nix
nixosConfigurations = {
  mycontainer = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./containers/mycontainer.nix
    ];
  };
};
```

## Example

This example sets up a container named `mycontainer` that serves "hello world!" via nginx, with the host proxying to it.

### Guest configuration (`containers/mycontainer.nix`)

```nix
{ inputs, ... }:
{
  imports = [ inputs.bouk-nixos-containers.nixosModules.guest ];

  services.nginx = {
    enable = true;
    virtualHosts."mycontainer" = {
      locations."/" = {
        return = "200 'hello world!'";
        extraConfig = "add_header Content-Type text/plain;";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];
}
```

### Host configuration

```nix
{ inputs, ... }:
{
  imports = [ inputs.bouk-nixos-containers.nixosModules.host ];

  bouk.containers.mycontainer = { };

  services.nginx = {
    enable = true;
    virtualHosts."example.com" = {
      locations."/" = {
        proxyPass = "http://mycontainer";
      };
    };
  };
}
```

## Deploying

Run `nixos-deploy-container` from your flake directory:

```
nixos-deploy-container [-v] <machine> <target> [container]
```

| Argument | Description |
|---|---|
| `machine` | The `nixosConfigurations` attribute name for the container |
| `target` | SSH destination of the host machine (e.g. `root@myserver`) |
| `container` | Container name on the host (defaults to `machine`) |

**Example:**

```bash
# Deploy "mycontainer" config to the container named "mycontainer" on myserver
nixos-deploy-container mycontainer root@myserver

# Deploy "mycontainer" config to a differently-named container
nixos-deploy-container mycontainer root@myserver mycontainer-prod
```

Use `-v` for verbose output.

### Running without installing

```bash
nix run github:bouk/nixos-containers -- mycontainer root@myserver
```

### Get a shell in the container

```bash
ssh -t root@myserver -- systemd-run -tPGM mycontainer -- /run/current-system/sw/bin/bash
```
