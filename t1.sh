#!/usr/bin/env -S bash -e

# Fixing annoying issue that breaks GitHub Actions
# shellcheck disable=SC2001

# Cleaning the TTY.
clear

# Cosmetics (colours for text).
BOLD='\e[1m'
BRED='\e[91m'
BBLUE='\e[34m'  
BGREEN='\e[92m'
BYELLOW='\e[93m'
RESET='\e[0m'

# Pretty print (function).
info_print () {
    echo -e "${BOLD}${BGREEN}[ ${BYELLOW}•${BGREEN} ] $1${RESET}"
}

# Pretty print for input (function).
input_print () {
    echo -ne "${BOLD}${BYELLOW}[ ${BGREEN}•${BYELLOW} ] $1${RESET}"
}

# Alert user of bad input (function).
error_print () {
    echo -e "${BOLD}${BRED}[ ${BBLUE}•${BRED} ] $1${RESET}"
}

# Setting up a password for the user account (function).
    input_print "Please enter name for a user account (enter empty to not create one): "
    read -r username
# Hostname Selection
    input_print "Please enter the hostname: "
    read -r hostname


# Enable error handling.
set -euxo pipefail

# Enable logging.
LOGFILE="install.log"
exec &> >(tee -a "$LOGFILE")

# Configuration options. All variables should be exported, so that they will be availabe in the arch-chroot.
#export KEYMAP="de-latin1"
export LANG="en_US.UTF-8"
export LOCALE="en_US.UTF-8 UTF-8"
export TIMEZONE="America/Santo_Domingo"
export COUNTRY="US"
export HOSTNAME=$hostname
export USERNAME=$username
export PASSWORD=$USERNAME # It is not recommended to set production passwords here.
export EFIPARTITION=/dev/sda1
export ROOTPARTITION=/dev/nvme0n1p2
#export HOMEPARTITION=/dev/nvme0n1p5
#export EFIPARTITION=${DISK}p1
#export ROOTPARTITION=${DISK}p2
#export HOMEPARTITION=/dev/sda5
#export SWAPPARTITION=/dev/nvme0n1p5
export DISKID=$(lsblk $ROOTPARTITION -o partuuid -n)

# Find and set mirrors. This mirror list will be automatically copied into the installed system.
#pacman -Sy --needed --noconfirm reflector
#reflector --country $COUNTRY --age 20 --latest 15 --sort rate --protocol https --save /etc/pacman.d/mirrorlist

# Get the "/dev/..." name of the first partition, format it and mount.
mkfs.btrfs -f $ROOTPARTITION
mkfs.vfat $EFIPARTITION
mount $ROOTPARTITION /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt
mount -o subvol=@,defaults,ssd,autodefrag,noatime,nodiratime,compress-force=zstd:13 $ROOTPARTITION /mnt
mkdir /mnt/{boot,home,.snapshots,var}
mount -o subvol=@home,defaults,ssd,autodefrag,noatime,nodiratime,compress=zstd $ROOTPARTITION /mnt/home
mount -o subvol=@var,defaults,ssd,autodefrag,noatime,nodiratime $ROOTPARTITION /mnt/var
mount $EFIPARTITION /mnt/boot


# Install base files and update fstab.
pacstrap -K /mnt base linux linux-firmware git vim intel-ucode btrfs-progs
genfstab -U /mnt >> /mnt/etc/fstab

# Extend logging to persistant storage.
cp "$LOGFILE" /mnt/root/
exec &> >(tee -a "$LOGFILE" | tee -a "/mnt/root/$LOGFILE")

# This function will be executed inside the arch-chroot.
archroot() {
  # Enable error handling again, as this is technically a new execution.
  set -euxo pipefail

  # Set and generate locales.
  echo "LANG=$LANG" >> /etc/locale.conf
  #echo "KEYMAP=$KEYMAP" >> /etc/vconsole.conf
  sed -i "/$LOCALE/s/^#//" /etc/locale.gen # Uncomment line with sed
  locale-gen

  # Set time zone and clock.
  ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
  hwclock --systohc

  # Set hostname.
  echo "$HOSTNAME" > /etc/hostname

  # This is optional.
  # mkinitcpio -P
  
  # Install boot loader.
  #pacman -S --needed --noconfirm refind
  #pacman -S --needed --noconfirm grub
  #grub-install $DISK
  #grub-mkconfig -o /boot/grub/grub.cfg

  # Install and enable network manager.
  pacman -S --needed --noconfirm networkmanager
  systemctl enable NetworkManager
  # Install other packages
  pacman -S --needed --noconfirm efibootmgr openssh bluez bluez-utils blueman tlp tlp-rdw powertop acpi acpi_call xf86-video-intel wireless_tools nm-connection-editor network-manager-applet pavucontrol pulseaudio alsa-utils wpa_supplicant dialog wget nano neovim

  systemctl enable sshd
  systemctl enable bluetooth
  systemctl enable tlp
  #systemctl enable tlp-sleep
  systemctl enable fstrim.timer
  # Install and configure sudo.
  pacman -S --needed --noconfirm sudo
  sed -i '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' /etc/sudoers # Uncomment line with sed

  # Create a new user and add it to the wheel group.
  useradd -m -G wheel $USERNAME
  echo $USERNAME:$PASSWORD | chpasswd
  passwd -e $USERNAME # Force user to change password at next login.
  passwd -dl root # Delete root password and lock root account.

  # Fix too low entropy, that can cause a slow system start.
  pacman -S --needed --noconfirm haveged
  systemctl enable haveged

  # Install and configure the desktop environment.
  #pacman -S --needed --noconfirm gnome gnome-tweaks
  #systemctl enable gdm
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'de')]"
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"

  #sudo -u $USERNAME curl -o /home/$USERNAME/pexels-photo-2387793.jpeg "https://images.pexels.com/photos/2387793/pexels-photo-2387793.jpeg"
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.background picture-uri "/home/$USERNAME/pexels-photo-2387793.jpeg"

  # Install git as prerequisite for the next steps.
  pacman -S --needed --noconfirm git base-devel cargo 

  # Install an AUR helper.
  cd /tmp
  sudo -u $USERNAME git clone https://aur.archlinux.org/yay.git
  cd yay
  sudo -u $USERNAME makepkg -sri --noconfirm
  cd .. && rm -R yay
  sed -i '/^#Color/s/#//' /etc/pacman.conf # Uncomment line with sed

  # Check if a hypervisor is used and install the corresponding guest software.
  pacman -S --needed --noconfirm dmidecode 
  if [[ $(dmidecode -s system-product-name) == *"VirtualBox"* ]]; then
    pacman -S --needed --noconfirm linux-headers virtualbox-guest-utils
    systemctl enable vboxservice
  fi

  if [[ $(dmidecode -s system-product-name) == *"VMware Virtual Platform"* ]]; then
    pacman -S --needed --noconfirm linux-headers open-vm-tools xf86-video-vmware # Maybe gtkmm3, if needed.
    systemctl enable vmtoolsd
  fi

  # Install some software. 
  pacman -S --needed --noconfirm firefox konsole tmux man
  
  # Install boot manager. 
  #pacman -S --needed --noconfirm refind
  # Install boot loader.
  #refind-install
  #rm /boot/refind_linux.conf
  #tee -a /boot/refind_linux.conf <<EOF
