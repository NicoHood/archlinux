#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Can be used to restore clone a running system."
    echo "Usage: $(basename "$0") <device>"
    exit 0
fi

# Get parameters
DEVICE="${1}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"

# Take new snapshots, then backup
systemctl start --wait snapper-timeline.service
nicohood.restore "${DEVICE}" "/.btrfs/snapshots"
