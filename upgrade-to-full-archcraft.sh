#!/bin/bash
# Archcraft Ultra-Deep System Upgrade & Maximum Maintenance Script
# Credits: script by 0b.livion (Discord: 0b.livion)

set -e

echo "==============================================================="
echo "        Archcraft Ultra-Deep System Maintenance Tool"
echo "        By 0b.livion (Discord: 0b.livion)"
echo "==============================================================="
echo ""
echo "[1] Full deep upgrade WITH backup"
echo "[2] Full deep upgrade (NO backup, faster and riskier)"
echo ""

read -p "Choose upgrade type (1 or 2): " mode

do_backup() {
  echo "==> [BACKUP] Starting pre-upgrade system backup..."
  backup_dir=~/archcraft_backup_$(date +"%Y%m%d_%H%M%S")
  mkdir -p "$backup_dir"
  echo "   Backing up /etc, /home, user dotfiles, pacman/aur package lists, and fstab..."
  sudo rsync -aAXv --exclude="$backup_dir" /etc "$backup_dir/"
  rsync -aAXv --exclude="$backup_dir" ~ "$backup_dir/home_backup/"
  pacman -Qqe > "$backup_dir/pacman_pkglist.txt"
  yay -Qqe > "$backup_dir/yay_pkglist.txt" 2>/dev/null || true
  cp /etc/fstab "$backup_dir/fstab.bak" 2>/dev/null || true
  cp -r ~/.config "$backup_dir/user_dotconfig" 2>/dev/null || true
  echo "==> [BACKUP] Backup complete! Saved to $backup_dir"
  echo ""
}

if [[ "$mode" == "1" ]]; then
  do_backup
elif [[ "$mode" == "2" ]]; then
  echo "==> Proceeding with FULL UPGRADE (NO BACKUP)..."
else
  echo "Invalid selection. Exiting."
  exit 1
fi

echo "==> [SYSTEM] Full package, firmware, microcode, kernel, and keyring update (hardcore deep system update)"
sudo pacman -Syu --noconfirm
sudo pacman -Syyu --noconfirm
sudo pacman -Fy --noconfirm
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman-key --populate
sudo pacman-key --refresh-keys
sudo pacman -Sy archlinux-keyring --noconfirm || true

echo "==> [SECURITY] Refreshing trust DB, pacman updaters, and any possible root CA stores"
sudo trust extract-compat || true
sudo update-ca-trust extract || true
sudo update-ca-certificates || true
sudo trust list || true

echo "==> [AUR] Upgrading ALL AUR and custom repo packages, including obscure ones!"
if ! command -v yay &> /dev/null; then
  echo "==> yay not found. Installing yay..."
  sudo pacman -S --needed --noconfirm base-devel git
  git clone https://aur.archlinux.org/yay.git ~/yay
  cd ~/yay
  makepkg -si --noconfirm
  cd ~
  rm -rf ~/yay
fi
yay -Syu --devel --timeupdate --noconfirm

echo "==> [BOOTLOADERS] Deep UEFI/GRUB/systemd-boot/LILO/refind upgrade & configuration"
if [[ -d /boot/efi ]]; then
  sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || true
  sudo bootctl update || true           # systemd-boot
  sudo refind-install || true           # refind
else
  sudo grub-install --target=i386-pc /dev/sda || true
fi
sudo grub-mkconfig -o /boot/grub/grub.cfg

if [ -x "$(command -v efibootmgr)" ]; then
  sudo efibootmgr || true
fi

echo "==> [FIRMWARE/MICROCODE] Updating UEFI, fwupd, and all microcode blobs"
if [ -x "$(command -v fwupdmgr)" ]; then
  sudo fwupdmgr refresh --force || true
  sudo fwupdmgr get-updates || true
  sudo fwupdmgr update --force || true
fi
sudo pacman -S --needed --noconfirm intel-ucode amd-ucode

