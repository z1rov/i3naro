#!/usr/bin/env bash
# ================================================================
#   i3naro — Installer
#   Repo: https://github.com/z1rov/i3naro
# ================================================================
set -Eeuo pipefail

# ================================================================
# GLOBALS
# ================================================================
USER_NAME="${SUDO_USER:-$USER}"
DOTFILES_REPO="https://github.com/z1rov/i3naro"
TMPDIR_CLONE="/tmp/i3naro_install_$$"
SUDO_KEEPALIVE_PID=""

# ================================================================
# COLORS
# ================================================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ================================================================
# UI
# ================================================================
banner() {
  clear
  echo -e "${CYAN}"
  cat <<'BANNER'

  ██╗██████╗ ███╗   ██╗ █████╗ ██████╗  ██████╗
  ██║╚════██╗████╗  ██║██╔══██╗██╔══██╗██╔═══██╗
  ██║ █████╔╝██╔██╗ ██║███████║██████╔╝██║   ██║
  ██║ ╚═══██╗██║╚██╗██║██╔══██║██╔══██╗██║   ██║
  ██║██████╔╝██║ ╚████║██║  ██║██║  ██║╚██████╔╝
  ╚═╝╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝

BANNER
  echo -e "${RESET}  ${BOLD}i3wm Modular Installer${RESET}  —  ${YELLOW}https://github.com/z1rov/i3naro${RESET}"
  echo -e "  $(printf '─%.0s' {1..52})\n"
}

step() {
  echo -e "\n${CYAN}[➜]${RESET} ${BOLD}$1${RESET}"
  echo -e "  $(printf '─%.0s' {1..42})"
}

ok()   { echo -e "  ${GREEN}[✔]${RESET} $1"; }
warn() { echo -e "  ${YELLOW}[!]${RESET} $1"; }
err()  { echo -e "  ${RED}[✗]${RESET} $1"; }
info() { echo -e "  ${CYAN}[i]${RESET} $1"; }

