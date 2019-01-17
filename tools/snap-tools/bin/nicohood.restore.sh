#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -ne 2 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <backup source> <destination blockdevice>"
    echo "Can be used to restore a backup to a new, empty disk."
    exit 0
fi

# Get parameters
BACKUP="${1}"
DEVICE="${2}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"
[[ ! -d "${BACKUP}" ]] && die "Not a valid backup directory: '${BACKUP}'"
[[ ! -d "${BACKUP}/custom" ]] && die "Missing custom directory: '${BACKUP}/custom'"

# Default settings
LUKS="${LUKS:-y}"
INTERACTIVE="${INTERACTIVE:-y}"

# User settings dialog
if [[ "${INTERACTIVE}" == y ]]; then
    msg "Settings:"
    read -rp "Use luks encryption for new disk? " -e -i "${LUKS}" LUKS

    # Ask for password
    if [[ "${LUKS}" == "y" ]]; then
        read -rsp "Please enter your luks password. If none was entered, the default password gets used." PASSWD_ROOT
    fi
fi

# Default password if none was entered
PASSWD_ROOT="${PASSWD_ROOT:-root}"

# Find custom subvolumes used in the backup
SUBVOLUMES=()
while IFS= read -r -d '' subvolume
do
    SUBVOLUMES+=("${subvolume}")
done < <(find "${BACKUP}/custom" -maxdepth 1 -mindepth 1 -type d -printf '%f\0')

# Create filesystems
msg2 "Partition the disks"
PASSWD_ROOT="${PASSWD_ROOT}" LUKS="${LUKS}" nicohood.mkfs "${DEVICE}" "${SUBVOLUMES[@]}"

# Create temporary mountpoint and mount btrfs filesystem
msg2 "Mount the file systems"
mkdir -p /run/media/root/
MOUNT="$(mktemp -d /run/media/root/mnt.XXXXXXXXXX)"
PASSWD_ROOT="${PASSWD_ROOT}" nicohood.mount "${DEVICE}" "${MOUNT}"

function copy_subvolume()
{
    config="${1}"
    if [[ ! -d "${BACKUP}/${config}" ]]; then
        warning "Backup directory '${BACKUP}/${config}' does not exist, skipping subvolume."
        return
    fi
    SRC_DIR="$(find "${BACKUP}/${config}/" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -n 1)/snapshot"

    # Transfer snapshots. Saved snapshot is readonly and
    # must be snapshotted again with write enabled.
    msg2 "Transferring snapshot '${SRC_DIR}'..."
    btrfs send "${SRC_DIR}" | btrfs receive "${MOUNT}/.btrfs/subvolumes/"

    # Move the initial subvolume, do not delete it.
    # It must be moved, as its currently mounted and deletion
    # would cause the mountpoint to function properly/disappear.
    # We can delete them after a new remount.
    mv "${MOUNT}/.btrfs/subvolumes/${config}" "${MOUNT}/.btrfs/backup/old/${config}"
    btrfs subvolume snapshot "${MOUNT}/.btrfs/subvolumes/snapshot" "${MOUNT}/.btrfs/subvolumes/${config}"

    # Delete the readonly snapshot of the transferrd snapshots.
    # They are not required, as they represent the new system subvolumes.
    btrfs subvolume delete "${MOUNT}/.btrfs/subvolumes/snapshot"
}

# Copy subvolumes to destination
btrfs subvolume create "${MOUNT}/.btrfs/backup/old"
btrfs subvolume create "${MOUNT}/.btrfs/backup/old/custom"
copy_subvolume root
copy_subvolume home
copy_subvolume user
copy_subvolume log
copy_subvolume srv
for config in "${SUBVOLUMES[@]}"
do
    copy_subvolume "custom/${config}"
done

# Remount with real filesystem mapping, of the new transferred backup
nicohood.umount "${DEVICE}"
PASSWD_ROOT="${PASSWD_ROOT}" nicohood.mount "${DEVICE}" "${MOUNT}"

# Delete intitial/empty subvolumes created by the mkfs command.
# Those are not required anymore.
# Note: The rm command will only work with recent kernels (4.18+) that
# introduced deleting multiple nested subvolumes with user privilegs.
# http://lkml.iu.edu/hypermail/linux/kernel/1806.0/02095.html
rm -rf "${MOUNT}/backup/old"

# Backup and regenerate fstab
cp "${MOUNT}"/etc/fstab "${MOUNT}"/etc/fstab.bak"$(ls "${MOUNT}"/etc/fstab.bak* | wc -l)"
genfstab -U "${MOUNT}" > "${MOUNT}"/etc/fstab

# Install Grub for Efi and BIOS. Efi installation will only work if you booted with efi.
if [[ "${LUKS}" == "y" ]]; then
    LUKS_UUID="$(blkid "${DEVICE}3" -o value -s UUID)"
    cp "${MOUNT}"/etc/mkinitcpio.conf "${MOUNT}"/etc/mkinitcpio.conf.bak"$(ls "${MOUNT}"/etc/mkinitcpio.conf.bak* | wc -l)"
    sed -i "s#cryptdevice=UUID=.*:cryptroot#cryptdevice=UUID=${LUKS_UUID}:cryptroot#" \
        "${MOUNT}/etc/default/grub"
    sed -i '/GRUB_ENABLE_CRYPTODISK=y/s/^#//g' "${MOUNT}/etc/default/grub"
fi
arch-chroot "${MOUNT}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE}"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/boot/bootx64.efi"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/debian/grubx64.efi"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/Redhat/grub.efi"

# Generate initramfs
arch-chroot "${MOUNT}" /bin/bash -c "mkinitcpio -P"
sync

msg "Restore completed."
