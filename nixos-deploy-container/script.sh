#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail
shopt -s inherit_errexit

tmpdir=$(mktemp -d)

cleanup() {
    for ctrl in "$tmpdir"/ssh-*; do
        ssh -o ControlPath="$ctrl" -O exit dummyhost 2>/dev/null || true
    done
    rm -rf "$tmpdir"
}
trap cleanup EXIT

nix_flags=()
while getopts ":v" opt; do
    case $opt in
        v)
            set -x
            nix_flags+=(--verbose -L)
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

if [ $# -lt 2 ]; then
  echo "Usage: deploy-container [-v] <machine> <target> [container]" >&2
  exit 1
fi

machine=$1
target=$2
container=${3:-$machine}

SSHOPTS=(-C -o ControlMaster=auto -o "ControlPath=$tmpdir/ssh" -o ControlPersist=60 -o ConnectTimeout=10)
SSH_COMMAND="ssh ${SSHOPTS[*]}"

# Open up SSH connection
$SSH_COMMAND "$target" -- echo 1 &>/dev/null &

echo "== Calculating system" >&2
drv=$(nix eval --raw ".#nixosConfigurations.\"$machine\".config.system.build.toplevel.drvPath" --show-trace "${nix_flags[@]}")

echo "== Copying build to $target" >&2
output="$drv^*"
NIX_SSHOPTS="${SSHOPTS[*]}" nix copy --derivation --to "ssh-ng://$target" "$output"

profile="/nix/var/nix/profiles/per-container/$container/system"

echo "== Building $machine" >&2
$SSH_COMMAND "$target" -- "nix --extra-experimental-features \"nix-command flakes\" build ${nix_flags[*]} --profile $profile \"$output\""

echo "== Activating container $container" >&2
$SSH_COMMAND "$target" -- "systemctl reload-or-restart systemd-nspawn@$container"
