#!/bin/bash

# Script minimalista para instalação do BSPWM no Arch Linux

# Verificar se o usuário é root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: Este script deve ser executado como root" >&2
    exit 1
fi

# Configurar pacman para não perguntar
sed -i 's/^#ParallelDownloads/ParallelDownloads/; s/^#Color/Color/' /etc/pacman.conf

# Atualizar o sistema
echo "Atualizando o sistema..."
pacman -Syu --noconfirm || exit 1

# Instalar pacotes essenciais mínimos
echo "Instalando pacotes essenciais..."
pacman -S --noconfirm \
    xorg-server xorg-xinit \
    bspwm sxhkd \
    dmenu \
    ttf-dejavu \
    lightdm lightdm-gtk-greeter || exit 1

# Configurar lightdm para inicialização automática
echo "Configurando lightdm..."
systemctl enable lightdm.service || exit 1

# Configurar usuário principal
USER=$(ls /home | head -n 1)
USER_HOME="/home/$USER"

if [ -z "$USER" ]; then
    echo "ERRO: Nenhum usuário encontrado em /home" >&2
    exit 1
fi

echo "Configurando ambiente para o usuário $USER..."

# Criar diretórios de configuração
sudo -u "$USER" mkdir -p "$USER_HOME/.config"/{bspwm,sxhkd}

# Configurações básicas do BSPWM
sudo -u "$USER" cp /usr/share/doc/bspwm/examples/bspwmrc "$USER_HOME/.config/bspwm/"
sudo -u "$USER" cp /usr/share/doc/bspwm/examples/sxhkdrc "$USER_HOME/.config/sxhkd/"
sudo -u "$USER" chmod +x "$USER_HOME/.config/bspwm/bspwmrc"

# Configurar sessão padrão
mkdir -p /usr/share/xsessions
cat > /usr/share/xsessions/bspwm.desktop <<EOF
[Desktop Entry]
Name=bspwm
Comment=Binary space partitioning window manager
Exec=bspwm
Type=Application
EOF