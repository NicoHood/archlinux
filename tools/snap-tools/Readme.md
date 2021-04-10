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
make install -C archlinux/tools/snap-tools PREFIX=/usr/local
```

#### Existing Installation
Install the PKGBUILD as you are used to do with AUR packages.

```bash
sudo pacman -S base-devel devtools pacman-contrib --needed
git clone https://github.com/nicohoood/archlinux.git
cd archlinux/tools/snap-tools
# Edit version number if required
updpkgsums
extra-x86_64-build
gpg --recv-keys 51DAE9B7C1AE9161
```

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

The `backup` subvolume is used when you want to use the disk as backup drive, but also make it bootable. Backups from other systems should be stored there.

An embedded initramfs keyfile is used to unlock the root partition at boot, [without having to enter the password twice](https://wiki.archlinux.org/index.php/Dm-crypt/Device_encryption#With_a_keyfile_embedded_in_the_initramfs). Make sure to chmod further kernels to permission 600!

```
btrfs
`-- / -> /.btrfs (root:root 700)
    |-- subvolumes
    |   |-- root -> /
    |   |-- home -> /home
    |   |-- user -> /home/user (1000:1000 700)
    |   |-- pkg  -> /var/cache/pacman/pkg
    |   |-- tmp  -> /var/tmp
    |   |-- log  -> /var/log
    |   |-- srv  -> /srv
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
    |   |-- pkg  -> /var/cache/pacman/pkg/.snapshots
    |   |-- tmp  -> /var/tmp/.snapshots
    |   |-- log  -> /var/log/.snapshots
    |   |-- srv  -> /srv/.snapshots
    |   `-- custom
    |       `-- ...
    |-- backup -> /backup
    |   `-- $hostname
    |       |-- root
    |       |-- home
    |       |-- user
    |       |-- ...
    |       `-- custom
    |           `-- ...
    `-- luks -> /root/luks (root:root 000)
        `-- crypto_keyfile.bin (root:root 000)

fat32
`-- / -> /boot/efi/
    `-- EFI
        |-- boot
        |   `-- bootx64.efi
        |-- grub
        |   `-- grubx64.efi
        |-- debian
        |   `-- grubx64.efi
        ``-- Redhat
            `-- grub.efi
