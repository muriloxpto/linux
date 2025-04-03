#!/bin/bash

# Definir variáveis
DISK="/dev/sda"
ESP_PARTITION="${DISK}1"   # Partição EFI (para UEFI)
ROOT_PARTITION="${DISK}2"
SWAP_PARTITION="${DISK}3"
MOUNT_POINT="/mnt"
HOSTNAME="archlinux"
USERNAME="user"
PASSWORD="1234"

# Cria tabela GPT
parted -s "$DISK" mklabel gpt

# Cria partição EFI (FAT32, 512MB)
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on      # Sinaliza que é uma partição ESP

# Cria partição raiz (ext4, resto do disco)
parted -s "$DISK" mkpart primary ext4 513MiB 100%

# Formata as partições
mkfs.fat -F32 "$ESP_PARTITION"      # Formata ESP como FAT32
mkfs.ext4 "$ROOT_PARTITION"         # Formata root como ext4

# Monta as partições
mount "$ROOT_PARTITION" "$MOUNT_POINT"
mkdir /mnt/boot
mount "$ESP_PARTITION" /mnt/boot    # Monta ESP em /boot

# Instalação do sistema base
pacstrap "$MOUNT_POINT" base linux linux-firmware

# Gerar fstab
genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab"

# Entrar no chroot e configurar o sistema
arch-chroot "$MOUNT_POINT" /bin/bash <<EOF
    # Configurar fuso horário
    ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
    hwclock --systohc

    # Configurar locale
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "LC_TIME=pt_BR.UTF-8" >> /etc/locale.conf
    echo "LC_MONETARY=pt_BR.UTF-8" >> /etc/locale.conf

    # Definir hostname
    echo "$HOSTNAME" > /etc/hostname

    # Configurar rede (DHCP via systemd-networkd)
    systemctl enable systemd-networkd

    # Configurar initramfs
    mkinitcpio -P

    # Instalar e configurar o GRUB
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

    # Criar usuário
    useradd -m -G wheel "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd

    # Habilitar sudo para o usuário
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
EOF

# Desmontar e reiniciar
umount -R "$MOUNT_POINT"
echo "Instalação concluída! Reiniciando..."
reboot