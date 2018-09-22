# Snap-Tools
Scripts and tools for installing a snapper+btrfs based Arch Linux backup system.

## Installation Script
Installs a minimal Arch Linux system with guided setup. Follows the [installation schema of the wiki](https://wiki.archlinux.org/index.php/installation_guide) so you can customize the script easily and better understand it.

### Features
* The system is bootable on EFI and BIOS computers
* Including fallback efi bootloaders to support efi (also boot from USB) without efi variables
* Fully encrypted root (including kernel and /boot)
* Strongest encryption settings used
* Btrfs/snapper optimized filesystem layout
* Live system cloning support by special backup concept (see below)

### Installation

#### Dependencies
* base-devel
* arch-install-scripts
* btrfs-progs
* dosfstools
* pacman-contrib

#### Installation Disc
This installation method is only suitable for live disks. It installs the software directly inside the filesystem without a proper package. For an existing system always use the PKGBUILD install further below.

```
mount -o remount,size=1G /run/archiso/cowspace
pacman -Sy git base-devel pacman-contrib --needed --noconfirm
git clone https://github.com/nicohoood/archlinux.git
make install -C archlinux PREFIX=/usr/local
```

#### Existing Installation
Install the PKGBUILD as you are used to do with AUR packages.

### Backup Concept
This script does not only install Arch Linux, it also sets up the system for a well thought-out backup concept. The backup concept relies on a specific partition and filesystem layout, which is described below. The most important aspects are:
* Hourly/Daily/Weekly/Monthly on-disk snapshots using [snapper](https://github.com/openSUSE/snapper)
* Pacman transaction snapshots using [snap-pac](https://github.com/wesbarnett/snap-pac)
* Incremental backup to external drive (or via ssh) using [snap-sync](https://github.com/wesbarnett/snap-sync)
* Easy restoring of single files inside snapshots/backup using btrfs snapshots
* Easy restoring of a full system backup or even a running system using the provided scripts of this repository

### Partition Layout
The partition layout is designed for compatibility and security. Even though a GPT is used, the system can still [boot via legacy boot through the 1M Grub partition](https://wiki.archlinux.org/index.php/GRUB#GUID_Partition_Table_.28GPT.29_specific_instructions). On newer EFI systems Grub is directly loaded from the [Efi System Partition (ESP)](https://wiki.archlinux.org/index.php/EFI_System_Partition). A fallback bootloader (bootx64.efi) is also installed to ensure the system still boots when the efi variables are lost.

To protect your data as best as possible the root filesystem gets encrypted with the strongest luks settings. Even the Linux kernel and anything else in /boot will be encrypted, only Grub is accessible by an attacker.

```
+-------------------------------+
|     GPT (BIOS compatible)     |
+--------+----------+-----------+
|  sda1  |   sda2   |   sda3    |
+--------+----------+-----------+
|  Grub  | Efi Grub | Luks root |
+--------+----------+-----------+
|   1M   |   512M   |   100%    |
+--------+----------+-----------+
|  Grub  |  Fat32   |   Btrfs   |
|        |/boot/efi |     /     |
+-------------------+-----------+
```

### Filesystem Layout
To understand the filesystem layout it is recommended to read up on [Btrfs subvolumes](https://wiki.archlinux.org/index.php/Btrfs#Subvolumes) first. This layout is optimized for creating new snapshots and backups with the mentioned snapper, snap-pac and snap-sync tools.

The btrfs subvolume layout is designed to take snapshots of the root, home and user directory, as well as custom user-defined snapshot directories. This layout is designed to be used with a main user with uid 1000.

The currently in use (master) subvolumes are stored inside `subvolumes`. Those hold the data of the running system. All snapshots of those subvolumes are stored inside `snapshots`. These subvolumes are mounted to the root filesystem in a way that snapper recognizes them properly while it is still possible to restore a system to a previous state.

The `snapshots` directory also has the same layout as a snap-sync backup. This makes it possible to restore a running system in the same way a snap-sync backup is restored.

Additionally some subvolumes are excluded from the backup, such as the pacman package cache and `data`. This data storage can be used for large persistent data which does not require (automated) backups such as VMs, makepkg, spotify, steam data.

An embedded initramfs keyfile is used to unlock the root partition at boot, [without having to enter the password twice](https://wiki.archlinux.org/index.php/Dm-crypt/Device_encryption#With_a_keyfile_embedded_in_the_initramfs). Make sure to chmod further kernels to permission 600!

```
btrfs
`-- / -> /.btrfs (root:root 700)
    |-- subvolumes
    |   |-- root -> /
    |   |-- home -> /home
    |   |-- user -> /home/user (1000:1000 700)
    |   `-- custom
    |       |-- git -> /home/user/git (1000:1000)
    |       |-- data -> /home/user/data (1000:1000)
    |       |-- vm -> /home/user/vm (1000:1000)
    |       |-- Documents -> /home/user/Documents (1000:1000)
    |       |-- Downloads -> /home/user/Downloads (1000:1000)
    |       |-- Pictures -> /home/user/Pictures (1000:1000)
    |       |-- Music -> /home/user/Music (1000:1000)
    |       |-- Videos -> /home/user/Videos (1000:1000)
    |       `-- ...
    |-- snapshots
    |   |-- root -> /.snapshots
    |   |-- home -> /home/.snapshots
    |   |-- user -> /home/user/.snapshots
    |   `-- custom
    |       `-- ...
    |-- excludes
    |   |-- pkg  -> /var/cache/pacman/pkg
    |   |-- tmp  -> /var/tmp
    |   |-- log  -> /var/log
    |   `-- srv  -> /srv
    |-- backup -> /backup
    |   `-- $COMPUTER
    |       |-- root
    |       |-- home
    |       |-- user
    |       `-- custom
    |           `-- ...
    `-- luks -> /root/luks (root:root 000)
        `-- crypto_keyfile.bin (root:root 000)

fat32
`-- / -> /boot/efi/
    `-- EFI
        |-- boot
        |   `-- bootx64.efi
        `-- grub
            `-- grubx64.efi
```


### Migrating an existing installation
1. Create a new filesystem layout
2. Mount the filesystems
3. Copy all data with rsync
4. Copy initramfs, fstab and grub config
5. Merge those configs
6. Recreate initramfs and grub
7. `chmod 600 "${MOUNT}"/boot/initramfs-linux*`
8. [Recreate efi variables](https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface#efibootmgr)
9. Migrate user homedir to /home/user
10. Fix snapper settings

## After installation
* Change default user password `passwd`
* Change default Luks password (with gnome-disks).
* Update Arch Linux mirrorlist.
* Do user customization (with gnome-settings and gnome-tweaks tool)
* Enable ssh (via gnome settings)
* [Enable DNS caching](https://wiki.archlinux.org/index.php/dnsmasq#NetworkManager)
* [Enable hostname resolution](https://wiki.archlinux.org/index.php/avahi#Hostname_resolution)
* [Enable color output for Pacman](https://wiki.archlinux.org/index.php/Color_output_in_console#pacman)
* Configure `~/.bashrc` and `/etc/inputrc` (see configs below)
* Configure `~/.makepkg.conf`
* Set plank theme to transparent: `plank --preferences`
* Check if `systemctl status rngd.service` is active, otherwise install `haveged` (e.g. if you have slow boot time)

## TODO
* shellcheck
* AUR package
* Makefile
* Script names?
Fix bug with subvolumes in nautilus https://gitlab.gnome.org/GNOME/glib/issues/1271