```


### Migrating an Existing Installation

#### Preparation
1. System Maintenance
    Before you backup anything make sure your backed up system is healthy. You should update and reboot your system first and also check for common errors. Please check the system maintenance section for more information. After all system problems are solved you can proceed to the next step.

2. Disable System Services
    Disable any system service that can cause problems after a migration. You can re-enable them after the migration succeeded. Common system services are:
    * Webserver (nginx, apache)
    * Snapper
    * Home Automation (Home Assistant)
    * Ambilight (Hyperion)

    ```bash
    sudo systemctl disable home-assistant.service
    sudo systemctl disable snapper-boot.timer
    sudo systemctl disable snapper-cleanup.timer
    sudo systemctl disable snapper-timeline.timer
    ```

3. Find nested btrfs subvolumes
    If you are using btrfs on your current system, you might find nested btrfs subvolumes in your directory structure. Those are ignored in any snapper backups and must be transferred manually, if desired. After the backup restore those subvolumes are empty/dead and must be reinitialized. A common usecase are the devtool subvolumes which can be recreated by using the `-c` switch of the devtools script.

    You can check for those subvolumes by entering the following command:
    ```bash
    # Exclude the snapshots
    sudo btrfs subvolume list / | grep -v ".snapshot"
    ```

4. Do a System Backup
    Backup your system using snap-sync or rsync. Make sure to also manually backup the excluded subvolumes and any other data that is not included in the snap-sync backup.

    It is recommended to not migrate/restore the backup to the same system disc, as you might forgot anything to backup which will be lost. Kepp the old system for a while after the migration.

    If you are not using btrfs snapshots as backup it is recommended to only transfer the data in the following steps from a live system instead of the current running system.

5. Start a Live-System
    Like the installation disc or another ArchLinux from an USB Stick.

6. Install snap-tools
    See Instructions above.

#### Migration
1. Create a new filesystem layout on the target disk
    ```bash
    # Check target disk first
    lsblk
    DEVICE_NEW=/dev/sda
    sudo nicohood.mkfs "${DEVICE_NEW}"
    ```
2. Mount the filesystems
    ```bash
    MNT_BACKUP=/mnt/backup
    MNT_NEW=/mnt/backup
    #MNT_BACKUP=/run/media/nicohood/e5b8a2d6-85a1-4640-a659-acb8d6922bd6
    #MNT_NEW=/mnt    
    sudo mkdir -p "${MNT_BACKUP}" "${MNT_NEW}"

    # Mount the new filesystem
    sudo nicohood.mount "${DEVICE_NEW}" "${MNT_NEW}"

    # Mount backup disk
    sudo cryptsetup luksOpen /dev/sdX backup
    sudo mount /dev/mapper/backup "${MNT_BACKUP}"
    ls "${MNT_BACKUP}"
    ```
3. Copy all backed up data with rsync or btrfs send.    
    ```bash
    # NOTE: Make sure to restore the *correct and most up to date backup*. `ls` listings do not put the highest number last!
    ls "${MNT_BACKUP}"/backup/$hostname/*/ -la

    # https://wiki.archlinux.org/index.php/rsync#Full_system_backup
    sudo rsync -aAXH --numeric-ids --info=progress2 "${MNT_BACKUP}"/backup/zebes/root/6557/snapshot/. "${MNT_NEW}"

    # Transfer user data (user subfolder!)
    # NOTE: If you have multiple users on the system, make sure to transfere them as well!
    sudo rsync -aAXH --numeric-ids --info=progress2 "${MNT_BACKUP}"/backup/zebes/home/6251/snapshot/nicohood/. "${MNT_NEW}"/home/user

    # Transfer other snapshots
    sudo rsync -aAXH --numeric-ids --info=progress2 "${MNT_BACKUP}"/backup/E744/hackallthethings/7509/snapshot/. "${MNT_NEW}"/home/user/hackallthethings

    # Transfer manual backups
    sudo rsync -aAXH --numeric-ids --info=progress2 "${MNT_BACKUP}"/backup/E744/data/20181024/. "${MNT_NEW}"/home/user/data

    # TODO chmod 700 /.btrfs, as rsync overrides this setting. Or the mount command should add this as mount option?
    # Does not seem so!?
    ```
4. Backup initramfs, fstab and grub config using `.bak` files

```bash
#!/bin/bash
set -x
set -e
set -o errexit -o errtrace -u
LUKS=y

# Check if run as root
[[ "${EUID}" -ne 0 ]] && echo "You must be a root user." && exit 1

# TODO required because of sudo
DEVICE_NEW=/dev/sda
MNT_NEW=/mnt

# Fstab
# TODO update echos to warning commands
mv "${MNT_NEW}"/etc/fstab "${MNT_NEW}"/etc/fstab.bak"$(ls "${MNT_NEW}"/etc/fstab* | wc -l)" || echo "Warning: No fstab config file found."
genfstab -U "${MNT_NEW}" > "${MNT_NEW}"/etc/fstab

# Move Initramfs config. Force a reinstall to generate a new default config file.
mv "${MNT_NEW}"/etc/mkinitcpio.conf "${MNT_NEW}"/etc/mkinitcpio.conf.bak"$(ls "${MNT_NEW}"/etc/mkinitcpio.conf* | wc -l)" || echo "Warning: No mkinitcpio config file found."
arch-chroot "${MNT_NEW}" /bin/bash -c "pacman -S mkinitcpio --noconfirm"
if [[ "${LUKS}" == "y" ]]; then
    # Forbit to read initramfs to not get access to embedded crypto keys
    # TODO warning command unknown
    #warning "Setting initramfs permissions to 600. Make sure to also change permissions for your own installed kernels."
    chmod 600 "${MNT_NEW}"/boot/initramfs-linux*

    # Add "keymap, encrypt" hooks and "/usr/bin/btrfs" to binaries
    sed -i 's/^HOOKS=(.*block/\0 keymap encrypt/g' "${MNT_NEW}"/etc/mkinitcpio.conf
    sed -i "s#^FILES=(#\0/root/luks/crypto_keyfile.bin#g" "${MNT_NEW}"/etc/mkinitcpio.conf
fi
sed -i "s#^BINARIES=(#\0/usr/bin/btrfs#g" "${MNT_NEW}"/etc/mkinitcpio.conf
arch-chroot "${MNT_NEW}" /bin/bash -c "mkinitcpio -P"

# Move Grub config. Force a reinstall to generate a new default config file.
mv "${MNT_NEW}"/etc/default/grub "${MNT_NEW}"/etc/default/grub.bak"$(ls "${MNT_NEW}"/etc/default/grub* | wc -l)" || echo "Warning: No grub config file found."
arch-chroot "${MNT_NEW}" /bin/bash -c "pacman -S grub --noconfirm"
if [[ "${LUKS}" == "y" ]]; then
    LUKS_UUID="$(blkid "${DEVICE_NEW}3" -o value -s UUID)"
    sed -i "s#^GRUB_CMDLINE_LINUX=\"#\0cryptdevice=UUID=${LUKS_UUID}:cryptroot cryptkey=rootfs:/root/luks/crypto_keyfile.bin#g" \
        "${MNT_NEW}/etc/default/grub"
    sed -i '/GRUB_ENABLE_CRYPTODISK=y/s/^#//g' "${MNT_NEW}/etc/default/grub"
fi
sed -i "/^GRUB_DEFAULT=.*/s/=.*/='Arch Linux, with Linux linux'/g" "${MNT_NEW}/etc/default/grub"
sed -i '/^GRUB_DEFAULT=*/iGRUB_DISABLE_SUBMENU=y' "${MNT_NEW}/etc/default/grub"
arch-chroot "${MNT_NEW}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
arch-chroot "${MNT_NEW}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
arch-chroot "${MNT_NEW}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE_NEW}"
install -Dm 755 "${MNT_NEW}/boot/efi/EFI/grub/grubx64.efi" "${MNT_NEW}/boot/efi/EFI/boot/bootx64.efi"
install -Dm 755 "${MNT_NEW}/boot/efi/EFI/grub/grubx64.efi" "${MNT_NEW}/boot/efi/EFI/debian/grubx64.efi"
install -Dm 755 "${MNT_NEW}/boot/efi/EFI/grub/grubx64.efi" "${MNT_NEW}/boot/efi/EFI/Redhat/grub.efi"
```

5. Manually merge the old configs for initramfs, fstab and grub with the new ones
    ```bash
    diff -u "${MNT_NEW}"/etc/fstab.bak "${MNT_NEW}"/etc/fstab
    diff -u "${MNT_NEW}"/etc/default/grub.bak "${MNT_NEW}"/etc/default/grub
    diff -u "${MNT_NEW}"/etc/mkinitcpio.conf.bak "${MNT_NEW}"/etc/mkinitcpio.conf
    ```
6. Recreate initramfs and grub (if manual changes were applied to the configs)
    ```bash
    #!/bin/bash
    set -x
    DEVICE_NEW=/dev/sda
    MNT_NEW=/mnt

    # Mkinitcpio
    arch-chroot "${MNT_NEW}" /bin/bash -c "mkinitcpio -P"

    # Grub
    arch-chroot "${MNT_NEW}" /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
    arch-chroot "${MNT_NEW}" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub"
    arch-chroot "${MNT_NEW}" /bin/bash -c "grub-install --target=i386-pc ${DEVICE_NEW}"
    install -Dm 755 "${MNT_NEW}/boot/efi/EFI/grub/grubx64.efi" "${MNT_NEW}/boot/efi/EFI/boot/bootx64.efi"
    install -Dm 755 "${MNT_NEW}/boot/efi/EFI/grub/grubx64.efi" "${MNT_NEW}/boot/efi/EFI/debian/grubx64.efi"
    install -Dm 755 "${MNT_NEW}/boot/efi/EFI/grub/grubx64.efi" "${MNT_NEW}/boot/efi/EFI/Redhat/grub.efi"
    ```

7. Fix initramfs permission: `sudo chmod 600 "${MNT_NEW}"/boot/initramfs-linux*`
8. [Recreate efi variables](https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface#efibootmgr)
9. Migrate user homedir to /home/user
```bash
# Change user name and directory
sudo arch-chroot "${MNT_NEW}"
usermod -l nicohood arch
groupmod -n nicohood arch
usermod --home /home/user nicohood

