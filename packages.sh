#!/usr/bin/env bash

#Main Packages
yay -S hyprland nano openssh pacman-contrib sddm-git waybar-hyprland-git

#Bar Tools
yay -S rofi swayidle swaylock-effects swww  waybar-updates 
#Install Fonts
yay -S adobe-source-code-pro-fonts ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-common ttf-jetbrains-mono  

#Installaudio components 
yay -S pipewire wireplumber pavucontrol pipewire-audio pipewire-pulse pipewire-alsa

#Bluetooth components 
yay -S bluez bluez-utils blueman 

#File manager
yay -S thunar gvfs thunar-archive-plugin file-roler thunar-media-tags-plugin thunar-volman thunar-shares-plugin tumbler gvfs-mtp 

#Other packages
yay -S gnome-keyring jq polkit-kde-agent qt6-base qt5-base

#Screenshot
yay -S lua maim slurp wl-clipboard

##Backup Tools