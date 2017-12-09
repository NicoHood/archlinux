#!/bin/bash

# Print initial welcome message with version information
VERSION="1.0.0"
echo "ArchLinux install script ${VERSION} https://github.com/NicoHood"
echo "More information: https://wiki.archlinux.org/index.php/installation_guide"

# Avoid any encoding problems
export LANG=C

# Check if messages are to be printed using color
unset ALL_OFF BOLD BLUE GREEN RED YELLOW MAGENTA CYAN
if [[ -t 2 ]]; then
    # Prefer terminal safe colored and bold text when tput is supported
    if tput setaf 0 &>/dev/null; then
        ALL_OFF="$(tput sgr0)"
        BOLD="$(tput bold)"
        BLUE="${BOLD}$(tput setaf 4)"
        GREEN="${BOLD}$(tput setaf 2)"
        RED="${BOLD}$(tput setaf 1)"
        YELLOW="${BOLD}$(tput setaf 3)"
        MAGENTA="${BOLD}$(tput setaf 5)"
        CYAN="${BOLD}$(tput setaf 6)"
    else
        ALL_OFF="\e[1;0m"
        BOLD="\e[1;1m"
        BLUE="${BOLD}\e[1;34m"
        GREEN="${BOLD}\e[1;32m"
        RED="${BOLD}\e[1;31m"
        YELLOW="${BOLD}\e[1;33m"
        MAGENTA="${BOLD}\e[1;35m"
        CYAN="${BOLD}\e[1;36m"
    fi
fi
readonly ALL_OFF BOLD BLUE GREEN RED YELLOW MAGENTA CYAN

