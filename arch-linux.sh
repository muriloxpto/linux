#!/bin/bash

# --- Variáveis de Configuração ---
DISK="/dev/sda"
ESP_PARTITION="${DISK}1"   # Partição EFI (512MB)
ROOT_PARTITION="${DISK}2"  # Restante do disco
MOUNT_POINT="/mnt"
HOSTNAME="archlinux"
USERNAME="murilo"
PASSWORD="1234"
TIMEZONE="America/Sao_Paulo"
KEYMAP="bt-abnt2"                # Mapa de teclado padrão (altere se necessário)

# --- Particionamento ---
# Limpa a tabela de partições e cria nova tabela GPT
wipefs -a "$DISK"
parted -s "$DISK" mklabel gpt

# Cria partição EFI (FAT32, 512MB)
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on

# Cria partição raiz (ext4, resto do disco)
parted -s "$DISK" mkpart primary ext4 513MiB 100%

# Formata as partições
mkfs.fat -F32 "$ESP_PARTITION"
mkfs.ext4 -F "$ROOT_PARTITION"  # -F para forçar formatação rápida

# Monta as partições
mount "$ROOT_PARTITION" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/boot"
mount "$ESP_PARTITION" "$MOUNT_POINT/boot"

# --- Instalação Mínima ---
# Pacotes essenciais apenas (removido linux-firmware que pode ser instalado depois se necessário)
pacstrap "$MOUNT_POINT" base linux base-devel

# --- Configuração do Sistema ---
# Gera fstab com UUIDs para maior confiabilidade
genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab"

# Configuração via chroot
arch-chroot "$MOUNT_POINT" /bin/bash <<EOF
    # Configuração básica do sistema
    echo "$HOSTNAME" > /etc/hostname
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    hwclock --systohc --utc
    
    # Locale mínimo (apenas en_US.UTF-8)
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    echo "FONT=lat9w-16" >> /etc/vconsole.conf  # Fonte com suporte a acentos
    
    # Rede básica (systemd-networkd + systemd-resolved)
    systemctl enable systemd-networkd systemd-resolved
    
    # Initramfs mínimo
    mkinitcpio -P
    
    # Bootloader (GRUB mínimo)
    pacman -S --noconfirm --needed grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Usuário e senha
    useradd -m -G wheel "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    
    # Sudo simplificado (sem instalar o pacote sudo, usando do su)
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
    echo "Defaults !tty_tickets" >> /etc/sudoers  # Mantém sudo válido por mais tempo
    
    # Otimização: limpar cache pacman
    pacman -Scc --noconfirm
EOF

# --- Finalização ---
umount -R "$MOUNT_POINT"
echo "Instalação mínima concluída! Reiniciando em 5 segundos..."
sleep 5
reboot