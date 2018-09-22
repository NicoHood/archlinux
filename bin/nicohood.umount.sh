#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 2 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device>"
    echo "Unmounts a disk partitioned and formatted with the specific layout."
    exit 0
fi

# Get parameters
DEVICE="${1}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"

# Check if device is a luks device
ROOT_DEVICE="${DEVICE}3"
LUKS_UUID=""
if cryptsetup isLuks "${ROOT_DEVICE}"; then
    LUKS_UUID="$(blkid "${DEVICE}3" -o value -s UUID)"
    ROOT_DEVICE="/dev/mapper/${LUKS_UUID}"
fi

# Unmount filesystem
umount -R "$(findmnt "${ROOT_DEVICE}" -f -n -o target)"

# Close luks container
if [[ "${LUKS_UUID}" != "" ]]; then
    cryptsetup luksClose "${LUKS_UUID}"
fi
