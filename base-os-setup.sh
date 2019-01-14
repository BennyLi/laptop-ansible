#! /usr/bin/env sh

# Sources of this process:
# * https://legacy.thomas-leister.de/arch-linux-luks-verschluesselt-auf-uefi-system-installieren-2/


# Load the key for your country
loadkeys de-latin1-nodeadkeys

# We want to use encryption, so we have to load the kernel module for this
modprobe dm-crypt

# Lets connect to wifi
wifi-menu


# Let's do the partitioning
# First check which one is your main harddrive
lsblk
read -p "Enter your device [/dev/sda]: " installdisk
if [ -z "$installdisk" ]; then
  installdisk="/dev/sda"
fi

read -p "We will do the partitioning on $installdisk. This will erase all data! Is $installdisk correct? [y/N] " correct

if [ "$correct" == "Y" ] || [ "$correct" == "y" ]; then
  echo "DO IT"
else
  echo "Aborting..."
fi


# We will now do the partitioning
# First: Erase the current partitions from the disk
echo "Erasing old partition scheme..."
wipefs --all --backup $installdisk
echo "Backup file of old partition scheme should be here: $(ls ~/wipefs-*.bak)"
