#!/bin/bash

# --- CONFIGURAÇÕES (EDITÁVEIS) ---
DISK="/dev/sda"                # Disco a ser particionado
HOSTNAME="archlinux"           # Hostname da máquina
USER="user"                    # Nome do usuário padrão
PASSWORD="1234"                # Senha do usuário e root (ALTERE ANTES DE USAR!)
TIMEZONE="America/Sao_Paulo"   # Fuso horário
LOCALE="en_US.UTF-8"           # Idioma
KEYMAP="br-abnt2"              # Layout do teclado
REFLECTOR_COUNTRIES=("Brazil" "United_States")  # Países para mirrors

# --- FUNÇÃO DE TRATAMENTO DE ERROS ---
error_handler() {
    local exit_code=$?
    echo -e "\n[ERRO] O script falhou na linha $1 com status $exit_code"
    echo "Último comando executado:"
    echo "$BASH_COMMAND"
    
    # Tentativa de desmontar sistemas de arquivos se estiverem montados
    if mount | grep -q "/mnt"; then
        umount -R /mnt 2>/dev/null
    fi
    
    exit $exit_code
}

# Habilitar tratamento de erros
trap 'error_handler $LINENO' ERR
set -e -o pipefail

# --- VERIFICAÇÃO DE VMWARE ---
if dmesg | grep -qi "vmware"; then
    VMWARE="YES"
    echo "VMware detectado, instalando drivers otimizados..."
else
    VMWARE="NO"
fi

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
loadkeys "$KEYMAP" || {
    echo "ERRO: Falha ao carregar o mapa de teclado $KEYMAP"
    exit 1
}

# --- ATUALIZAR MIRRORS COM REFLECTOR ---
echo "Atualizando lista de mirrors com reflector..."
if ! pacman -Sy reflector --noconfirm; then
    echo "AVISO: Não foi possível instalar reflector, usando mirrors padrão"
else
    # Criar backup do mirrorlist original
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # Gerar novo mirrorlist com os melhores mirrors
    reflector_cmd="reflector --latest 20 --protocol https --sort rate"
    
    for country in "${REFLECTOR_COUNTRIES[@]}"; do
        reflector_cmd+=" --country ${country}"
    done
    
    eval "$reflector_cmd --save /etc/pacman.d/mirrorlist"
    
    echo "Mirrors atualizados com sucesso!"
    pacman -Syy  # Atualizar bancos de dados
fi

# --- PARTICIONAMENTO AUTOMÁTICO (UEFI ou BIOS) ---
echo "Particionando $DISK..."
if ! parted -s "$DISK" mklabel gpt; then
    echo "ERRO: Falha ao criar tabela de partição GPT"
    exit 1
fi

if [ "$BOOT_MODE" = "UEFI" ]; then
    parted -s "$DISK" mkpart primary fat32 1MiB 512MiB || exit 1
    parted -s "$DISK" set 1 esp on || exit 1
    parted -s "$DISK" mkpart primary ext4 512MiB 100% || exit 1
else
    parted -s "$DISK" mkpart primary 1MiB 2MiB || exit 1
    parted -s "$DISK" set 1 bios_grub on || exit 1
    parted -s "$DISK" mkpart primary ext4 2MiB 100% || exit 1
fi

# --- FORMATAÇÃO ---
echo "Formatando partições..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.fat -F32 "${DISK}1" || exit 1
    mkfs.ext4 -F "${DISK}2" || exit 1
else
    mkfs.ext4 -F "${DISK}2" || exit 1
fi

# --- MONTAGEM ---
if [ "$BOOT_MODE" = "UEFI" ]; then
    mount "${DISK}2" /mnt || exit 1
    mkdir -p /mnt/boot/efi || exit 1
    mount "${DISK}1" /mnt/boot/efi || exit 1
else
    mount "${DISK}2" /mnt || exit 1
fi

# --- PACOTES BASE ---
BASE_PACKAGES="base linux linux-firmware networkmanager sudo reflector"

# --- PACOTES PARA VMWARE ---
if [ "$VMWARE" = "YES" ]; then
    VMWARE_PACKAGES="open-vm-tools xf86-video-vmware xf86-input-vmmouse"
    echo "Pacotes VMware a serem instalados: $VMWARE_PACKAGES"
    BASE_PACKAGES="$BASE_PACKAGES $VMWARE_PACKAGES"
fi

# --- INSTALAÇÃO DOS PACOTES ---
echo "Instalando pacotes básicos..."
if ! pacstrap -K /mnt $BASE_PACKAGES; then
    echo "ERRO: Falha ao instalar pacotes base"
    exit 1
fi

# --- GERAR FSTAB ---
echo "Gerando fstab..."
if ! genfstab -U /mnt >> /mnt/etc/fstab; then
    echo "ERRO: Falha ao gerar fstab"
    exit 1
fi

# --- CONFIGURAÇÃO DO CHROOT ---
echo "Configurando sistema instalado..."
if ! arch-chroot /mnt /bin/bash <<EOF
# --- ATUALIZAR MIRRORS NO SISTEMA INSTALADO ---
reflector_cmd="reflector --latest 20 --protocol https --sort rate"
for country in "${REFLECTOR_COUNTRIES[@]}"; do
    reflector_cmd+=" --country ${country}"
done
eval "\$reflector_cmd --save /etc/pacman.d/mirrorlist"

# --- RELÓGIO E FUSO HORÁRIO ---
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || exit 1
hwclock --systohc || exit 1

# --- LOCALE (IDIOMA) ---
echo "$LOCALE UTF-8" >> /etc/locale.gen || exit 1
locale-gen || exit 1
echo "LANG=$LOCALE" > /etc/locale.conf || exit 1

# --- TECLADO ---
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf || exit 1

# --- HOSTNAME ---
echo "$HOSTNAME" > /etc/hostname || exit 1

# --- HOSTS ---
echo "127.0.0.1 localhost" >> /etc/hosts || exit 1
echo "::1 localhost" >> /etc/hosts || exit 1
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts || exit 1

# --- SENHAS (ROOT E USUÁRIO) ---
echo "root:$PASSWORD" | chpasswd || exit 1
useradd -m -G wheel -s /bin/bash "$USER" || exit 1
echo "$USER:$PASSWORD" | chpasswd || exit 1

# --- SUDOERS ---
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers || exit 1

# --- HABILITAR NETWORKMANAGER ---
systemctl enable NetworkManager || exit 1

# --- CONFIGURAÇÃO VMWARE (SE NECESSÁRIO) ---
if [ "$VMWARE" = "YES" ]; then
    systemctl enable vmtoolsd || exit 1
    systemctl enable vmware-vmblock-fuse || exit 1
fi

# --- INSTALAR GRUB (UEFI ou BIOS) ---
if [ "$BOOT_MODE" = "UEFI" ]; then
    pacman -S grub efibootmgr --noconfirm || exit 1
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck || exit 1
else
    pacman -S grub --noconfirm || exit 1
    parted -s "$DISK" mkpart primary 1MiB 2MiB
    parted -s "$DISK" set 3 bios_grub on
    grub-install --target=i386-pc --recheck "$DISK" || exit 1
fi

grub-mkconfig -o /boot/grub/grub.cfg || exit 1
EOF
then
    echo "ERRO: Falha durante a configuração chroot"
    exit 1
fi

# --- FINALIZAR ---
echo "Desmontando e Desligando..."
umount -R /mnt
if [ "$VMWARE" = "YES" ]; then
    echo "VMware Tools instalado com sucesso!"
fi
echo "Instalação concluída! Desligando em 5 segundos..."
sleep 5
poweroff