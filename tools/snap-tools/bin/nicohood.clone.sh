#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device>"
    echo "Can be used to clone a running system to a new, empty disk."
    exit 0
fi

# Get parameters
DEVICE="${1}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"

# Check if snapper is installed and configured
check_dependency snapper || die "Please install snapper and set it up first!"

# Take new snapshots, then backup
systemctl start --wait snapper-timeline.service
nicohood.restore "/.btrfs/snapshots" "${DEVICE}"