# ================================================================
# TRAIN ANIMATION
# ================================================================
run_train() {
  local smoke_frames=(
    "   (   )"
    "   (    )"
    "   (     )"
    "   (    )"
    "   (   )"
    "   ."
    "    "
  )

  _print_train() {
    clear
    local pos=$1 frame=$2
    local space
    space=$(printf "%${pos}s" "")
    echo "${space}${smoke_frames[$frame]}"
    cat <<EOF
${space}   ___     ____
${space}  |_ _|   |__ /   _ _     __ _      _ _    ___
${space}   | |     |_ \  | ' \   / _\` |    | '_|  / _ \\
${space}  |___|   |___/  |_||_|  \__,_|   _|_|_   \___/
${space} _|"""""|_|"""""|_|"""""|_|"""""|_|"""""|_|"""""|
${space} "\`-0-0-'"\`-0-0-'"\`-0-0-'"\`-0-0-'"\`-0-0-'"\`-0-0-'
EOF
  }

  for i in {0..22}; do
    _print_train "$i" $(( i % ${#smoke_frames[@]} ))
    sleep 0.08
  done
  for (( i=22; i>=0; i-- )); do
    _print_train "$i" $(( i % ${#smoke_frames[@]} ))
    sleep 0.08
  done
  clear
}

# ================================================================
# CHECKS
# ================================================================
check_root() {
  if [[ $EUID -eq 0 ]]; then
    err "No ejecutes como root. Usa tu usuario normal."
    exit 1
  fi
}

check_arch() {
  if ! command -v pacman &>/dev/null; then
    err "Este instalador es solo para Arch Linux."
    exit 1
  fi
}

# ================================================================
# CLEANUP TRAP
# ================================================================
_cleanup() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  rm -rf "$TMPDIR_CLONE" 2>/dev/null || true
}
trap '_cleanup' EXIT INT TERM

# ================================================================
# SUDO
# ================================================================
setup_sudo_cache() {
  step "Cacheando credenciales sudo"
  sudo -v
  while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" 2>/dev/null || exit
  done &
  SUDO_KEEPALIVE_PID=$!
  ok "sudo cacheado"
}

setup_sudo_nopasswd() {
  local sudofile="/etc/sudoers.d/99_${USER_NAME}"
  step "Configurando sudo NOPASSWD"

  sudo sh -c "echo '${USER_NAME} ALL=(ALL) NOPASSWD: ALL' > '${sudofile}'"
  sudo chmod 440 "$sudofile"
  sudo visudo -cf "$sudofile" || {
    sudo rm -f "$sudofile"
    err "sudoers inválido — revertido"
    exit 1
  }
  ok "sudo NOPASSWD configurado"
}

# ================================================================
# YAY
# ================================================================
setup_yay() {
  if command -v yay &>/dev/null; then
    ok "yay ya instalado — skip"
    return
  fi

  step "Instalando yay (AUR helper)"
  sudo pacman -S --needed --noconfirm git base-devel

  local tmp
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmp/yay"
  pushd "$tmp/yay" >/dev/null
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmp"
  ok "yay instalado"
}

# ================================================================
# DETECTAR DISPLAY MANAGER ACTIVO
# FIX: systemctl is-enabled retorna != 0 si el DM no existe,
#      lo que con set -e mataba el script silenciosamente.
#      Ahora cada check tiene || true para evitarlo.
# ================================================================
detect_display_manager() {
  local dm_list=("gdm" "sddm" "lightdm" "ly" "lxdm" "slim" "xdm" "greetd" "emptty")
  for dm in "${dm_list[@]}"; do
    if systemctl is-enabled "$dm" &>/dev/null || systemctl is-active "$dm" &>/dev/null; then
      echo "$dm"
      return 0
    fi
  done
  echo ""
  return 0
}

# ================================================================
# PAQUETES
# ================================================================
PACMAN_PKGS=(
  # Xorg
  xorg xorg-xinit xorg-xrdb
  # D-Bus (necesario para dbus-launch en .xinitrc)
  dbus
  # WM + compositor
  i3-wm i3status i3lock picom
  # Bar
  polybar
  # Terminales
  kitty alacritty
  # Shell + tmux
  zsh tmux
  # Editor
  neovim
  # Launcher + file manager
  rofi thunar gvfs
  # Utilidades
  bat eza xclip feh
  brightnessctl pamixer
  flameshot
  # Red
  networkmanager
  # Browser
  firefox
  # Audio
  pipewire pipewire-pulse wireplumber
  # Temas + iconos
  papirus-icon-theme gnome-themes-extra
  # Notificaciones
  dunst
  # Node (scripts polybar)
  nodejs npm
  # Fuentes sistema
  terminus-font
  ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono
  ttf-hack-nerd ttf-jetbrains-mono-nerd
  ttf-font-awesome
)

install_pacman() {
  for pkg in "$@"; do
    if pacman -Qi "$pkg" &>/dev/null; then
      info "$pkg ya instalado"
    else
      step "Instalando $pkg"
      sudo pacman -S --needed --noconfirm "$pkg"
      ok "$pkg"
    fi
  done
}

install_yay_pkgs() {
  if ! command -v yay &>/dev/null; then
    warn "yay no disponible — omitiendo AUR"
    return
  fi
  for pkg in "$@"; do
    if yay -Qi "$pkg" &>/dev/null; then
      info "$pkg (AUR) ya instalado"
    else
      step "Instalando AUR: $pkg"
      yay -S --needed --noconfirm "$pkg"
      ok "$pkg"
    fi
  done
}

# ================================================================
# ZSH + OH-MY-ZSH + POWERLEVEL10K
# ================================================================
setup_zsh() {
  step "Oh My Zsh"
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ok "oh-my-zsh instalado"
  else
    ok "oh-my-zsh ya existe — skip"
  fi

  local ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  step "Plugins Zsh"
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    ok "zsh-autosuggestions"
  else
    info "zsh-autosuggestions ya existe"
  fi

  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    ok "zsh-syntax-highlighting"
  else
    info "zsh-syntax-highlighting ya existe"
  fi

  step "Powerlevel10k"
  if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      "$ZSH_CUSTOM/themes/powerlevel10k"
    ok "powerlevel10k instalado"
  else
    info "powerlevel10k ya existe"
  fi
}

# ================================================================
# FUENTES DEL REPO
# ================================================================
install_fonts() {
  local fonts_src="$1/fonts"

  if [[ ! -d "$fonts_src" ]]; then
    warn "No se encontró fonts/ en el repo — skip"
    return
  fi

  step "Instalando fuentes del repo"
  local dest="$HOME/.local/share/fonts/i3naro"
  mkdir -p "$dest"

  cp -r "$fonts_src"/. "$dest/"

  fc-cache -fv "$dest" &>/dev/null
  ok "Fuentes → $dest  (terminus, panels, iosevka, fantasque, feather…)"
}

# ================================================================
# DOTFILES
# ================================================================
setup_dotfiles() {
  step "Clonando i3naro"
  mkdir -p "$TMPDIR_CLONE"

  if [[ -d "$TMPDIR_CLONE/.git" ]]; then
    git -C "$TMPDIR_CLONE" pull
    ok "Repo actualizado"
  else
    git clone "$DOTFILES_REPO" "$TMPDIR_CLONE"
    ok "Repo clonado"
  fi

  local REPO="$TMPDIR_CLONE"

  step "Aplicando config/"
  mkdir -p "$HOME/.config"

  if [[ -d "$REPO/config" ]]; then
    for item in "$REPO/config"/*/; do
      # Eliminar trailing slash para que basename funcione bien
      item="${item%/}"
      [[ -e "$item" ]] || continue
      local name
      name="$(basename "$item")"

      if [[ "$name" == "mozilla" ]]; then
        # mozilla va a ~/.mozilla/ (fuera de .config)
        mkdir -p "$HOME/.mozilla"
        cp -rT "$item" "$HOME/.mozilla"
        ok "config/mozilla → ~/.mozilla/"
      else
        # El resto va a ~/.config/<nombre>
        rm -rf "$HOME/.config/$name"
        cp -rT "$item" "$HOME/.config/$name"
        ok "config/$name → ~/.config/$name"
      fi
    done
  else
    warn "No se encontró config/"
  fi

  if [[ -d "$REPO/config/wallpapers" ]]; then
    mkdir -p "$HOME/Pictures/.wallpapers"
    cp -r "$REPO/config/wallpapers/"* "$HOME/Pictures/.wallpapers/"
    ok "wallpapers → ~/Pictures/.wallpapers/"
  fi

  step "Aplicando home/"
  if [[ -d "$REPO/home" ]]; then
    while IFS= read -r -d '' item; do
      local rel dest
      rel="${item#$REPO/home/}"
      dest="$HOME/$rel"
      if [[ -d "$item" ]]; then
        mkdir -p "$dest"
      else
        mkdir -p "$(dirname "$dest")"
        cp "$item" "$dest"
      fi
    done < <(find "$REPO/home" -mindepth 1 -print0)
    ok "home/ → ~/"
  else
    warn "No se encontró home/"
  fi

  install_fonts "$REPO"

  step "Permisos de ejecución"
  local i3sc="$HOME/.config/i3/scripts"
  if [[ -d "$i3sc" ]]; then
    find "$i3sc" -type f -exec chmod 755 {} \;
    ok "i3/scripts → 755"
  fi

  [[ -f "$HOME/.config/polybar/launch.sh" ]] && {
    chmod +x "$HOME/.config/polybar/launch.sh"
    ok "polybar/launch.sh → +x"
  }
  local pbsc="$HOME/.config/polybar/scripts"
  if [[ -d "$pbsc" ]]; then
    find "$pbsc" -type f -exec chmod 755 {} \;
    ok "polybar/scripts → 755"
  fi

  step "Directorios estándar"
  mkdir -p \
    "$HOME/Documents" \
    "$HOME/Downloads" \
    "$HOME/Music" \
    "$HOME/Videos" \
    "$HOME/Pictures/.wallpapers" \
    "$HOME/Pictures/Clipboard" \
    "$HOME/CTF"
  ok "Directorios creados"
}

# ================================================================
# SERVICIOS
# ================================================================
setup_services() {
  step "Servicios"

  sudo systemctl enable NetworkManager
  sudo systemctl start NetworkManager
  ok "NetworkManager habilitado"

  if pacman -Qi i3-wm &>/dev/null; then
    warn "Removiendo i3-wm (conflicto con i3-gaps)..."
    sudo pacman -Rns --noconfirm i3-wm || true
  fi

  local active_dm
  active_dm="$(detect_display_manager)"

  if [[ -n "$active_dm" ]]; then
    warn "Display manager detectado: ${BOLD}${active_dm}${RESET}${YELLOW} — omitiendo lightdm"
  else
    info "Sin display manager activo — instalando lightdm"
    sudo pacman -S --needed --noconfirm lightdm lightdm-gtk-greeter
    sudo systemctl enable lightdm
    ok "lightdm habilitado"
  fi

  # .xinitrc correcto: dbus-launch necesario para que i3 funcione bien
  # con apps GTK, notificaciones, portals, etc.
  cat > "$HOME/.xinitrc" <<'XINITRC'
#!/bin/sh

# Merge Xresources si existe
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Lanzar i3 con D-Bus session
exec dbus-launch --exit-with-session i3
XINITRC
  chmod +x "$HOME/.xinitrc"
  ok ".xinitrc → dbus-launch i3"

  # .xsession para display managers (lxdm, lightdm, sddm…)
  cp "$HOME/.xinitrc" "$HOME/.xsession"
  chmod +x "$HOME/.xsession"
  ok ".xsession → creado (para DM)"

  # Entrada de escritorio para DMs que leen /usr/share/xsessions/
  if [[ ! -f /usr/share/xsessions/i3.desktop ]]; then
    sudo tee /usr/share/xsessions/i3.desktop >/dev/null <<'DESKTOP'
[Desktop Entry]
Name=i3
Comment=Improved dynamic tiling window manager
Exec=i3
TryExec=i3
Type=Application
X-LightDM-DesktopName=i3
DesktopNames=i3
Keywords=tiling;wm;windowmanager;window;manager;
DESKTOP
    ok "i3.desktop → /usr/share/xsessions/"
  else
    info "i3.desktop ya existe"
  fi

  sudo chsh -s /bin/zsh "$USER_NAME"
  ok "shell → zsh"
}

# ================================================================
# ROOT SYNC
# ================================================================
setup_root_sync() {
  step "Sincronizando config con root"
  sudo chsh -s /bin/zsh root
  [[ -d "$HOME/.oh-my-zsh" ]] && sudo cp -r "$HOME/.oh-my-zsh" /root/
  [[ -f "$HOME/.zshrc" ]]     && sudo cp "$HOME/.zshrc" /root/
  [[ -d "$HOME/.config" ]]    && sudo cp -r "$HOME/.config" /root/
  ok "Root sincronizado"
}

# ================================================================
# SSH
# ================================================================
setup_ssh() {
  banner
  read -rp "  ¿Generar claves SSH? (Y/n): " ans
  ans="${ans,,}"
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && return

  step "Configuración SSH"

  echo -e "\n  Modo:"
  echo -e "   ${BOLD}1)${RESET} Sin passphrase (default)"
  echo -e "   ${BOLD}2)${RESET} Con passphrase (recomendado)\n"
  read -rp "  Opción [1]: " mode
  [[ "$mode" != "2" ]] && mode=1

  read -rp "  Etiqueta [${USER_NAME}]: " SSH_USER
  SSH_USER="${SSH_USER:-$USER_NAME}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  local PASS_RSA="" PASS_ED25519=""

  if [[ "$mode" == "2" ]]; then
    while true; do
      read -s -p "  Passphrase RSA: " p1; echo
      read -s -p "  Confirmar:      " p2; echo
      [[ "$p1" == "$p2" ]] && PASS_RSA="$p1" && break
      err "No coinciden"
    done
    read -s -p "  Passphrase ED25519 (Enter = reusar RSA): " q1; echo
    if [[ -z "$q1" ]]; then
      PASS_ED25519="$PASS_RSA"
    else
      while true; do
        read -s -p "  Confirmar ED25519: " q2; echo
        [[ "$q1" == "$q2" ]] && PASS_ED25519="$q1" && break
        err "No coinciden"
      done
    fi
  fi

  _gen_key() {
    local path="$1" type="$2" bits="$3" pass="$4"
    if [[ -f "$path" ]]; then
      read -rp "  [!] $path existe — ¿sobreescribir? (y/N): " ow
      [[ "${ow,,}" != "y" ]] && { info "Clave $type omitida"; return; }
      cp "$path"     "$path.bak"     2>/dev/null || true
      cp "$path.pub" "$path.pub.bak" 2>/dev/null || true
      rm -f "$path" "$path.pub"
    fi

    if [[ "$type" == "rsa" ]]; then
      ssh-keygen -t rsa -b "$bits" -f "$path" \
        -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    else
      ssh-keygen -t ed25519 -f "$path" \
        -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    fi
    chmod 600 "$path"
    chmod 644 "$path.pub"
    ok "Clave $type → $path"
  }

  _gen_key "$HOME/.ssh/id_rsa"     "rsa"     4096 "$PASS_RSA"
  _gen_key "$HOME/.ssh/id_ed25519" "ed25519" ""   "$PASS_ED25519"

  banner
  [[ -f "$HOME/.ssh/id_rsa.pub" ]] && {
    echo -e "  ${BOLD}─── id_rsa.pub ────────────────────────────────${RESET}"
    cat "$HOME/.ssh/id_rsa.pub"
    echo
  }
  [[ -f "$HOME/.ssh/id_ed25519.pub" ]] && {
    echo -e "  ${BOLD}─── id_ed25519.pub ────────────────────────────${RESET}"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo
  }

  read -rp "  Presiona ENTER para continuar..."
}

# ================================================================
# MAIN
# ================================================================
main() {
  check_root
  check_arch

  run_train

  banner
  read -rp "  ¿Continuar instalación? (Y/n): " ans
  ans="${ans,,}"
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && exit 0

  setup_sudo_cache
  setup_sudo_nopasswd
  setup_yay

  install_pacman "${PACMAN_PKGS[@]}"

  setup_zsh
  setup_dotfiles
  setup_services

  banner
  read -rp "  ¿Sincronizar config con root? (y/N): " do_root
  [[ "${do_root,,}" == "y" ]] && setup_root_sync

  setup_ssh

  banner
  echo -e "  ${GREEN}${BOLD}✔  INSTALACIÓN COMPLETADA${RESET}\n"
  echo -e "  ${CYAN}Próximos pasos:${RESET}"
  echo -e "   • Reinicia la sesión o ejecuta: ${BOLD}exec zsh${RESET}"
  echo -e "   • El WM arranca via ${BOLD}lightdm${RESET} (o ${BOLD}startx${RESET} con .xinitrc)"
  echo -e "   • Wallpapers en: ${BOLD}~/Pictures/.wallpapers/${RESET}\n"
}

main "$@"
