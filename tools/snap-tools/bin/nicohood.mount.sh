#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 2 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device> <mountpoint>"
    echo "Mounts a disk partitioned and formatted with the specific layout."
    exit 0
fi

# Get parameters
DEVICE="${1}"
MOUNT="${2}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"
[[ ! -d "${MOUNT}" ]] && die "Not a valid mountpoint directory: '${MOUNT}'"
mountpoint -q "${MOUNT}" && die "Mountpoint ${MOUNT} is already in use."

# Let luks ask for the password if not passed to the script
PASSWD_ROOT="${PASSWD_ROOT:-""}"
ROOT_DEVICE="${DEVICE}3"
if cryptsetup isLuks "${ROOT_DEVICE}"; then
    # Open cryptodisks
    LUKS_UUID="$(blkid "${DEVICE}3" -o value -s UUID)"
    [[ -e "/dev/mapper/${LUKS_UUID}" ]] && die "Luks device ${LUKS_UUID} already opened."
    if [[ -z "${PASSWD_ROOT}" ]]; then
        cryptsetup luksOpen "${DEVICE}3" "${LUKS_UUID}" || die "Error opening Luks."
    else
        echo "${PASSWD_ROOT}" | cryptsetup luksOpen "${DEVICE}3" "${LUKS_UUID}"
    fi
    ROOT_DEVICE="/dev/mapper/${LUKS_UUID}"
fi

# Mount snapper tracked root and home subvolume to the mountpoint
plain "Mounting default subvolumes and snapshots."
mount -o subvol=subvolumes/root "${ROOT_DEVICE}" "${MOUNT}"
mkdir -p "${MOUNT}/.snapshots"
mount -o subvol=snapshots/root "${ROOT_DEVICE}" "${MOUNT}/.snapshots"

mkdir -p "${MOUNT}/home"
mount -o subvol=subvolumes/home "${ROOT_DEVICE}" "${MOUNT}/home"
mkdir -p "${MOUNT}/home/.snapshots"
mount -o subvol=snapshots/home "${ROOT_DEVICE}" "${MOUNT}/home/.snapshots"

mkdir -p "${MOUNT}/data"
mount -o subvol=subvolumes/data "${ROOT_DEVICE}" "${MOUNT}/data"
mkdir -p "${MOUNT}/data/.snapshots"
mount -o subvol=snapshots/data "${ROOT_DEVICE}" "${MOUNT}/data/.snapshots"

mkdir -p "${MOUNT}/var/cache/pacman/pkg"
mount -o subvol=subvolumes/pkg "${ROOT_DEVICE}" "${MOUNT}/var/cache/pacman/pkg"

mkdir -p "${MOUNT}/var/tmp"
mount -o subvol=subvolumes/tmp "${ROOT_DEVICE}" "${MOUNT}/var/tmp"

# Mount btrfs real root directory to /.btrfs
# TODO chmod 700 /.btrfs, as rsync overrides this setting. Or the mount command should add this as mount option?
plain "Mounting root btrfs."
mkdir -p "${MOUNT}/.btrfs"
mount "${ROOT_DEVICE}" "${MOUNT}/.btrfs"

# Mount backup and luks subvolume
mkdir -p "${MOUNT}/backup"
mount -o subvol=backup "${ROOT_DEVICE}" "${MOUNT}/backup"
mkdir -p "${MOUNT}/root/luks"
mount -o subvol=luks "${ROOT_DEVICE}" "${MOUNT}/root/luks"

# Mount efi partition
mkdir -p "${MOUNT}/boot/efi"
mount "${DEVICE}2" "${MOUNT}/boot/efi"
