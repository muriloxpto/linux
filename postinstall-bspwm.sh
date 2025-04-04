if ! arch-chroot /mnt /bin/bash <<EOF

# Verificar se o script está sendo executado dentro de um chroot
if [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]; then
    # Modo normal (não chroot)
    echo "Executando instalação normal..."
else
    # Modo chroot - adicionado pelo usuário
    echo "Executando em ambiente chroot..."
fi

# --- INSTALAR PACOTES EXTRAS (BASE) ---
# Verificar se o usuário é root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script precisa ser executado como root ou com sudo."
    exit 1
fi

# Atualizar o sistema
echo "Atualizando o sistema..."
pacman -Syu --noconfirm

# Instalar pacotes essenciais
echo "Instalando pacotes essenciais..."
pacman -S --noconfirm \
    xorg-server xorg-xinit xorg-xrandr \       # Xorg básico
    bspwm sxhkd \                              # Gerenciador de janelas e atalhos
    dmenu \                                    # Lançador de aplicativos
    feh \                                      # Gerenciador de wallpapers
    picom \                                    # Compositor para transparências/sombra
    ttf-dejavu \                               # Fonte básica
    lightdm lightdm-gtk-greeter  # Gerenciador de login para inicialização automática

# Configurar lightdm para inicialização automática
echo "Configurando lightdm para inicializar automaticamente..."
systemctl enable lightdm.service

# Configurar para o usuário atual
USER=$(logname)
USER_HOME=$(eval echo ~$USER)

echo "Configurando arquivos básicos para $USER..."
su - $USER -c "mkdir -p $USER_HOME/.config/{bspwm,sxhkd}"

# Copiar configurações padrão mínimas
su - $USER -c "cp /usr/share/doc/bspwm/examples/bspwmrc $USER_HOME/.config/bspwm/"
su - $USER -c "cp /usr/share/doc/bspwm/examples/sxhkdrc $USER_HOME/.config/sxhkd/"
su - $USER -c "chmod +x $USER_HOME/.config/bspwm/bspwmrc"

# Configurar sessão do lightdm para o usuário
echo "Configurando sessão padrão para o usuário..."
mkdir -p /var/lib/AccountsService/users/
cat > /var/lib/AccountsService/users/$USER <<EOF
[User]
Language=
Session=bspwm
XSession=bspwm
Icon=/home/$USER/.face
EOF

# Configurar .xinitrc como fallback
echo "Configurando .xinitrc..."
su - $USER -c "echo 'exec bspwm' > $USER_HOME/.xinitrc"
chown $USER:$USER $USER_HOME/.xinitrc

# Criar arquivo de sessão .desktop para o bspwm
echo "Criando arquivo de sessão para o lightdm..."
cat > /usr/share/xsessions/bspwm.desktop <<EOF
[Desktop Entry]
Name=bspwm
Comment=Binary space partitioning window manager
Exec=bspwm
Type=Application
EOF

echo "Instalação mínima concluída!"
echo "Para iniciar o BSPWM, execute 'startx' após login"
echo "Configure seus atalhos em ~/.config/sxhkd/sxhkdrc"
echo "Configure o gerenciador de janelas em ~/.config/bspwm/bspwmrc"
EOF
then
    echo "ERRO: Falha durante a configuração chroot"
    exit 1
fi