#"Boot using default options" "root=PARTUUID=$DISKID rw add_efi_memmap initrd=boot\intel-ucode.img initrd=boot\initramfs-linux.img pcie_aspm=force acpi_osi="
#EOF

  #grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  #rub-mkconfig -o /boot/grub/grub.cfg
 # sed -i '/^#GRUB_DISABLE_OS_PROBER=false/s/#//' /etc/default/grub # Uncomment line with sed
 bootctl install
  tee -a /boot/loader/loader.conf <<EOF
default      arch.conf
timeout      0
editor       no
console-mode auto
EOF

##
  sed -i 's,#COMPRESSION="zstd",COMPRESSION="zstd",g' /etc/mkinitcpio.conf
  sed -i 's,MODULES=(),MODULES=(btrfs),g' /etc/mkinitcpio.conf
##
  tee -a /boot/loader/entries/arch.conf <<EOF
title Arch Linux  
linux /vmlinuz-linux  
initrd /intel-ucode.img  
initrd /initramfs-linux.img  
options root=$ROOTPARTITION rootfstype=btrfs rootflags=subvol=@ elevator=deadline add_efi_memmap rw quiet splash loglevel=3 vt.global_cursor_default=0 plymouth.ignore_serial_consoles vga=current rd.systemd.show_status=auto r.udev.log_priority=3 nowatchdog fbcon=nodefer i915.fastboot=1 i915.invert_brightness=1
EOF


mkinitcpio -p linux

  
  # Install some software and append some options to the corresponding config file.
  pacman -S --needed --noconfirm tilix
  cat >> /home/$USERNAME/.bashrc << 'EOT' 
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
        source /etc/profile.d/vte.sh
fi
EOT

  sudo -u $USERNAME yay -S --needed --noconfirm powerline powerline-fonts-git
  cat >> /home/$USERNAME/.bashrc << 'EOT'
powerline-daemon -q
POWERLINE_BASH_CONTINUATION=1
POWERLINE_BASH_SELECT=1
. /usr/share/powerline/bindings/bash/powerline.sh
EOT

  # Append some options to config files.
  cat >> /home/$USERNAME/.vimrc << 'EOT'
let g:powerline_pycmd="py3"
set rtp+=/usr/lib/python3.*/site-packages/powerline/bindings/vim
set laststatus=2
syntax enable
EOT

  cat >> /home/$USERNAME/.tmux.conf << 'EOT'
set -g default-terminal "screen-256color"
source /usr/lib/python3.*/site-packages/powerline/bindings/tmux/powerline.conf
EOT

  # Install and set an icon theme for Gnome.
  #sudo -u $USERNAME paru -S --needed --noconfirm paper-icon-theme-git
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Paper'

  # This is an example of how to install packages by custom groups. Adapt as you like.
  # The list below is an example for a pentest machine.
  #declare -A PACKAGES
  #PACKAGES[TOOLS]="dnsutils"
  #PACKAGES[RECON]="nikto sslscan wireshark-qt exploitdb"
  #PACKAGES[ENUM]="enum4linux sqlmap gobuster wfuzz wpscan"
  #PACKAGES[SCANNING]="nmap masscan"
  #PACKAGES[SPOOFING]="responder"
  #PACKAGES[EXPLOITATION]="metasploit"

  #for package in ${PACKAGES[@]}; do
  #  sudo -u $USERNAME paru -S --needed --noconfirm $package \
  #    || echo "$package" >> /home/$USERNAME/packages-with-errors.txt
  #done
  
  # Reconfigure sudo, so that a password is need to elevate privileges.
  sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/# //' /etc/sudoers # Uncomment line with sed
  sed -i '/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^/# /' /etc/sudoers # Comment line with sed
  echo "Finished archroot." 
}

# Export the function so that it is visible by bash inside arch-chroot.
export -f archroot
arch-chroot /mnt /bin/bash -c "archroot" || echo "arch-chroot returned: $?"

# Lazy unmount.
#umount -l /mnt

cat << 'EOT'
******************************************************
* Finished. You can now reboot into your new system. *
******************************************************
EOT