echo "==> [KERNEL/INITRD] Rebuilding all kernels/initramfs and refreshing hooks"
sudo mkinitcpio -P || true
sudo dracut --regenerate-all --force || true 2>/dev/null
sudo update-initramfs -u -k all || true 2>/dev/null

echo "==> [SYSTEMD/CORE] Full systemd, journal, login daemon, and logrotate hard refresh"
sudo systemctl daemon-reexec
sudo systemctl restart systemd-journald
sudo systemctl restart systemd-logind
sudo journalctl --vacuum-time=7d
sudo logrotate -f /etc/logrotate.conf || true

echo "==> [DB/DBUS] Restarting/refreshing DBus, polkit, GConf, and hardware DBs"
sudo systemctl restart dbus || true
sudo systemctl restart polkit || true
sudo pacman -S --needed --noconfirm hwdata pciids usbutils || true
sudo update-pciids || true
sudo update-usbids || true

echo "==> [ESSENTIAL SYSTEM] Updating all must-have tool and hardware packages and euro mega-list"
sudo pacman -S --needed --noconfirm \
  linux-firmware reflector archlinux-keyring alsa-utils alsa-plugins pulseaudio pipewire pipewire-pulse \
  base base-devel linux linux-headers util-linux openssh \
  networkmanager network-manager-applet pavucontrol xdg-utils xorg xorg-xinit mesa mesa-utils \
  xf86-video-intel xf86-video-amdgpu xf86-video-nouveau intel-ucode amd-ucode nvidia nvidia-utils \
  sudo grub efibootmgr os-prober mtools dosfstools ntfs-3g exfat-utils lvm2 btrfs-progs sgdisk parted gparted \
  dmraid mdadm cryptsetup strace ltrace lsof inxi hwinfo mcelog iotop powertop git htop neofetch btop \
  qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat \
  firewalld ufw nftables iptables smartmontools glib2 net-tools wireless_tools \
  bluez bluez-utils blueman wireless-regdb upower tlp powertop cpupower acpi acpid \
  systemd-resolvconf systemd-sysvcompat dosfstools sdl2 gsettings-desktop-schemas \
  fuse3 squashfs-tools zram-generator cpupower

echo "==> [FILESYSTEMS/SMART] Checking all disks, devices, and even some passed-through devices"
if sudo smartctl --scan | grep -q '/dev/'; then
  for disk in $(sudo smartctl --scan | awk '{print $1}'); do
    sudo smartctl -a "$disk" || true
    sudo smartctl -t short "$disk" || true
  done
fi

for part in $(lsblk -nrpo NAME,TYPE | awk '$2=="part"{print $1}'); do
  mountpoint=$(lsblk -nrpo NAME,MOUNTPOINT | grep "^$part " | awk '{print $2}')
  if [[ -z "$mountpoint" ]]; then
    sudo fsck -n "$part" || true
  fi
done

echo "==> [FSTAB/LABELS/UUIDS] Verifying /etc/fstab, mounting test, and rebuilding UUID caches"
sudo findmnt --verify --tab-file /etc/fstab || true
sudo blkid -c /dev/null || true

echo "==> [DESKTOP/WINDOW MANAGER/ALL PACKAGES] Reinstalling and repairing all desktop environments, shells and X configs"
sudo pacman -S --needed --noconfirm \
  bspwm sxhkd openbox nitrogen lxappearance picom dmenu rofi polybar \
  alacritty termite kitty xfce4-terminal xterm thunar thunar-archive-plugin thunar-volman tumbler ranger \
  pcmanfm feh lxpolkit lxsession lxqt-policykit \
  mousepad leafpad geany gvfs gvfs-mtp gvfs-gphoto2 gvfs-afc gvfs-smb gvfs-nfs \
  flameshot scrot gimp inkscape pinta viewnior \
  mpv vlc pavucontrol pamixer pulseaudio-alsa \
  firefox chromium qutebrowser gedit code sublime-text libreoffice-fresh okular evince zathura \
  arc-gtk-theme arc-icon-theme tela-circle-theme tela-circle-icon-theme papirus-icon-theme \
  ttf-jetbrains-mono ttf-fira-code ttf-dejavu nerd-fonts-complete \
  lxappearance-gtk3 lxappearance-obconf lxappearance-openbox \
  wget curl git unzip tar zip p7zip lzop lz4 xarchiver \
  networkmanager lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings \
  conky lxrandr arandr redshift dunst xfce4-notifyd dunstify \
  htop btop neofetch screenfetch flameshot playerctl xdotool wmctrl

