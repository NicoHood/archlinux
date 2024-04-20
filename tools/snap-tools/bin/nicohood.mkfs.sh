#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "${BASH_SOURCE%/*}/nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device> "
    echo "Creates a partition layout with encrypted btrfs root filesystem."
    echo "Support BIOS and UEFI installations."
    exit 0
fi

# Get parameters
DEVICE="${1}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"

# Create temporary mountpoint
mkdir -p /run/media/root/
MOUNT="$(mktemp -d /run/media/root/mnt.XXXXXXXXXX)"
plain "Creating partitions and filesystems on ${DEVICE} with temporary mountpoint ${MOUNT}."

# Enable luks encryption
if [[ -z "${LUKS:-""}" ]]; then
    read -rp "Encrypt filesystem with Luks? [Y/n]" yesno
    if [[ "${yesno}" != [Yy]"es" && "${yesno}" != [Yy] && -n "${yesno}" ]]; then
        LUKS="n"
    else
        LUKS="y"
    fi
fi
plain "Using luks disk encryption: ${LUKS}."

# Let luks ask for the password if not passed to the script
# TODO ask for the password here, if luks was used
PASSWD_ROOT="${PASSWD_ROOT:-""}"

# Partition disk:
# GPT
# +1M bios boot partition
# +512M EFI /boot/efi partition
# 100% luks root / partition
# NOTE: A custom, smaller root size can be used via environment variable.
# Make sure to run sudo with the -E flag set, to keep the exported variables.
# Afterwards you can use fdisk to add another 4th partition for additional data etc.
ROOT_SIZE="${ROOT_SIZE:-""}"
plain "Partitioning disk."
echo -e "g\nn\n\n\n+1M\nt\n4\nn\n\n\n+512M\nt\n\n1\nn\n\n\n${ROOT_SIZE}\np\nw\n" | fdisk -w always -W always "${DEVICE}"
sync

ROOT_DEVICE="${DEVICE}3"
if [[ "${LUKS}" == "y" ]]; then
    # Warn when random is used, and recommend to start rngd.service
    if [[ "$(systemctl is-active rngd)" != "active" ]]; then
        warning "No rngd service running. Creating crypto disks may take a very long time."
        plain "Run: 'sudo pacman -S rng-tools && sudo systemctl enable --now rngd.service'"
    fi

    # Create cryptodisks
    warning "For better security overwrite the disk with random bytes first."
    plain "Creating and opening root luks container"
    if [[ -z "${PASSWD_ROOT}" ]]; then
        until cryptsetup luksFormat --type luks2 --pbkdf argon2id -c aes-xts-plain64 -s 512 -h sha512 --use-random "${DEVICE}3"
        do
            error "Please enter a correct Luks password."
        done
    else
        echo "${PASSWD_ROOT}" | cryptsetup luksFormat --type luks1 -c aes-xts-plain64 -s 512 -h sha512 --use-random "${DEVICE}3"
    fi

    # Open cryptodisks
    LUKS_UUID="$(blkid "${DEVICE}3" -o value -s UUID)"
    if [[ -z "${PASSWD_ROOT}" ]]; then
        cryptsetup luksOpen "${DEVICE}3" "${LUKS_UUID}" || die "Error opening Luks."
    else
        echo "${PASSWD_ROOT}" | cryptsetup luksOpen "${DEVICE}3" "${LUKS_UUID}"
    fi
    ROOT_DEVICE="/dev/mapper/${LUKS_UUID}"
fi

mkfs.btrfs -f "${ROOT_DEVICE}"
sync
mount "${ROOT_DEVICE}" "${MOUNT}"
chmod 700 "${MOUNT}"

# Create structure subvolumes
btrfs subvolume create "${MOUNT}/subvolumes"
btrfs subvolume create "${MOUNT}/snapshots"
btrfs subvolume create "${MOUNT}/backup"

# Create top level subvolumes
btrfs subvolume create "${MOUNT}/subvolumes/root"
mkdir -m 750 "${MOUNT}/subvolumes/root/root"
btrfs subvolume create "${MOUNT}/subvolumes/home"
btrfs subvolume create "${MOUNT}/subvolumes/data"
btrfs subvolume create "${MOUNT}/subvolumes/pkg"
btrfs subvolume create "${MOUNT}/subvolumes/tmp"
chmod 1777 "${MOUNT}/subvolumes/tmp"

# Create subvolumes for snapshots
btrfs subvolume create "${MOUNT}/snapshots/root"
btrfs subvolume create "${MOUNT}/snapshots/home"
btrfs subvolume create "${MOUNT}/snapshots/data"

# Create subvolumes untracked by snapper
btrfs subvolume create "${MOUNT}/luks"
chmod 000 "${MOUNT}/luks"

# Add luks key to luks directory
if [[ "${LUKS}" == "y" ]]; then
    dd bs=512 count=4 iflag=fullblock if=/dev/random of="${MOUNT}/luks/crypto_keyfile.bin"
    sync
    chmod 000 "${MOUNT}/luks/crypto_keyfile.bin"
    if [[ -z "${PASSWD_ROOT}" ]]; then
        cryptsetup luksAddKey "${DEVICE}3" "${MOUNT}/luks/crypto_keyfile.bin"
    else
        echo "${PASSWD_ROOT}" | cryptsetup luksAddKey "${DEVICE}3" "${MOUNT}/luks/crypto_keyfile.bin"
    fi
fi

# Add version identifier for snap-tools as text file.
echo "${VERSION}" > "${MOUNT}/version.txt"

# Format efi partition
mkfs.fat -F32 -s 1 -S 4096 -v "${DEVICE}2"

# Unmount btrfs filesystem
umount "${MOUNT}"
if [[ "${LUKS}" == "y" ]]; then
    cryptsetup luksClose "${LUKS_UUID}"
fi

msg "Creating filesystem on for ${DEVICE} with temporary mountpoint ${MOUNT} succeeded."