# TODO fix autologin
# TODO change finger name -> Do via gnome settings

# Symlink/bind a (temporary!) compatibility folder? I am not sure if this causes more problems
# Only do that if you cannot solve all problems of the fgrep below.
ln -s /home/user /home/arch

# Switch to target user, to not have root permissions on snapshot folders etc.
su nicohood

# Search (and replace) old path in files
fgrep '/home/nicohood' ~ -R --exclude '*.log' --exclude '*.log.*' --exclude '*.LOG' --exclude '*.LOG.*' --exclude '*.log:*' --exclude '*.LOG:*'

# Known conflicts:
* Arduino sketchbook folder (Autofixed by application)
* Atom preferences, Opened files
* Nautilus bookmarks `nano ~/.config/gtk-3.0/bookmarks`
* dconf (Application settings) Check with: `gsettings list-recursively | fgrep '/home/nicohood'`
* Firefox cache (clear cache?)
* Spotify Cache (Autofixed by application) `.config/spotify/prefs`
* Vlc (Last Played files)
* Kodi (addons, database) -> Maybe reinstall addons?
* Fritzing part database (Unimportant to me)
* Several log files

# Verify and fix (bind) mounts and symlinks
mount | fgrep '/home/user'
find /home/user/ -xtype l

# Recreate symlinks
rm -rf ~/.cache/spotify
#rm -rf ~/.config/spotify
mkdir -p ~/data/spotify
ln -s ~/data/spotify ~/.cache/spotify
```
10. Reboot

11. Do system Maintenance again, check for any erros. Reenable all disabled services. Change any default password.

11. Backup this updated tutorial!!!

### Migration from 1.0.2 to 1.0.3
* Fix restore script transmitting unavailable snapshot.

### Migration from 1.0.1 to 1.0.2
* Fixed Bug "grub-mkconfig failes"

### Migration from 1.0.0 to 1.0.1
* Fixed restoring subvolumes when tmp or pkg subvolumes do not exist.
* Do not override existing backup files (fstab and grub config) on restoring.

### Migration from 0.18 to 1.0.0
Only the version number changed. This was used to reflect file system layout changes in the major version number, software changes in the minor version number and software fixes in the bugfix number.
```bash
# Add the newly introduced version number to the filesytem layout.
echo "1.0.0" | sudo tee /.btrfs/version.txt
```

### Migration 0.16 to 0.18
srv, pkg, log, tmp folder moved to snapshot layout, no excluded subvolumes anymore

```bash
# NOTE: Backup the current system using snap-sync!
# NOTE: Update snap-tools to 0.18 afterwards!
# This update can be done on a booted system!

