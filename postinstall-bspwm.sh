#!/bin/bash

# Script para instalação do BSPWM em ambiente chroot pós-instalação do Arch Linux

# Verificar se estamos no ambiente chroot
if ! arch-chroot /mnt /bin/bash <<"CHROOT_EOF"
then
    echo "ERRO: Falha ao entrar no ambiente chroot"
    exit 1
fi

# --- INÍCIO DA INSTALAÇÃO NO CHROOT ---

echo "Iniciando instalação do BSPWM no ambiente chroot..."

# Verificar se o usuário é root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: Este script deve ser executado como root"
    exit 1
fi

# Configurar pacman para não perguntar
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

# Atualizar o sistema
echo "Atualizando o sistema..."
pacman -Syu --noconfirm

# Instalar pacotes essenciais
echo "Instalando pacotes essenciais..."
pacman -S --noconfirm \
    xorg-server xorg-xinit xorg-xrandr \
    bspwm sxhkd \
    dmenu \
    feh \
    picom \
    ttf-dejavu \
    lightdm lightdm-gtk-greeter

# Configurar lightdm para inicialização automática
echo "Configurando lightdm..."
systemctl enable lightdm.service

# Configurar usuário (assumindo que já existe um usuário principal)
USER=$(ls /home | head -n 1)  # Pega o primeiro usuário encontrado em /home
USER_HOME="/home/$USER"

if [ -z "$USER" ]; then
    echo "ERRO: Nenhum usuário encontrado em /home"
    exit 1
fi

echo "Configurando ambiente para o usuário $USER..."

# Criar diretórios de configuração
mkdir -p "$USER_HOME/.config"/{bspwm,sxhkd}
chown -R "$USER:$USER" "$USER_HOME/.config"

# Copiar configurações padrão
echo "Configurando arquivos básicos..."
sudo -u "$USER" cp /usr/share/doc/bspwm/examples/bspwmrc "$USER_HOME/.config/bspwm/"
sudo -u "$USER" cp /usr/share/doc/bspwm/examples/sxhkdrc "$USER_HOME/.config/sxhkd/"
sudo -u "$USER" chmod +x "$USER_HOME/.config/bspwm/bspwmrc"

# Configurar sessão padrão
echo "Configurando sessão automática..."
mkdir -p /var/lib/AccountsService/users/
cat > "/var/lib/AccountsService/users/$USER" <<EOF
[User]
Language=
Session=bspwm
XSession=bspwm
Icon=$USER_HOME/.face
EOF

# Configurar .xinitrc
sudo -u "$USER" echo "exec bspwm" > "$USER_HOME/.xinitrc"

# Criar entrada de sessão para o lightdm
cat > /usr/share/xsessions/bspwm.desktop <<EOF
[Desktop Entry]
Name=bspwm
Comment=Binary space partitioning window manager
Exec=bspwm
Type=Application
EOF

# Mensagem final
cat <<EOF

Instalação do BSPWM concluída com sucesso!

Configurações:
- Gerenciador de login: lightdm
- Sessão padrão: bspwm
- Configurações do usuário em: $USER_HOME/.config/bspwm/
- Atalhos em: $USER_HOME/.config/sxhkd/sxhkdrc

Após reiniciar, o sistema iniciará automaticamente no BSPWM.
EOF

CHROOT_EOF

# Verificar se a instalação foi bem sucedida
if [ $? -eq 0 ]; then
    echo "Instalação concluída com sucesso!"
else
    echo "ERRO: Ocorreu um problema durante a instalação"
    exit 1
fi