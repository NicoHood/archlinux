# Arch Linux
Script and tools for the daily usage of Arch Linux.

## Installation Script
Installs a minimal Arch Linux system with guided setup. Follows the schema of
the wiki so you can customize the script easily and understand it.

### Features
* The system is bootable on EFI and BIOS computers
* Including a fallback efi bootloader to support efi boot from USB
* Fully encrypted root /
* Btrfs/snapper optimized filesystem layout
* Live system cloning support
* Optional settings for VM (ext4, no encryption, etc.)

### Installation
File List:
* install_x64.sh
* pkg/base.pacman
* pkg/gnome.pacman
* pkg/gnome.systemd
* pkg/vm.pacman

### Dependencies
* btrfs-progs
* dosfstools
* arch-install-scripts
* libnewt (for whiptail in interactive mode)

### Partition Layout
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
* Snapper can be enabled for the configs root, home and repo
* Large data can be moved to /data/$USER (spotify, steam, makepkg, vm)

```
fat32
`-- / -> /boot/efi/
    `-- EFI
        |-- boot
        |   `-- bootx64.efi
        `-- grub
            `-- grubx64.efi

btrfs
`-- / -> /.btrfs (root:root 700)
    |-- subvolumes
    |   |-- root -> /
    |   |-- home -> /home
    |   `-- repo -> /repo
    |-- snapshots
    |   |-- root -> /.snapshots
    |   |-- home -> /home/.snapshots
    |   `-- repo -> /repo/.snapshots
    `-- excludes
        |-- pkg  -> /var/cache/pacman/pkg
        |-- tmp  -> /var/tmp
        |-- log  -> /var/log
        |-- srv  -> /srv
        `-- data -> /data
```

## TODO
* shellcheck
* AUR package
* Makefile

## Links
* [snapper](https://github.com/openSUSE/snapper)
* [snap-sync](https://github.com/wesbarnett/snap-sync)
* [snap-pac](https://github.com/wesbarnett/snap-pac)
