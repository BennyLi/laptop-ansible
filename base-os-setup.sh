#! /usr/bin/env sh

# Sources of this process:
# * https://legacy.thomas-leister.de/arch-linux-luks-verschluesselt-auf-uefi-system-installieren-2/
# * https://disconnected.systems/blog/archlinux-installer/#the-complete-installer-script


# Exit with a clear message on failures
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR


# Load the key for your country
loadkeys de-latin1-nodeadkeys


#####  Get some user input for variable data  ##### {{{1

hostname=$(dialog --stdout --inputbox "Enter hostname / name of your computer" 0 0) || exit 1
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


#####  Set up logging  ##### {{{1
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")


#####  Internet connectivity  ##### {{{1

# Check connectivity
ping -c 1 8.8.8.8 >> /dev/null
if [[ "$?" == "0" ]]; then 
  echo "Already connected to the internet."
else
  # Lets connect to the internet
  wifi=$(dialog --stdout --menu "Do you want to connect via wifi or ethernet?" 0 0 0 0 ethernet 1 wifi) || exit 1
  if [ "$wifi" == "1" ]; then
    wifi-menu
  else
    interfaces=$(ip -o link | awk '{ gsub(":","",$1); gsub(":","",$2); print $2 " " $1 }')
    interface=$(dialog --stdout --menu "Select network interface" 0 0 0 $interfaces)
    dhcpcd $interface
  fi
  
  # Check connectivity
  ping -c 1 8.8.8.8 >> /dev/null
  [[ "$?" == "0" ]] || ( echo "No network connection! Please try again..."; exit 1; )
fi

# Setup clock
timedatectl set-ntp true


#####  Partitioning  ##### {{{1
correct=$(dialog --stdout --menu "We will do the partitioning on $device. This will erase all data! Is $device correct?" 0 0 0 N No Y Yes)
[[ "$correct" == "Y" ]] || ( echo "Aborting due to user interaction..."; exit 1 )


# We will now do the partitioning
# First: Erase the current partitions from the disk
echo "Erasing old partition scheme..."
wipefs --all --backup $device
echo "Backup file of old partition scheme should be here: $(ls ~/wipefs-*.bak)"

echo "Converting disk to GPT format"
sgdisk --mbrtogpt $device
echo "Creating EFI boot partition..."
sgdisk --new 1:2048:+512M -t ef00 --change-name="EFI Boot2" $device
echo "Creating Linux LVM partition filling rest of device..."
sgdisk --new 2:0:0 --change-name="Linux LVM" $device
echo "Partitioning done!"
echo


#####  Encryption  ##### {{{1

# We want to use encryption, so we have to load the kernel module for this
modprobe dm-crypt

echo "Next step is the encryption."
#echo "A benchmark will be run and you can choose the encryption type."
#read -p "Hit any key to continue..."
#cryptsetup benchmark
#read -p "Enter the encryption you want to use: " $encryptiontype
encryptiontype="aes-xts-plain"
keysize="512"
cryptsetup -c $encryptiontype -y -s $keysize luksFormat ${device}2

echo "Creating LVM container..."
cryptsetup luksOpen ${device}2 lvm
pvcreate /dev/mapper/lvm
vgcreate main /dev/mapper/lvm
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB
lvcreate -L ${swap_size} -n swap main
lvcreate -l 100%FREE -n root main

echo "Creating file system..."
mkswap /dev/mapper/main-swap
mkfs.ext4 /dev/mapper/main-root

echo "Mounting system..."
mount /dev/mapper/main-root /mnt
mkdir /mnt/boot
mount ${device}1 /mnt/boot
swapon /dev/mapper/main-swap


#####  System preperation and base install  ##### {{{1

echo "Updating mirror list for germany..."
mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
curl -s "https://www.archlinux.org/mirrorlist/?country=DE&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | tee -a /etc/pacman.d/mirrorlist

echo "Installing base system packages..."
pacstrap /mnt/ base base-devel wpa_supplicant dialog git fish ansible gummiboot

echo "Generating fstab..."
genfstab -p /mnt > /mnt/etc/fstab

echo "Setting hostname..."
echo $hostname > /mnt/etc/hostname

echo "Generating locales..."
echo "LANG=de_DE.UTF-8" > /mnt/etc/locale.conf
sed -i 's/^#de_DE/de_DE/g' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen

echo "Keyboard layout and localtime..."
echo KEYMAP=de-latin1 > /mnt/etc/vconsole.conf
arch-chroot /mnt/ ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime


#####  Configure boot  ##### {{{1

echo "Configuring bootmenu..."
sed -i 's/^HOOKS=.*/HOOKS="base udev autodetect modconf block keyboard keymap encrypt lvm2 filesystems fsck"/g' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux
arch-chroot /mnt gummiboot --path=/boot install

cat <<EOF > /mnt/boot/loader/loader.conf
default arch
EOF

cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  cryptdevice=${device}2:main root=/dev/mapper/main-root resume=/dev/mapper/main-swap lang=de locale=de_DE.UTF-8
EOF


#####  User setup  ##### {{{1

echo "Setting up you (the user)..."
arch-chroot /mnt useradd --create-home --user-group --shell /usr/bin/fish --groups wheel,uucp,video,audio,storage,optical,games,input "$user"
arch-chroot /mnt chsh -s /usr/bin/fish


#####  Finish setup  ##### {{{1

umount /mnt/boot
umount /mnt

echo "All done!"
read -p "Remove the USB stick and press [Enter] to reboot to your new system..." $key
reboot
