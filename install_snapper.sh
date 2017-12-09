#!/bin/bash

# Install snapper
sudo pacman -S --needed --asexplicit snapper snap-pac

# root config
sudo umount /.snapshots
sudo rm /.snapshots/ -r
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots/
sudo mkdir /.snapshots

# home config
sudo umount /home/.snapshots
sudo rm /home/.snapshots/ -r
sudo snapper -c home create-config /home
sudo btrfs subvolume delete /home/.snapshots/
sudo mkdir /home/.snapshots

# repo config
sudo umount /repo/.snapshots
sudo snapper -c repo create-config /repo
sudo btrfs subvolume delete /repo/.snapshots/
sudo mkdir /repo/.snapshots

# Remount subvolumes
sudo mount -a

# Enable services
sudo systemctl enable --now snapper-boot.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl enable --now snapper-timeline.timer