# Move existing subvolumes
sudo su
cd /.btrfs
mv excludes/srv/ subvolumes/
mv excludes/pkg/ subvolumes/
mv excludes/log/ subvolumes/
mv excludes/tmp/ subvolumes/
rm excludes/ -r

# Create new snapshot subvolumes
cd snapshots
btrfs subvolume create srv
btrfs subvolume create pkg
btrfs subvolume create log
btrfs subvolume create tmp

# Create snapshot mount points
mkdir -p /var/cache/pacman/pkg/.snapshots
mkdir -p /var/tmp/.snapshots
mkdir -p /var/log/.snapshots
mkdir -p /srv/.snapshots

# Update fstab
# Change path of the old 4 subvolumes
# Add new entries for the 4 new snapshot subvolumes.
# Change the path to snapshot, edit the id and change the mount point!
# See sample config below.
# Use the following command to get the btrfs subvolume id:
btrfs subvolume list -o /.btrfs/snapshots
nano /etc/fstab

# Test mount
mount -a

# Write version and reboot!
echo "0.0.18" > /.btrfs/version.txt
mkinitcpio -P
reboot

# Configure snapper for newly added snapshots
# Do a backup of the newly added snapper configs.
# The pkg cache and tmp are still ignored/not configured as snapper configs.
nicohood.configure.snapper
```

```txt
/etc/fstab
----------
# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /var/cache/pacman/pkg   btrfs           rw,relatime,ssd,space_cache,subvolid=285,subvol=/subvolumes/pkg,subvol=subvolumes/pkg       0 0

# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /var/tmp        btrfs           rw,relatime,ssd,space_cache,subvolid=286,subvol=/subvolumes/tmp,subvol=subvolumes/tmp       0 0

# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /var/log        btrfs           rw,relatime,ssd,space_cache,subvolid=287,subvol=/subvolumes/log,subvol=subvolumes/log       0 0

# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /srv            btrfs           rw,relatime,ssd,space_cache,subvolid=288,subvol=/subvolumes/srv,subvol=subvolumes/srv       0 0


# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /var/cache/pacman/pkg/.snapshots   btrfs           rw,relatime,ssd,space_cache,subvolid=3291,subvol=/snapshots/pkg,subvol=snapshots/pkg       0 0

# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /var/tmp/.snapshots        btrfs           rw,relatime,ssd,space_cache,subvolid=3293,subvol=/snapshots/tmp,subvol=snapshots/tmp       0 0

# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /var/log/.snapshots        btrfs           rw,relatime,ssd,space_cache,subvolid=3292,subvol=/snapshots/log,subvol=snapshots/log       0 0

# /dev/mapper/cde1639a-009b-48f3-b38c-c4a04ab5e66e
UUID=8ab9a81d-fab4-4449-9c6e-5770b596ae2e       /srv/.snapshots            btrfs           rw,relatime,ssd,space_cache,subvolid=3290,subvol=/snapshots/srv,subvol=snapshots/srv       0 0
```

## System maintenance - After system recovery/clone
1. Check for missing Pacman files
```bash
# Get a list of all missing files.
# Usually only folders in /var/log are missing.
# Those can be regenerated by reinstalling the package (preferred)
# or by creating them manually (permissions might differ).
# After fixing the files, run the check again to verify.
# Some files might be created in .install files,
# which are only run on package installs, not upgrade/reinstalls.
pacman -Qn | sudo pacman -Q --check 1>/dev/null
```

2. Check for failed services
```
sudo journalctl -p 3 -xb
```

3. Check for broken symlinks, files or lost files
```bash
find "$HOME" -xtype l

sudo pacman -S lostfiles pacutils --needed
sudo lostfiles
sudo paccheck --md5sum --quiet
```

3. Fix snapper settings
Verify that pacman runs without errors (snap-pac) https://github.com/wesbarnett/snap-pac/issues/25

```bash
# Remove old snapshot configurations (or disable snapper service until next boot and fix afterwards)
nano /etc/conf.d/snapper
rm /etc/snapper/configs/repo

