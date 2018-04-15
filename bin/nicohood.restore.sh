#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 2 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Can be used to restore a backup."
    echo "Usage: $(basename "$0") <device> <backup>"
    exit 0
fi

# Get parameters
DEVICE="${1}"
BACKUP="${2}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"
[[ ! -d "${BACKUP}" ]] && die "Not a valid backup directory: '${BACKUP}'"

# Default settings
PASSWD_ROOT="${PASSWD_ROOT:-root}"
LUKS="${LUKS:-y}"
INTERACTIVE="${INTERACTIVE:-y}"

# User settings dialog
if [[ "${INTERACTIVE}" == y ]]; then
    msg "Settings:"
    read -p "Use luks encryption? " -e -i "${LUKS}" LUKS
fi

# Find custom subvolumes
SUBVOLUMES=()
while IFS= read -r -d '' subvolume
do
    SUBVOLUMES+=("${subvolume}")
done < <(find "${BACKUP}/custom" -maxdepth 1 -mindepth 1 -type d -printf '%f\0')

# Create filesystems
msg2 "Partition the disks"
PASSWD_ROOT="${PASSWD_ROOT}" LUKS="${LUKS}" nicohood.mkfs "${DEVICE}" "${SUBVOLUMES[@]}"

# Create temporary mountpoint and mount bare btrfs filesystem
msg2 "Mount the file systems"
mkdir -p /run/media/root/
MOUNT="$(mktemp -d /run/media/root/mnt.XXXXXXXXXX)"
ROOT_DEVICE="${DEVICE}3"
if cryptsetup isLuks "${DEVICE}3"; then
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
mount "${ROOT_DEVICE}" "${MOUNT}"

function copy_subvolume()
{
    config="${1}"
    SRC_DIR="$(find "${BACKUP}/${config}/" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -n 1)/snapshot"
    msg2 "Transfering snapshot '${SRC_DIR}'..."
    btrfs send "${SRC_DIR}" | btrfs receive "${MOUNT}/subvolumes/"
    btrfs subvolume delete "${MOUNT}/subvolumes/${config}"
    btrfs subvolume snapshot "${MOUNT}/subvolumes/snapshot" "${MOUNT}/subvolumes/${config}"
    btrfs subvolume delete "${MOUNT}/subvolumes/snapshot"
}

# Copy subvolumes to destination
copy_subvolume root
copy_subvolume home
copy_subvolume user
for config in "${SUBVOLUMES[@]}"
do
    copy_subvolume "custom/${config}"
done

# Remount with real filesystem mapping
umount -R "${MOUNT}"
if [[ "${LUKS}" == "y" ]]; then
    cryptsetup luksClose "${LUKS_UUID}"
fi
PASSWD_ROOT="${PASSWD_ROOT}" nicohood.mount "${DEVICE}" "${MOUNT}"

# Backup and regenerate fstab
cp "${MOUNT}"/etc/fstab "${MOUNT}"/etc/fstab.bak
genfstab -U "${MOUNT}" > "${MOUNT}"/etc/fstab

# Install Grub for Efi and BIOS. Efi installation will only work if you booted with efi.
if [[ "${LUKS}" == "y" ]]; then
    cp "${MOUNT}/etc/default/grub" "${MOUNT}/etc/default/grub.bak"
    sed -i "s#cryptdevice=UUID=.*:cryptroot#cryptdevice=UUID=${LUKS_UUID}:cryptroot#" \
        "${MOUNT}/etc/default/grub"
    sed -i '/GRUB_ENABLE_CRYPTODISK=y/s/^#//g' "${MOUNT}/etc/default/grub"
fi
arch-chroot "${MOUNT}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE}"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/boot/bootx64.efi"

# Generate initramfs
arch-chroot "${MOUNT}" /bin/bash -c "mkinitcpio -P"
sync

msg "Restore completed."
