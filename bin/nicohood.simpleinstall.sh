#!/bin/bash

# Check input parameters
if [[ "$#" -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device>"
    exit 0
fi
DEVICE="${1}"

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && echo "You must be a root user." && exit 1
[[ ! -b "${DEVICE}" ]] && echo "Not a valid device: '${DEVICE}'" && exit 1

# User settings dialog
echo "Settings:"
read -rp "Enter username: " -e -i "arch" MY_USERNAME
read -rp "Enter hostname: " -e -i "archlinuxpc" MY_HOSTNAME
read -rp "Enter keyboard layout: " -e -i "$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf &>/dev/null || echo us)" KEYBOARD_LAYOUT
TIMEZONE="/usr/share/zoneinfo/$(tzselect)"

# Boot CD in EFI mode
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "Warning: Not running in EFI mode. The system might not be able to boot with EFI, only legacy BIOS. Make sure to reinitialize the efi variables."
fi

# Check for internet
if ! ping archlinux.org -c 4; then
    echo "Error: No network connection." && exit 1
fi

# Last user check
read -r -p "Press enter to start installation."
set -o errexit -o errtrace -u -x -E

# Ntp will be enabled for the target system automatcally via systemd service.
if [ -f ~/install.txt ]; then
    timedatectl set-ntp true
fi

# Partition disk
echo -e "g\nn\n\n\n+1M\nt\n4\nn\n\n\n+512M\nt\n\n1\nn\n\n\n\np\nw\n" | fdisk -w always -W always "${DEVICE}"
sync

# Create filesystems
mkfs.fat -F32 -s 1 -S 4096 -v "${DEVICE}2"
mkfs.ext4 "${DEVICE}3"

# Mount partitions
mkdir -p /run/media/root/
MOUNT="$(mktemp -d /run/media/root/mnt.XXXXXXXXXX)"
mount "${DEVICE}3" "${MOUNT}"
mkdir -p "${MOUNT}/boot/efi"
mount "${DEVICE}2" "${MOUNT}/boot/efi"

# Mirror selection
if [ -f ~/install.txt ]; then
    curl -s "https://www.archlinux.org/mirrorlist/?country=DE&country=GB&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" \
        | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors - > "/etc/pacman.d/mirrorlist"
fi

# Install base system
pacstrap "${MOUNT}" base grub efibootmgr bash-completion intel-ucode \
    os-prober rng-tools sudo ttf-dejavu ttf-liberation

# Generate fstab entries
genfstab -U "${MOUNT}" > "${MOUNT}"/etc/fstab

# Set time zone
ln -sf "${TIMEZONE}" "${MOUNT}"/etc/localtime
arch-chroot "${MOUNT}" /bin/bash -c "hwclock --systohc --utc"
arch-chroot "${MOUNT}" /bin/bash -c "systemctl enable systemd-timesyncd.service"

# Set locale, only english language (not keyboard layout!) is supported by this script
sed -i '/en_US.UTF-8 UTF-8/s/^#//g' "${MOUNT}"/etc/locale.gen
arch-chroot "${MOUNT}" /bin/bash -c "locale-gen"
echo 'LANG=en_US.UTF-8' > "${MOUNT}"/etc/locale.conf
# /etc/locale.conf already contains LANG=en_US.UTF-8 by default
echo "KEYMAP=${KEYBOARD_LAYOUT}" > "${MOUNT}"/etc/vconsole.conf

# Hostname and network
echo "${MY_HOSTNAME}" > "${MOUNT}"/etc/hostname
arch-chroot "${MOUNT}" /bin/bash -c "systemctl enable dhcpcd.service"
echo "Warning: dhcpcd.service enabled. Disable it when using NetworkManager.service instead."

# Mkinitcpio
arch-chroot "${MOUNT}" /bin/bash -c "mkinitcpio -P"

# Add new admin user and disable root account
sed -i '/%wheel.ALL=(ALL) ALL/s/^# //g' "${MOUNT}/etc/sudoers"
arch-chroot "${MOUNT}" /bin/bash -c "useradd -m -d /home/user -G wheel,users,lp,uucp -s /bin/bash ${MY_USERNAME,,}"
echo "${MY_USERNAME,,}:123456" | arch-chroot "${MOUNT}" /bin/bash -c "chpasswd"
arch-chroot "${MOUNT}" /bin/bash -c "chfn -f ${MY_USERNAME} ${MY_USERNAME,,}"
arch-chroot "${MOUNT}" /bin/bash -c "passwd -l root"

# Install grub for efi and bios. Efi installation will only work if you booted with efi.
arch-chroot "${MOUNT}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE}"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/boot/bootx64.efi"

umount -R "${MOUNT}"
sync
read -r -p "Installation successful. Press enter to reboot now."
reboot