# Reenable/create new snapper configs
# Also make sure to set the snapshot interval. Some subvolumes like the log do not require much backups!
sudo nicohood.configure.snapper
```

4. Update and manage packages
```bash
sudo pacman -Syyu

# Make sure all most recent base packages are installed.
sudo pacman -S base base-devel --needed

# Check for modified config files:
pacman -Qii | grep ^MODIFIED | cut -f2

# List AUR packages, and check if all of them are manually installed or not required anymore (dropped by archlinux devs).
pacman -Qm

# Remove orphans:
sudo pacman -Rns $(pacman -Qtdq)

# Clean package cache:
sudo pacman -Sc

# TODO Check list of explicitely installed packages
```

5. Limit journald (logfile) size:

  ```bash
  sudo mkdir -p /etc/systemd/journald.conf.d
  sudo nano /etc/systemd/journald.conf.d/00-journal-size.conf
  -------------------------------------------------
  [Journal]
  SystemMaxUse=50M
  -------------------------------------------------
  sudo systemctl restart systemd-journald.service
  
  # Clean systemd logs (free ~2G)
  journalctl --vacuum-time=10d
  ```

6. Update Grub Bootloader
    Optional, not essentially required
    TODO

## After installation
* Change default user password `passwd`
* Change default Luks password (with gnome-disks).
* Update Arch Linux mirrorlist.
* Do user customization (with gnome-settings and gnome-tweaks tool)
* Enable ssh (via gnome settings)
* [Enable DNS caching](https://wiki.archlinux.org/index.php/NetworkManager#Enable_DNS_Caching)
* [Enable hostname resolution](https://wiki.archlinux.org/index.php/avahi#Hostname_resolution)
* [Enable color output for Pacman](https://wiki.archlinux.org/index.php/Color_output_in_console#pacman)
* Configure `~/.bashrc` and `/etc/inputrc` (see configs below)
* Configure `~/.makepkg.conf`
* Set plank theme to transparent: `plank --preferences` (must run in x11 mode)
* Check if `systemctl status rngd.service` is active, otherwise install `haveged` (e.g. if you have slow boot time)
* Enable [remote unlocking](https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlocking_.28hooks:_netconf.2C_dropbear.2C_tinyssh.2C_ppp.29)
* Setup snap-sync backups. Pay attention to use `backup/$HOSTNAME/custom` as location for the custom subvolumes. Otherwise they are not recognized properly while restoring.
* Limit journald (logfile) size, as described above.



### .bashrc
```
~/.bashrc
---------
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Improve color output
alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '

# Default editor
export EDITOR=nano

# Unlimited scrollback
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTCONTROL=ignoredups

# Use ssh-agent
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent > ~/.ssh-agent-thing
fi
if [[ "$SSH_AGENT_PID" == "" ]]; then
    eval $(<~/.ssh-agent-thing) > /dev/null
fi

# Enable "fuck" command
eval $(thefuck --alias)
```

### inputrc
```
/etc/inputrc
------------
[...]

# Use Shift+Up/Down to search history
"\e[1;2A": history-search-backward
"\e[1;2B": history-search-forward
```

### makepkg.conf
```
mkdir -p ~/data/makepkg/{src,pkg,srcpkg,log}
~/.makepkg.conf
---------------
PACKAGER="NicoHood <nicohood@archlinux.org>"
INTEGRITY_CHECK=sha512
MAKEFLAGS="-j$(nproc)"
COMPRESSXZ=(xz -9 -c -z - --threads=0)
BUILDDIR=/tmp/makepkg
SRCDEST=/home/user/data/makepkg/src
PKGDEST=/home/user/data/makepkg/pkg
SRCPKGDEST=/home/user/data/makepkg/srcpkg
LOGDEST=/home/user/data/makepkg/log
```

## TODO
* shellcheck
* AUR package
* Makefile
* Script names?
* Fix bug with subvolumes in nautilus https://gitlab.gnome.org/GNOME/glib/issues/1271