echo "==> [EXTRAS] (Re)installing core plugins, input/IME, drivers, and obscure system packages"
sudo pacman -S --needed --noconfirm \
  fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool input-leap ttf-opensans ttf-liberation ttf-croscore \
  xdg-desktop-portal-gtk xdg-desktop-portal xdg-user-dirs glibc-locales udisks2 udiskie

echo "==> [ARCHCRAFT] Updating all exclusive themes, configs, extras, powermenus, shell scripts"
yay_pkg_list=(
  archcraft-wallpapers archcraft-grub-theme archcraft-iso-scripts
  archcraft-plymouth-themes archcraft-themes archcraft-polybar
  archcraft-rofi archcraft-bspwm archcraft-sxhkd
  archcraft-openbox archcraft-picom archcraft-conky
  archcraft-lxappearance archcraft-terminals
  archcraft-bling archcraft-powermenu archcraft-pkglist
  picom-git
)
yay -S --noconfirm --devel --timeupdate "${yay_pkg_list[@]}"

echo "==> [CONFIGS] Fetching and applying all official and dotfile configs for all DE and WM"
git clone https://github.com/archcraft-os/configs.git ~/archcraft-configs
cp -rf ~/archcraft-configs/* ~/.config/
rm -rf ~/archcraft-configs

echo "==> [CLEANUP] Orphan/package cache, deep python/flatpak/snap/node/npm/pip cache clear"
sudo pacman -Rns --noconfirm $(pacman -Qtdq) || true
sudo pacman -Sc --noconfirm
sudo paccache -r || true
pip cache purge || true
npm cache clean --force || true
yarn cache clean || true
flatpak uninstall --unused -y || true
snap set system refresh.retain=2; sudo snap remove --purge $(snap list --all | awk '/disabled/{print $1, $2}') || true

echo "==> [REPAIRS] Touching rebuilds and database resyncs"
fc-cache -fv
gtk-update-icon-cache /usr/share/icons/* || true
sudo updatedb || true
glib-compile-schemas /usr/share/glib-2.0/schemas || true
gdk-pixbuf-query-loaders --update-cache || true
sudo ldconfig
sudo depmod -a
sudo udevadm trigger --type=devices --action=change || true

echo "==> [SYSTEM SERVICES RE-ENABLE] Enabling, upgrading and restarting ALL critical services"
sudo systemctl daemon-reload
for svc in NetworkManager bluetooth lightdm dbus polkit systemd-timesyncd chronyd cups upower fstrim.timer; do
  sudo systemctl enable $svc || true
  sudo systemctl restart $svc || true
done

echo "==> [DEEP AI] Flushing D-Bus, XDG, user, and even obscure caches no one fixes"
rm -rf ~/.cache/*
rm -rf ~/.config/chromium/ShaderCache/*
sudo sysctl -w vm.drop_caches=3

echo "==> [ULTRA] Making sure literally every database, extension, core, and secret sauce updated"
sudo update-mime-database /usr/share/mime || true
sudo mandb -c || true
sudo icon-cache-update || true 2>/dev/null
sudo fontconfig-infinality-ultimate || true 2>/dev/null

echo "==> [ULTIMATE FINISH] All possible deep upgrades and secret stuff completed. Please REBOOT for full effect!"
echo ""
echo "  Script by 0b.livion (Discord: 0b.livion)"
