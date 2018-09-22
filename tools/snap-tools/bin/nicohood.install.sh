#!/bin/bash

# Import util functions, will print a welcome message
[[ ! -f "${BASH_SOURCE%/*}/nicohood.common" ]] && echo "nicohood.common script not found." && exit 1
source "${BASH_SOURCE%/*}/nicohood.common"

# Check input parameters
if [[ "$#" -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device> [subvolumes]"
    echo "Default subvolumes: ${DEFAULT_SUBVOLUMES[*]}"
    exit 0
fi

# Get parameters
DEVICE="${1}"
shift
SUBVOLUMES=(${@:-${DEFAULT_SUBVOLUMES[@]}})

# Check user, device and mountpoint
[[ "${EUID}" -ne 0 ]] && die "You must be a root user."
[[ ! -b "${DEVICE}" ]] && die "Not a valid device: '${DEVICE}'"

# Default settings
MY_USERNAME="${MY_USERNAME:-"${SUDO_USER:-arch}"}"
PASSWD_USER="${PASSWD_USER:-toor}"
MY_HOSTNAME="${MY_HOSTNAME:-archlinuxpc}"
PASSWD_ROOT="${PASSWD_ROOT:-root}"
LUKS="${LUKS:-y}"
GNOME="${GNOME:-y}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-"$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf &>/dev/null || echo us)"}"
TIMEZONE="${TIMEZONE:-"$(readlink -fe /etc/localtime)"}"
INTERACTIVE="${INTERACTIVE:-y}"

# User settings dialog
if [[ "${INTERACTIVE}" == y ]]; then
    msg "Settings:"
    read -p "Enter username: " -e -i "${MY_USERNAME}" MY_USERNAME
    read -p "Enter hostname: " -e -i "${MY_HOSTNAME}" MY_HOSTNAME
    read -p "Install gnome desktop environment? " -e -i "${GNOME}" GNOME
    read -p "Use luks encryption? " -e -i "${LUKS}" LUKS
    read -p "Enter keyboard layout: " -e -i "${KEYBOARD_LAYOUT}" KEYBOARD_LAYOUT
    if [ -f ~/install.txt ]; then
        TIMEZONE="/usr/share/zoneinfo/$(tzselect)"
    else
        read -p "Enter timezone: " -e -i "${TIMEZONE}" TIMEZONE
    fi
fi

msg "1 Pre-installation"
msg2 "1.1 Set the keyboard layout"
# No keyboard layout switch required, as the script runs independant

# Boot CD in EFI mode
msg2 "1.2 Verify the boot mode"
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    warning "Not running in EFI mode. The system might not be able to boot with EFI, only legacy BIOS. Make sure to reinitialize the efi variables."
fi

# Check for internet
msg2 "1.3 Connect to the Internet"
if ! ping archlinux.org -c 4; then
    die "No network connection."
fi

# Last user check
if [[ "${INTERACTIVE}" == y ]]; then
    read -rp "Press enter to start the installation now."
fi

# Set time
# Ntp will be enabled for the target system automatcally via systemd service.
msg2 "1.4 Update the system clock"
if [ -f ~/install.txt ]; then
    timedatectl set-ntp true
fi

# Create filesystems
msg2 "1.5 Partition the disks"
PASSWD_ROOT="${PASSWD_ROOT}" LUKS="${LUKS}" nicohood.mkfs "${DEVICE}" "${SUBVOLUMES[@]}"

# Create temporary mountpoint
msg2 "1.6 Mount the file systems"
mkdir -p /run/media/root/
MOUNT="$(mktemp -d /run/media/root/mnt.XXXXXXXXXX)"
PASSWD_ROOT="${PASSWD_ROOT}" nicohood.mount "${DEVICE}" "${MOUNT}"

msg "2 Installation"

# Mirror selection
msg2 "2.1 Select the mirrors"
if [ -f ~/install.txt ]; then
    cp "/etc/pacman.d/mirrorlist" "/etc/pacman.d/mirrorlist.bak"
    curl -s "https://www.archlinux.org/mirrorlist/?country=DE&country=GB&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" \
        | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors - > "/etc/pacman.d/mirrorlist"
fi

# Install basic system and chroot
msg2 "2.2 Install the base packages"

# Determine packages to install
RESOURCE_DIR="$(dirname "$(realpath "${BASH_SOURCE}")")"
PACKAGES=("${RESOURCE_DIR}/pkg/base.pacman")
if [[ "${GNOME}" == "y" ]]; then
    PACKAGES+=("${RESOURCE_DIR}/pkg/gnome.pacman")
fi

# Use local package cache for non livecd installations
if [ -f ~/install.txt ]; then
    cat "${PACKAGES[@]}" | pacstrap "${MOUNT}" -
else
    cat "${PACKAGES[@]}" | pacstrap -c "${MOUNT}" -
fi

msg "3 Configure the system"
msg2 "3.1 Fstab"
genfstab -U "${MOUNT}" > "${MOUNT}"/etc/fstab

# All chroot is done with a separate command to make the script better readable in editors
msg2 "3.1 Chroot"

# Set time zone
msg2 "3.3 Time zone"
ln -sf "${TIMEZONE}" "${MOUNT}"/etc/localtime
arch-chroot "${MOUNT}" /bin/bash -c "hwclock --systohc --utc"
arch-chroot "${MOUNT}" /bin/bash -c "systemctl enable systemd-timesyncd.service"

# Set locale, only english language (not keyboard layout!) is supported by this script
msg2 "3.4 Locale"
sed -i '/en_US.UTF-8 UTF-8/s/^#//g' "${MOUNT}"/etc/locale.gen
arch-chroot "${MOUNT}" /bin/bash -c "locale-gen"
echo 'LANG=en_US.UTF-8' > "${MOUNT}"/etc/locale.conf
# /etc/locale.conf already contains LANG=en_US.UTF-8 by default
echo "KEYMAP=${KEYBOARD_LAYOUT}" > "${MOUNT}"/etc/vconsole.conf

# Hostname
msg2 "3.5 Hostname"
echo "${MY_HOSTNAME,,}" > "${MOUNT}"/etc/hostname

msg2 "3.6 Network configuration"
if [[ "${GNOME}" != "y" ]]; then
    arch-chroot "${MOUNT}" /bin/bash -c "systemctl enable dhcpcd.service"
    warning "dhcpcd.service enabled. Disable it when using NetworkManager.service instead."
else
    # Enable gnome network and other services
    while read -r line; do
        arch-chroot "${MOUNT}" /bin/bash -c "systemctl enable ${line}"
    done < "${RESOURCE_DIR}/pkg/gnome.systemd"
fi

# Mkinitcpio
msg2 "3.7 Initramfs"

if [[ "${LUKS}" == "y" ]]; then
    # Forbit to read initramfs to not get access to embedded crypto keys
    warning "Setting initramfs permissions to 600. Make sure to also change permissions for your own installed kernels."
    chmod 600 "${MOUNT}"/boot/initramfs-linux*

    # Add "keymap, encrypt" hooks and "/usr/bin/btrfs" to binaries
    sed -i 's/^HOOKS=(.*block/\0 keymap encrypt/g' "${MOUNT}"/etc/mkinitcpio.conf
    sed -i "s#^FILES=(#\0/root/luks/crypto_keyfile.bin#g" "${MOUNT}"/etc/mkinitcpio.conf
fi
sed -i "s#^BINARIES=(#\0/usr/bin/btrfs#g" "${MOUNT}"/etc/mkinitcpio.conf

# Generate initramfs
arch-chroot "${MOUNT}" /bin/bash -c "mkinitcpio -P"

# Add new admin user and disable root account
msg2 "3.8 Root password"
sed -i '/%wheel.ALL=(ALL) ALL/s/^# //g' "${MOUNT}/etc/sudoers"
arch-chroot "${MOUNT}" /bin/bash -c "useradd -m -d /home/user -G wheel,users,lp,uucp,lock,audio -s /bin/bash ${MY_USERNAME,,}"
echo "${MY_USERNAME,,}:${PASSWD_USER}" | arch-chroot "${MOUNT}" /bin/bash -c "chpasswd"
arch-chroot "${MOUNT}" /bin/bash -c "chfn -f ${MY_USERNAME} ${MY_USERNAME,,}"
arch-chroot "${MOUNT}" /bin/bash -c "passwd -l root"

# Install grub for efi and bios. Efi installation will only work if you booted with efi.
msg2 "3.9 Boot loader"
if [[ "${LUKS}" == "y" ]]; then
    LUKS_UUID="$(blkid "${DEVICE}3" -o value -s UUID)"
    sed -i "s#^GRUB_CMDLINE_LINUX=\"#\0cryptdevice=UUID=${LUKS_UUID}:cryptroot cryptkey=rootfs:/root/luks/crypto_keyfile.bin#g" \
        "${MOUNT}/etc/default/grub"
    sed -i '/GRUB_ENABLE_CRYPTODISK=y/s/^#//g' "${MOUNT}/etc/default/grub"
fi
sed -i "/^GRUB_DEFAULT=.*/s/=.*/='Arch Linux, with Linux linux'/g" "${MOUNT}/etc/default/grub"
sed -i '/^GRUB_DEFAULT=*/iGRUB_DISABLE_SUBMENU=y' "${MOUNT}/etc/default/grub"
arch-chroot "${MOUNT}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE}"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/boot/bootx64.efi"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/debian/grubx64.efi"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/Redhat/grub.efi"

# User check
msg "4 Reboot"
sync
plain "Installation successful. System still mounted at ${MOUNT}. Unmount and reboot now? [Y/n]"
warning "You need to change the default disk and user password after the reboot!"
read -r yesno
if [[ "${yesno}" != [Yy]"es" && "${yesno}" != [Yy] && -n "${yesno}" ]]; then
    abort_exit
fi

# Unmount and reboot
umount -R "${MOUNT}"
if [[ "${LUKS}" == "y" ]]; then
    cryptsetup luksClose "${LUKS_UUID}"
fi
reboot
