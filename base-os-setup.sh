#! /usr/bin/env sh

# Sources of this process:
# * https://legacy.thomas-leister.de/arch-linux-luks-verschluesselt-auf-uefi-system-installieren-2/


# Load the key for your country
loadkeys de-latin1-nodeadkeys

# We want to use encryption, so we have to load the kernel module for this
modprobe dm-crypt

hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true



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

echo "Converting disk to GPT format"
sgdisk --mbrtogpt $installdisk
echo "Creating EFI boot partition..."
sgdisk --new 1:2048:+512M -t ef00 --change-name="EFI Boot2" $installdisk
echo "Creating Linux LVM partition filling rest of device..."
sgdisk --new 2:0:0 --change-name="Linux LVM" $installdisk
echo "Partitioning done!"
echo


echo "Next step is the encryption."
echo "A benchmark will be run and you can choose the emcryption type."
read -p "Hit any key to continue..."
cryptsetup benchmark
read -p "Enter the encryption you want to use: " $encryptiontype
cryptsetup -c $encryptiontype -y -s 512 luksFormat ${installdisk}2

echo "Creating LVM container..."
cryptsetup luksOpen ${installdisk}2 lvm
pvcreate /dev/mapper/lvm
vgcreate main /dev/mapper/lvm
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB
lvcreate -L ${swap_size} -n swap main
lvcreate -l 100%FREE -n root main

mkswap /dev/mapper/main-swap
mkfs.ext4 /dev/mapper/main-root

mount /dev/mapper/main-root /mnt
mkdir /mnt/boot
mount ${installdisk}1 /mnt/boot
swapon /dev/mapper/main-swap

mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
curl -s "https://www.archlinux.org/mirrorlist/?country=DE&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | tee -a /etc/pacman.d/mirrorlist

pacstrap /mnt/ base base-devel wpa_supplicant dialog
genfstab -p /mnt > /mnt/etc/fstab

arch-chroot /mnt/
