# --- CONFIGURAÇÕES (EDITÁVEIS) ---
DISK="/dev/sda"                # Disco a ser particionado
HOSTNAME="archlinux"           # Hostname da máquina
USER="user"                    # Nome do usuário padrão
PASSWORD="1234"                # Senha do usuário e root (ALTERE ANTES DE USAR!)
TIMEZONE="America/Sao_Paulo"   # Fuso horário
LOCALE="en_US.UTF-8"           # Idioma
KEYMAP="br-abnt2"              # Layout do teclado

# --- VERIFICAÇÃO DE UEFI/BIOS ---
if [ -d /sys/firmware/efi/efivars ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

# --- VERIFICAÇÃO DE INTERNET ---
echo "Verificando conexão com a internet..."
if ! ping -c 3 archlinux.org &> /dev/null; then
    echo "ERRO: Sem internet! Configure manualmente e tente novamente."
    exit 1
fi

# --- CONFIGURAR TECLADO ---
loadkeys "$KEYMAP"

# --- PARTICIONAMENTO AUTOMÁTICO (UEFI ou BIOS) ---
echo "Particionando $DISK..."
parted -s "$DISK" mklabel gpt

if [ "$BOOT_MODE" = "UEFI" ]; then
    parted -s "$DISK" mkpart primary fat32 1MiB 512MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary ext4 512MiB 100%
else  # BIOS
    parted -s "$DISK" mkpart primary ext4 1MiB 100%
    parted -s "$DISK" set 1 boot on
fi

# --- FORMATAÇÃO ---
echo "Formatando partições..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.fat -F32 "${DISK}1"
    mkfs.ext4 -F "${DISK}2"
else
    mkfs.ext4 -F "${DISK}1"
fi

# --- MONTAGEM ---
if [ "$BOOT_MODE" = "UEFI" ]; then
    mount "${DISK}2" /mnt
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi
else
    mount "${DISK}1" /mnt
fi

# --- INSTALAÇÃO DOS PACOTES MÍNIMOS ---
echo "Instalando pacotes básicos..."
pacstrap -K /mnt base linux linux-firmware networkmanager sudo

# --- GERAR FSTAB ---
echo "Gerando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- CONFIGURAÇÃO DO CHROOT ---
echo "Configurando sistema instalado..."
arch-chroot /mnt /bin/bash <<EOF
# --- RELÓGIO E FUSO HORÁRIO ---
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# --- LOCALE (IDIOMA) ---
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# --- TECLADO ---
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# --- HOSTNAME ---
echo "$HOSTNAME" > /etc/hostname

# --- HOSTS ---
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# --- SENHAS (ROOT E USUÁRIO) ---
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USER"
echo "$USER:$PASSWORD" | chpasswd

# --- SUDOERS ---
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# --- HABILITAR NETWORKMANAGER ---
systemctl enable NetworkManager

# --- INSTALAR GRUB (UEFI ou BIOS) ---
if [ "$BOOT_MODE" = "UEFI" ]; then
    pacman -S grub efibootmgr --noconfirm
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
else
    pacman -S grub --noconfirm
    grub-install "$DISK"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

# --- FINALIZAR ---
echo "Desmontando e Desligando..."
umount -R /mnt
echo "Instalação concluída! Desligando em 5 segundos..."
sleep 5
poweroff