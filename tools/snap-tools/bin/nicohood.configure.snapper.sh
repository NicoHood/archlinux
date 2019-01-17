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
    if [[ -e "/etc/snapper/configs/${CONFIG}" ]];then
        echo "Warning: Config already exists: '${CONFIG}'"
        return
    fi
    echo "Creating config '${CONFIG}'"
    umount "${CONFIG_PATH}/.snapshots"
    rm "${CONFIG_PATH}/.snapshots" -r
    snapper -c "${CONFIG}" create-config "${CONFIG_PATH}"
    btrfs subvolume delete "${CONFIG_PATH}/.snapshots"
    mkdir "${CONFIG_PATH}/.snapshots"
    mount -a
}

# Create base snapshot configs
# NOTE: /var/tmp and /var/cache/pacman/pkg will not be backed up, even if technically possible.
create_config root /
create_config home /home
create_config user /home/user
create_config log /var/log
create_config srv /srv

# Do not use timeline snapshot for the log directory. Only back it up using snap-sync.
# TODO if this is set, then the restore script wont find any snapshot as backup and will fail.
#snapper -c log set-config TIMELINE_CREATE="no"

# Create custom snapshot configs
while IFS= read -r -d '' config
do
    create_config "${config}" "/home/user/${config}"
done < <(find "/.btrfs/snapshots/custom" -maxdepth 1 -mindepth 1 -type d -printf '%f\0')

# Enable services
systemctl enable --now snapper-boot.timer
systemctl enable --now snapper-cleanup.timer
systemctl enable --now snapper-timeline.timer

echo "Configured snapper successful. Please set your snapshot interval for all configs properly!"