function msg()
{
    echo "${GREEN}==>${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function msg2()
{
    echo "${BLUE}  ->${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function plain()
{
    echo "    ${1}" >&2
}

function warning()
{
    echo "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function error()
{
    echo "${RED}==> ERROR:${ALL_OFF}${BOLD} ${1}${ALL_OFF}" >&2
}

function die()
{
    error "${1}"
    exit 1
}

function kill_exit
{
    echo ""
    warning "Exited due to user intervention."
    exit 1
}

function command_not_found_handle
{
    die "${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1}: command not found."
}

function check_dependency()
{
    local RET=0
    for dependency in "${@}"
    do
        if ! command -v "${dependency}" &> /dev/null; then
            error "Required dependency '${dependency}' not found."
            RET=1
        fi
    done
    return "${RET}"
}

# Trap errors
set -o errexit -o errtrace -u
trap 'die "Error on or near line ${LINENO}."' ERR
trap kill_exit SIGTERM SIGINT SIGHUP

# Check input parameters
if [[ "$#" -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") <device>"
    exit 0
fi
echo ""

# Check for root user
if [[ ${EUID} -ne 0 ]]; then
    die "You must be a root user."
fi

# Get parameters
DEVICE="${1}"
shift

# Environment variables
MOUNT="${MOUNT:-/mnt}"
MY_USERNAME="${MY_USERNAME:-arch}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
PASSWD_USER="${PASSWD_USER:-toor}"
PASSWD_ROOT="${PASSWD_ROOT:-root}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us}"
GNOME="${GNOME:-y}"
BACKUP="${BACKUP:-/.btrfs/snapshots}"

# Desktop/VM presets
read -rp "Use preset for virtual machine? [y/N]?" yesno
if [[ "${yesno}" != [Yy]"es" && "${yesno}" != [Yy] ]]; then
    # Normal installation
    MY_HOSTNAME="${MY_HOSTNAME:-archlinuxpc}"
    RANDOM_SOURCE="${RANDOM_SOURCE:-random}"
    BTRFS="${BTRFS:-y}"
    LUKS="${LUKS:-y}"
    VM="${VM:-n}"
else
    # VM installation
    MY_HOSTNAME="${MY_HOSTNAME:-archlinuxvm}"
    RANDOM_SOURCE="${RANDOM_SOURCE:-random}"
    BTRFS="${BTRFS:-y}"
    LUKS="${LUKS:-n}"
    VM="${VM:-y}"
fi

read -rp "Customize options? [y/N]?" yesno
if [[ "${yesno}" != [Yy]"es" && "${yesno}" != [Yy] ]]; then
    # TODO interactive read with default values
    # TODO different layouts info ls /usr/share/kbd/keymaps/**/*.map.gz
    # $(tzselect) TODO default to timezone of the current system: readlink -fe /etc/localtime
    # TODO check if timezone option exists
    echo TODO
fi

# TODO print option overview

# Check if dependencies are available
# Dependencies: bash arch-install-scripts btrfs-progs dosfstools sed cryptsetup
check_dependency pacstrap arch-chroot genfstab btrfs mkfs.fat sed cryptsetup \
     || die "Please install the missing dependencies."

# Device check
if [[ ! -b "${DEVICE}" ]]; then
    die "Not a valid device: ${DEVICE}"
fi

# Mountpoint check
if [[ ! -d "${MOUNT}" ]] ; then
    die "Not a valid mountpoint directory: ${MOUNT}"
fi

# User check
warning "Creating partitions and filesystems on ${DEVICE} with temporary mountpoint ${MOUNT}."
read -rp "This will overwrite any existing data. Continue [y/N]?" yesno
if [[ "${yesno}" != [Yy]"es" && "${yesno}" != [Yy] ]]; then
    warning "Aborted by user"
    exit 0
fi

msg "1 Pre-installation"
msg2 "1.1 Set the keyboard layout"
# No keyboard layout switch required, as the script runs independant

# Boot CD in EFI mode
msg2 "1.2 Verify the boot mode"
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    warning "Not running in EFI mode. The system will not be able to boot with EFI, only legacy BIOS."
fi

# Check for internet
msg2 "1.3 Connect to the Internet"
if ! ping archlinux.org -c 4; then
    die "No network connection."
fi

# Set time
msg2 "1.4 Update the system clock"
timedatectl set-ntp true

msg2 "1.5 Partition the disks"

# Unmount all existing/pending installations first
umount -R "${MOUNT}" || true
cryptsetup luksClose /dev/mapper/$(blkid ${DEVICE}3 -o value -s UUID) || true

# Partition disk:
# GPT
# +1M bios boot partition
# +512M EFI /boot/efi partition
# 100% luks root / partition
wipefs -a "${DEVICE}"
plain "Formating disk..."
echo -e "g\nn\n\n\n+1M\nt\n4\nn\n\n\n+512M\nt\n\n1\nn\n\n\n\np\nw\n" | fdisk "${DEVICE}"
sync

# Make sure that all new partitions do not contain any filesystem signatures anymore
wipefs -a ${DEVICE}1
wipefs -a ${DEVICE}2
wipefs -a ${DEVICE}3

ROOT_DEVICE=${DEVICE}3
if [[ "${LUKS}" == "y" ]]; then
    # Create cryptodisks
    warning "For more security overwrite the disk with random bytes first."
    plain "Creating and opening root luks container"
    echo "${PASSWD_ROOT}" | cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 --use-${RANDOM_SOURCE} ${DEVICE}3

    # Open cryptodisks
    LUKS_UUID=$(blkid ${DEVICE}3 -o value -s UUID)
    echo "${PASSWD_ROOT}" | cryptsetup luksOpen ${DEVICE}3 "${LUKS_UUID}"
    ROOT_DEVICE="/dev/mapper/${LUKS_UUID}"
fi

# Create and mount btrfs
msg2 "1.6 Mount the file systems"
if [[ "${BTRFS}" == "y" ]]; then
    mkfs.btrfs -f "${ROOT_DEVICE}"
    mount -o nossd "${ROOT_DEVICE}" ${MOUNT}
    chmod 700 ${MOUNT}

    # Create structure subvolumes
    btrfs subvolume create ${MOUNT}/subvolumes
    btrfs subvolume create ${MOUNT}/snapshots
    btrfs subvolume create ${MOUNT}/excludes

    # Use external backup to install from
    if [[ -n "${BACKUP}" ]]; then
      # Transfer backup snapshots and create read/write snapshots of them
      SRC_DIR="$(find "${BACKUP}"/root/ -maxdepth 1 -mindepth 1 -type d | sort -V | tail -n 1)/snapshot"
      btrfs send "${SRC_DIR}" | btrfs receive ${MOUNT}/subvolumes/
      btrfs subvolume snapshot ${MOUNT}/subvolumes/snapshot ${MOUNT}/subvolumes/root
      btrfs subvolume delete ${MOUNT}/subvolumes/snapshot

      SRC_DIR="$(find "${BACKUP}"/home/ -maxdepth 1 -mindepth 1 -type d | sort -V | tail -n 1)/snapshot"
      btrfs send "${SRC_DIR}" | btrfs receive ${MOUNT}/subvolumes/
      btrfs subvolume snapshot ${MOUNT}/subvolumes/snapshot ${MOUNT}/subvolumes/home
      btrfs subvolume delete ${MOUNT}/subvolumes/snapshot

      SRC_DIR="$(find "${BACKUP}"/repo/ -maxdepth 1 -mindepth 1 -type d | sort -V | tail -n 1)/snapshot"
      btrfs send "${SRC_DIR}" | btrfs receive ${MOUNT}/subvolumes/
      btrfs subvolume snapshot ${MOUNT}/subvolumes/snapshot ${MOUNT}/subvolumes/repo
      btrfs subvolume delete ${MOUNT}/subvolumes/snapshot
    else
      # Create top level subvolumes
      btrfs subvolume create ${MOUNT}/subvolumes/root
      btrfs subvolume create ${MOUNT}/subvolumes/home
      btrfs subvolume create ${MOUNT}/subvolumes/repo
    fi

    # Create subvolumes for snapshots
    btrfs subvolume create ${MOUNT}/snapshots/root
    btrfs subvolume create ${MOUNT}/snapshots/home
    btrfs subvolume create ${MOUNT}/snapshots/repo

    # Create subvolumes untracked by snapper
    btrfs subvolume create ${MOUNT}/excludes/pkg
    btrfs subvolume create ${MOUNT}/excludes/tmp
    chmod +t ${MOUNT}/excludes/tmp
    btrfs subvolume create ${MOUNT}/excludes/log
    btrfs subvolume create ${MOUNT}/excludes/srv
    btrfs subvolume create ${MOUNT}/excludes/data

    # Unmount btrfs filesystem
    umount -R ${MOUNT}

    # Mount snapper tracked root and home subvolume to the mountpoint
    mount -o nossd,subvol=subvolumes/root "${ROOT_DEVICE}" ${MOUNT}
    mkdir -p ${MOUNT}/.snapshots
    mount -o nossd,subvol=snapshots/root "${ROOT_DEVICE}" ${MOUNT}/.snapshots
    mkdir -p ${MOUNT}/home
    mount -o nossd,subvol=subvolumes/home "${ROOT_DEVICE}" ${MOUNT}/home
    mkdir -p ${MOUNT}/home/.snapshots
    mount -o nossd,subvol=snapshots/home "${ROOT_DEVICE}" ${MOUNT}/home/.snapshots
    mkdir -p ${MOUNT}/repo
    mount -o nossd,subvol=subvolumes/repo "${ROOT_DEVICE}" ${MOUNT}/repo
    mkdir -p ${MOUNT}/repo/.snapshots
    mount -o nossd,subvol=snapshots/repo "${ROOT_DEVICE}" ${MOUNT}/repo/.snapshots

    # Mount btrfs real root directory to /.btrfs
    mkdir -p ${MOUNT}/.btrfs
    mount -o nossd "${ROOT_DEVICE}" ${MOUNT}/.btrfs

    # Mount subvolumes which should get excluded from snapper backups
    mkdir -p ${MOUNT}/var/cache/pacman/pkg
    mkdir -p ${MOUNT}/var/tmp
    mkdir -p ${MOUNT}/var/log
    mkdir -p ${MOUNT}/srv
    mkdir -p ${MOUNT}/data
    mount -o nossd,subvol=excludes/pkg "${ROOT_DEVICE}" ${MOUNT}/var/cache/pacman/pkg
    mount -o nossd,subvol=excludes/tmp "${ROOT_DEVICE}" ${MOUNT}/var/tmp
    mount -o nossd,subvol=excludes/log "${ROOT_DEVICE}" ${MOUNT}/var/log
    mount -o nossd,subvol=excludes/srv "${ROOT_DEVICE}" ${MOUNT}/srv
    mount -o nossd,subvol=excludes/data "${ROOT_DEVICE}" ${MOUNT}/data
else
    # Create and mount ext4 root
    mkfs.ext4 "${ROOT_DEVICE}"
    mount "${ROOT_DEVICE}" ${MOUNT}
fi

# Format and mount efi partition
mkfs.fat -F32 ${DEVICE}2
mkdir -p "${MOUNT}/boot/efi"
mount ${DEVICE}2 "${MOUNT}/boot/efi"

if [[ -z "${BACKUP}" ]]; then
    msg "2 Installation"

    # Mirror selection
    msg2 "2.1 Select the mirrors"
    warning "System mirrorlist will be used for new installation."
    plain "Please visit https://www.archlinux.org/mirrorlist/ and only use https + ipv4&6 only mirrors."

    # Install basic system and chroot
    msg2 "2.2 Install the base packages"

    # Use local package cache for non livecd installations
    if [ -f ~/install.txt ]; then
        pacstrap "${MOUNT}" - <pkg/base.pacman
    else
        pacstrap -c "${MOUNT}" - <pkg/base.pacman
    fi

    # TODO
    # Ask to install gnome desktop
    # Ask to install virtual box video drivers
fi

msg "3 Configure the system"
msg2 "3.1 Fstab"
cp "${MOUNT}"/etc/fstab "${MOUNT}"/etc/fstab.bak
genfstab -U "${MOUNT}" > "${MOUNT}"/etc/fstab

if [[ -z "${BACKUP}" ]]; then
    msg2 "3.1 Chroot"
    # All chroot is done with a separate command to make the script better readable in editors

    # Set time zone
    msg2 "3.3 Time zone"
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${MOUNT}"/etc/localtime
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
    echo "${MY_HOSTNAME}" > "${MOUNT}"/etc/hostname

    msg2 "3.6 Network configuration"
    arch-chroot "${MOUNT}" /bin/bash -c "systemctl enable dhcpcd.service"
    warning "dhcpcd.service enabled. Disable it when using NetworkManager.service instead."
fi

# Mkinitcpio
msg2 "3.7 Initramfs"

if [[ "${LUKS}" == "y" ]]; then
    # Create and add crypto keyfile for faster initramfs unlocking
    if [[ -z "${BACKUP}" ]]; then
        dd bs=512 count=4 if=/dev/${RANDOM_SOURCE} of=${MOUNT}/root/crypto_keyfile.bin iflag=fullblock
        sync

        # Forbit to read initramfs to not get access to embedded crypto keys
        chmod 000 ${MOUNT}/root/crypto_keyfile.bin
        chmod 700 "${MOUNT}"/boot/initramfs-linux*

        # Add "keymap, encrypt" hooks and "/usr/bin/btrfs" to binaries
        sed -i 's/^HOOKS=(.*block/\0 keymap encrypt/g' "${MOUNT}"/etc/mkinitcpio.conf
        sed -i "s#^FILES=(#\0/root/crypto_keyfile.bin#g" "${MOUNT}"/etc/mkinitcpio.conf
    fi

    echo "${PASSWD_ROOT}" | cryptsetup luksAddKey ${DEVICE}3 ${MOUNT}/root/crypto_keyfile.bin
fi
if [[ "${BTRFS}" == "y" && -z "${BACKUP}" ]]; then
    sed -i "s#^BINARIES=(#\0/usr/bin/btrfs#g" "${MOUNT}"/etc/mkinitcpio.conf
fi

# Generate initramfs
arch-chroot "${MOUNT}" /bin/bash -c "mkinitcpio -P"

if [[ -z "${BACKUP}" ]]; then
    # Add new admin user and disable root account
    msg2 "3.8 Root password"
    sed -i '/%wheel.ALL=(ALL) ALL/s/^# //g' "${MOUNT}/etc/sudoers"
    arch-chroot "${MOUNT}" /bin/bash -c "useradd -m -G wheel,users,lp,uucp -s /bin/bash ${MY_USERNAME,,}"
    echo "${MY_USERNAME,,}:${PASSWD_USER}" | arch-chroot "${MOUNT}" /bin/bash -c "chpasswd"
    arch-chroot "${MOUNT}" /bin/bash -c "chfn -f ${MY_USERNAME} ${MY_USERNAME,,}"
    arch-chroot "${MOUNT}" /bin/bash -c "passwd -l root"

    # Create user folders for /data/$USER and /repo/$USER
    arch-chroot "${MOUNT}" /bin/bash -c "install -d -o "${MY_USERNAME,,}" -g "${MY_USERNAME,,}" -m 700 "/data/${MY_USERNAME,,}""
    arch-chroot "${MOUNT}" /bin/bash -c "install -d -o "${MY_USERNAME,,}" -g "${MY_USERNAME,,}" -m 700 "/repo/${MY_USERNAME,,}""
fi

# Install grub for efi and bios. Efi installation will only work if you booted with efi.
msg2 "3.9 Boot loader"
if [[ "${LUKS}" == "y" ]]; then
    if [[ -z "${BACKUP}" ]]; then
        sed -i "s#^GRUB_CMDLINE_LINUX=\"#\0cryptdevice=UUID=${LUKS_UUID}:cryptroot cryptkey=rootfs:/root/crypto_keyfile.bin#g" \
            "${MOUNT}/etc/default/grub"
    else
        cp "${MOUNT}/etc/default/grub" "${MOUNT}/etc/default/grub.bak"
        sed -i "s#cryptdevice=UUID=.*:cryptroot#cryptdevice=UUID=${LUKS_UUID}:cryptroot#" \
            "${MOUNT}/etc/default/grub"
    fi
    sed -i '/GRUB_ENABLE_CRYPTODISK=y/s/^#//g' "${MOUNT}/etc/default/grub"
fi
arch-chroot "${MOUNT}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
arch-chroot "${MOUNT}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE}"
install -Dm 755 "${MOUNT}/boot/efi/EFI/grub/grubx64.efi" "${MOUNT}/boot/efi/EFI/boot/bootx64.efi"

# User check
msg "4 Reboot"
sync
plain "Installation successful. System still mounted at ${MOUNT}. Unmount and reboot now? [Y/n]"
read -r yesno
if [[ "${yesno}" != [Yy]"es" && "${yesno}" != [Yy] && -n "${yesno}" ]]; then
    warning "Aborted by user"
    exit 0
fi

# Unmount and reboot
umount -R "${MOUNT}"

if [[ "${LUKS}" == "y" ]]; then
    # Close cryptodisk
    cryptsetup luksClose "${ROOT_DEVICE}"
fi
reboot


# TODO check all moount options
# TODO nossd required?
