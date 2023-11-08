#!/bin/bash

# Ensure that you are running the script as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Set the hostname for your Debian system
hostname="Haunter"

# Set the password for the root user (change this)
root_password="06/07"

# Set your wireless network SSID and password
wifi_ssid=""
wifi_password=""



root_partition="/dev/sda2"
efi_partition="/dev/sda1"
# Get the PARTUUID of the EFI system partition
efi_partuuid=$(lsblk -no PARTUUID $efi_partition)
# Replace /dev/sda1 with your EFI system partition


# If the PARTUUID is empty or not found, exit the script
if [ -z "$efi_partuuid" ]; then
    echo "EFI system partition PARTUUID not found. Please check your partition setup."
    exit 1
fi

# Format the root partition (e.g., as ext4)
mkfs.ext4 $root_partition

#mount the partitions
mount $root_partition /mnt

# Format the EFI system partition (e.g., as vfat)
mkfs.vfat -F32 $efi_partition

mkdir -p /mnt/boot/efi
mount $efi_partition /mnt/boot/efi

# Configure the network interfaces
echo "auto lo" > /etc/network/interfaces
echo "iface lo inet loopback" >> /etc/network/interfaces
echo "auto eth0" >> /etc/network/interfaces
echo "iface eth0 inet dhcp" >> /etc/network/interfaces
echo "auto wlan0" >> /etc/network/interfaces
echo "iface wlan0 inet dhcp" >> /etc/network/interfaces
wpa_passphrase "$wifi_ssid" "$wifi_password" >> /etc/network/interfaces

# Update the package list
apt update

# Install the base system and Xorg
debootstrap --variant=minbase bookworm /mnt
chroot /mnt apt-get install -y libxft-dev libxinerama-dev make gcc g++ libx11-dev fonts-dejavu xserver-xorg-core

# Install efibootmgr
chroot /mnt apt-get install -y efibootmgr

# Mount necessary file systems
mount --bind /dev /mnt/dev
mount --bind /dev/pts /mnt/dev/pts
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

#copy the hosts /etc/resolv.conf
cp /etc/resolv.conf /mnt/etc/

# Create /etc/fstab for the chroot environment
# This script generates /etc/fstab based on the current disk configuration
# Customize the generated /etc/fstab as needed
cat << EOF > /mnt/etc/fstab
# /etc/fstab
$(blkid -o list | awk -F'=' '{print $1, $2}' | sed 's/"//g')
EOF

# Change root into the new system
chroot /mnt /bin/bash

# Set the root password
echo "root:$root_password" | chpasswd

# Set the hostname
echo "$hostname" > /etc/hostname

# Configure the network
echo "127.0.0.1 localhost $hostname" > /etc/hosts
echo "::1 localhost $hostname" >> /etc/hosts

# Install wireless tools
apt install -y wireless-tools wpasupplicant

# Configure wireless networking
wpa_supplicant -B -i wlan0 -c /etc/network/interfaces

# Update the package list again
apt update

# Clean up
apt clean
rm -rf /var/lib/apt/lists/*

# Set up an EFI boot entry using the PARTUUID
efibootmgr --create --disk /dev/sda --part 1 --loader /EFI/debian/grubx64.efi --label "Debian" --partuuid $efi_partuuid

# Exit the chroot environment
exit

# Unmount file systems
umount /mnt/dev/pts
umount /mnt/dev
umount /mnt/proc
umount /mnt/sys

# Reboot to complete the installation
reboot


