#!/bin/bash

# Import util functions, will print a welcome message
echo "${BASH_SOURCE%/*}/common.sh"
[[ ! -f "${BASH_SOURCE%/*}/common.sh" ]] && echo "Util script not found." && exit 1
source "${BASH_SOURCE%/*}/common.sh"

# Check input parameters
if [[ "$#" -ne 2 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device> <mountpoint>"
    exit 0
fi
echo ""

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
mkdir -p "${MOUNT}/home/user"
mount -o subvol=subvolumes/user "${ROOT_DEVICE}" "${MOUNT}/home/user"
mkdir -p "${MOUNT}/home/user/.snapshots"
mount -o subvol=snapshots/user "${ROOT_DEVICE}" "${MOUNT}/home/user/.snapshots"

# Mount btrfs real root directory to /.btrfs
plain "Mounting root btrfs."
mkdir -p "${MOUNT}/.btrfs"
mount "${ROOT_DEVICE}" "${MOUNT}/.btrfs"

# Mount subvolumes which should get excluded from snapper backups
plain "Mounting exclude subvolumes"
mkdir -p "${MOUNT}/var/cache/pacman/pkg"
mount -o subvol=excludes/pkg "${ROOT_DEVICE}" "${MOUNT}/var/cache/pacman/pkg"
mkdir -p "${MOUNT}/var/tmp"
mount -o subvol=excludes/tmp "${ROOT_DEVICE}" "${MOUNT}/var/tmp"
mkdir -p "${MOUNT}/var/log"
mount -o subvol=excludes/log "${ROOT_DEVICE}" "${MOUNT}/var/log"
mkdir -p "${MOUNT}/srv"
mount -o subvol=excludes/srv "${ROOT_DEVICE}" "${MOUNT}/srv"
mkdir -p "${MOUNT}/root/luks"
mount -o subvol=excludes/luks "${ROOT_DEVICE}" "${MOUNT}/root/luks"

# Mount custom user subvolumes
plain "Mounting custom user subvolumes."
while IFS= read -d $'\0' -r directory ; do
    mkdir -p "${MOUNT}/home/user/${directory}"
    mount -o subvol="subvolumes/custom/${directory}" "${ROOT_DEVICE}" "${MOUNT}/home/user/${directory}"
    mkdir -p "${MOUNT}/home/user/${directory}/.snapshots"
    mount -o subvol="snapshots/custom/${directory}" "${ROOT_DEVICE}" "${MOUNT}/home/user/${directory}/.snapshots"
done < <(find "${MOUNT}/.btrfs/snapshots/custom" -maxdepth 1 -mindepth 1 -type d -printf '%f\0')

# Mount efi partition
mkdir -p "${MOUNT}/boot/efi"
mount "${DEVICE}2" "${MOUNT}/boot/efi"
