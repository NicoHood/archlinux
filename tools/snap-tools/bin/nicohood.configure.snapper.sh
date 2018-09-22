#!/bin/bash

# Stop on error, simple version
set -x
set -e
set -u

# Check if run as root
[[ "${EUID}" -ne 0 ]] && echo "You must be a root user." && exit 1

# Install snapper
pacman -S --needed --asexplicit snapper snap-pac snap-sync

function create_config()
{
    CONFIG="${1}"
    CONFIG_PATH="${2}"
    umount "${CONFIG_PATH}/.snapshots"
    rm "${CONFIG_PATH}/.snapshots" -r
    snapper -c "${CONFIG}" create-config "${CONFIG_PATH}"
    btrfs subvolume delete "${CONFIG_PATH}/.snapshots"
    mkdir "${CONFIG_PATH}/.snapshots"
    mount -a
}

# Create base snapshot configs
create_config root /
create_config home /home
create_config user /home/user

# Create custom snapshot configs
while IFS= read -r -d '' config
do
    create_config "${config}" "/home/user/${config}"
done < <(find "/.btrfs/snapshots/custom" -maxdepth 1 -mindepth 1 -type d -printf '%f\0')

# Enable services
systemctl enable --now snapper-boot.timer
systemctl enable --now snapper-cleanup.timer
systemctl enable --now snapper-timeline.timer
