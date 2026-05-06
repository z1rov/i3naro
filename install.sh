#!/usr/bin/env bash
# ================================================================
#   i3naro + bspwm — Unified Modular Installer
#   Repo: https://github.com/z1rov/i3naro
#   Based on: z1rov/i3naro  &  envertex/dotfiles
# ================================================================
set -Eeuo pipefail

# ================================================================
# GLOBALS
# ================================================================
USER_NAME="${SUDO_USER:-$USER}"
DOTFILES_I3="https://github.com/z1rov/i3naro"
DOTFILES_BSPWM="https://github.com/envertex/dotfiles"
TMPDIR_PREFIX="/tmp/dotfiles_install_$$"

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
# UI HELPERS
# ================================================================
banner() {
  clear
  echo -e "${CYAN}"
  cat <<'EOF'
  ██╗██████╗ ███╗   ██╗ █████╗ ██████╗  ██████╗
  ██║╚════██╗████╗  ██║██╔══██╗██╔══██╗██╔═══██╗
  ██║ █████╔╝██╔██╗ ██║███████║██████╔╝██║   ██║
  ██║ ╚═══██╗██║╚██╗██║██╔══██║██╔══██╗██║   ██║
  ██║██████╔╝██║ ╚████║██║  ██║██║  ██║╚██████╔╝
  ╚═╝╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝
EOF
  echo -e "${RESET}"
  echo -e "  ${BOLD}i3wm + bspwm — Unified Modular Installer${RESET}"
  echo -e "  ${YELLOW}https://github.com/z1rov/i3naro${RESET}\n"
  echo -e "  $(printf '─%.0s' {1..50})\n"
}

step() {
  echo -e "\n${CYAN}[➜]${RESET} ${BOLD}$1${RESET}"
  echo -e "  $(printf '─%.0s' {1..40})"
}

ok()   { echo -e "  ${GREEN}[✔]${RESET} $1"; }
warn() { echo -e "  ${YELLOW}[!]${RESET} $1"; }
err()  { echo -e "  ${RED}[✗]${RESET} $1"; }
info() { echo -e "  ${CYAN}[i]${RESET} $1"; }

# ================================================================
# TRAIN ANIMATION (del install.sh original — se mantiene)
# ================================================================
run_train() {
  local smoke_frames=( "   (   )" "   (    )" "   (     )" "   (    )" "   (   )" "   ." "    " )

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

  for i in {0..20}; do
    _print_train "$i" $((i % ${#smoke_frames[@]}))
    sleep 0.08
  done
  for ((i=20; i>=0; i--)); do
    _print_train "$i" $((i % ${#smoke_frames[@]}))
    sleep 0.08
  done
  clear
}

# ================================================================
# CHECKS
# ================================================================
[[ $EUID -eq 0 ]] && {
  echo -e "${RED}[!] No ejecutes como root.${RESET}"
  exit 1
}

command -v pacman &>/dev/null || {
  echo -e "${RED}[!] Este script es solo para Arch Linux.${RESET}"
  exit 1
}

# ================================================================
# MODO DE INSTALACIÓN
# ================================================================
choose_mode() {
  banner
  echo -e "  Elige qué instalar:\n"
  echo -e "   ${BOLD}1)${RESET} i3wm  — i3-gaps + Polybar + LightDM  ${CYAN}(i3naro)${RESET}"
  echo -e "   ${BOLD}2)${RESET} bspwm — bspwm + sxhkd + lxdm         ${CYAN}(envertex)${RESET}"
  echo -e "   ${BOLD}3)${RESET} Ambos\n"
  read -rp "  Opción [1/2/3]: " MODE
  MODE="${MODE:-1}"
  [[ "$MODE" =~ ^[123]$ ]] || { err "Opción inválida."; exit 1; }
}

# ================================================================
# SUDO
# ================================================================
setup_sudo_cache() {
  step "Cacheando credenciales sudo"
  sudo -v
  # Keep sudo alive during install
  while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEP_PID=$!
  trap 'kill $SUDO_KEEP_PID 2>/dev/null' EXIT
}

setup_sudo_nopasswd() {
  local SUDO_FILE="/etc/sudoers.d/99_${USER_NAME}"
  step "Configurando sudo NOPASSWD"

  sudo sh -c "echo '${USER_NAME} ALL=(ALL) NOPASSWD: ALL' > '${SUDO_FILE}'"
  sudo chmod 440 "$SUDO_FILE"
  sudo visudo -cf "$SUDO_FILE" || {
    sudo rm -f "$SUDO_FILE"
    err "Sudoers file inválido — revertido"
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
# INSTALADORES DE PAQUETES
# ================================================================
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
    warn "yay no disponible — omitiendo paquetes AUR"
    return
  fi
  for pkg in "$@"; do
    if yay -Qi "$pkg" &>/dev/null; then
      info "$pkg (AUR) ya instalado"
    else
      step "Instalando AUR: $pkg"
      yay -S --needed --noconfirm "$pkg"
      ok "$pkg (AUR)"
    fi
  done
}

# ================================================================
# PAQUETES — I3NARO
# ================================================================
I3_PACMAN_PKGS=(
  xorg xorg-xinit
  i3-gaps
  lightdm lightdm-gtk-greeter
  polybar
  alacritty
  zsh
  rofi feh nano
  flameshot xclip
  networkmanager
  neovim tmux
  bat eza
  pipewire pipewire-pulse wireplumber
  dunst
  nodejs npm
  terminus-font
  ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono
  ttf-hack-nerd ttf-jetbrains-mono-nerd
  ttf-font-awesome
)

# ================================================================
# PAQUETES — BSPWM
# ================================================================
BSPWM_PACMAN_PKGS=(
  xorg xorg-xinit
  bspwm sxhkd
  picom feh
  lxdm
  kitty zsh tmux neovim
  rofi thunar gvfs
  bat eza xclip
  brightnessctl pamixer
  firefox
  pipewire pipewire-pulse wireplumber
  papirus-icon-theme
  dunst flameshot
  gnome-themes-extra
  linux linux-firmware mesa xf86-video-amdgpu
  polybar nodejs npm
)

BSPWM_AUR_PKGS=( i3lock-color )

# ================================================================
# ZSH + OH-MY-ZSH
# ================================================================
setup_zsh_common() {
  step "Instalando Oh My Zsh"
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ok "oh-my-zsh instalado"
  else
    ok "oh-my-zsh ya existe — skip"
  fi

  local ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  step "Plugins Zsh"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

  [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

  ok "plugins instalados"
}

setup_zsh_i3() {
  setup_zsh_common

  local ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
  step "Powerlevel10k (theme i3naro)"
  [[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] || \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      "$ZSH_CUSTOM/themes/powerlevel10k"
  ok "powerlevel10k instalado"
}

setup_zsh_bspwm() {
  setup_zsh_common
}

# ================================================================
# FUENTES — NUEVO REPO (fonts/ en la raíz del repo)
# ================================================================
install_fonts() {
  local repo_dir="$1"
  local fonts_dir="$repo_dir/fonts"

  if [[ ! -d "$fonts_dir" ]]; then
    warn "No se encontró directorio fonts/ — omitiendo instalación manual de fuentes"
    return
  fi

  step "Instalando fuentes desde fonts/"
  local dest="$HOME/.local/share/fonts/i3naro"
  mkdir -p "$dest"
  cp -r "$fonts_dir"/. "$dest/"
  fc-cache -fv "$dest" &>/dev/null
  ok "Fuentes instaladas en $dest"
}

# ================================================================
# DOTFILES — I3NARO (nueva estructura: config/ home/)
# ================================================================
setup_dotfiles_i3() {
  step "Clonando dotfiles i3naro"

  local DOTDIR="$TMPDIR_PREFIX/i3naro"
  mkdir -p "$TMPDIR_PREFIX"

  if [[ -d "$DOTDIR/.git" ]]; then
    git -C "$DOTDIR" pull
    ok "Dotfiles actualizados"
  else
    git clone "$DOTFILES_I3" "$DOTDIR"
    ok "Dotfiles clonados"
  fi

  step "Aplicando configuración i3naro"
  mkdir -p "$HOME/.config"

  # config/ → ~/.config/
  if [[ -d "$DOTDIR/config" ]]; then
    cp -r "$DOTDIR/config/"* "$HOME/.config/"
    ok "config/ → ~/.config/"
  else
    warn "No se encontró config/ en el repo"
  fi

  # home/ → ~/  (archivos ocultos como .zshrc, .p10k.zsh, etc.)
  if [[ -d "$DOTDIR/home" ]]; then
    # Copiar todo excepto directorios problemáticos
    find "$DOTDIR/home" -maxdepth 1 \( -name "." -o -name ".." \) -prune -o -print | \
      while read -r item; do
        [[ -z "$item" || "$item" == "$DOTDIR/home" ]] && continue
        local base
        base="$(basename "$item")"
        cp -r "$item" "$HOME/$base"
      done
    ok "home/ → ~/"
  else
    warn "No se encontró home/ en el repo"
  fi

  # Fuentes del repo
  install_fonts "$DOTDIR"

  # Crear directorios estándar
  step "Creando carpetas estándar"
  mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/Music" "$HOME/Videos" \
           "$HOME/Pictures/.wallpapers" "$HOME/Pictures/Clipboard" "$HOME/CTF"
  ok "Directorios creados"

  # Permisos polybar
  [[ -f "$HOME/.config/polybar/launch.sh" ]] && chmod +x "$HOME/.config/polybar/launch.sh"
  [[ -f "$HOME/.config/polybar/scripts/ip-detect.sh" ]] && chmod +x "$HOME/.config/polybar/scripts/ip-detect.sh"

  ok "Dotfiles i3naro aplicados"
}

# ================================================================
# DOTFILES — BSPWM (estructura: config/ home/ del repo envertex)
# ================================================================
setup_dotfiles_bspwm() {
  step "Clonando dotfiles bspwm"

  local DOTDIR="$TMPDIR_PREFIX/bspwm"
  mkdir -p "$TMPDIR_PREFIX"

  if [[ -d "$DOTDIR/.git" ]]; then
    git -C "$DOTDIR" pull
    ok "Dotfiles actualizados"
  else
    git clone "$DOTFILES_BSPWM" "$DOTDIR"
    ok "Dotfiles clonados"
  fi

  step "Aplicando configuración bspwm"
  mkdir -p "$HOME/.config"

  [[ -d "$DOTDIR/config" ]] && {
    cp -r "$DOTDIR/config/"* "$HOME/.config/"
    ok "config/ → ~/.config/"
  }

  [[ -f "$DOTDIR/home/.zshrc" ]] && {
    cp "$DOTDIR/home/.zshrc" "$HOME/"
    ok ".zshrc copiado"
  }

  [[ -d "$DOTDIR/home/.mozilla" ]] && cp -r "$DOTDIR/home/.mozilla" "$HOME/"
  [[ -d "$DOTDIR/home/.local" ]]   && cp -r "$DOTDIR/home/.local"   "$HOME/"

  # bspwmrc permisos
  [[ -f "$HOME/.config/bspwm/bspwmrc" ]] && chmod +x "$HOME/.config/bspwm/bspwmrc"
  find "$HOME/.config/bspwm/scripts" -type f -exec chmod 755 {} \; 2>/dev/null || true

  step "Creando carpetas estándar"
  mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/CTF"
  ok "Directorios creados"

  ok "Dotfiles bspwm aplicados"
}

# ================================================================
# SERVICIOS — I3NARO
# ================================================================
setup_services_i3() {
  step "Servicios i3wm"
  sudo systemctl enable NetworkManager lightdm
  sudo systemctl start NetworkManager
  echo "exec i3" > "$HOME/.xinitrc"
  sudo chsh -s /bin/zsh "$USER_NAME"
  ok "Servicios i3 configurados"
}

# ================================================================
# SERVICIOS — BSPWM
# ================================================================
setup_services_bspwm() {
  step "Servicios bspwm"
  sudo systemctl enable NetworkManager lxdm
  sudo systemctl start NetworkManager
  echo "exec bspwm" > "$HOME/.xinitrc"
  sudo chsh -s /bin/zsh "$USER_NAME"
  ok "Servicios bspwm configurados"
}

# ================================================================
# ROOT SYNC (solo bspwm, opcional en i3)
# ================================================================
setup_root_sync() {
  step "Sincronizando config con root"
  sudo chsh -s /bin/zsh root
  sudo cp -r "$HOME/.oh-my-zsh" /root/ 2>/dev/null || true
  sudo cp "$HOME/.zshrc" /root/ 2>/dev/null || true
  sudo cp -r "$HOME/.config" /root/ 2>/dev/null || true
  ok "Root sincronizado"
}

# ================================================================
# SSH (módulo compartido — idempotente)
# ================================================================
setup_ssh() {
  banner
  read -rp "  ¿Generar claves SSH? (Y/n): " ans
  ans="${ans,,}"
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && return

  step "Configuración de claves SSH"

  echo -e "\n  Modo de clave:"
  echo -e "   ${BOLD}1)${RESET} Sin passphrase (default)"
  echo -e "   ${BOLD}2)${RESET} Con passphrase (recomendado)\n"
  read -rp "  Opción [1]: " mode
  [[ "$mode" != "2" ]] && mode=1

  read -rp "  Etiqueta de clave [${USER_NAME}]: " SSH_USER
  SSH_USER="${SSH_USER:-$USER_NAME}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  local PASS_RSA="" PASS_ED25519=""

  if [[ "$mode" == "2" ]]; then
    while true; do
      read -s -p "  Passphrase RSA: " p1; echo
      read -s -p "  Confirmar: " p2; echo
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
      [[ "${ow,,}" != "y" ]] && return
      cp "$path" "$path.bak" 2>/dev/null || true
      cp "$path.pub" "$path.pub.bak" 2>/dev/null || true
      rm -f "$path" "$path.pub"
    fi
    if [[ "$type" == "rsa" ]]; then
      ssh-keygen -t rsa -b "$bits" -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    else
      ssh-keygen -t ed25519 -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    fi
    chmod 600 "$path"
    chmod 644 "$path.pub"
    ok "Clave $type generada → $path"
  }

  _gen_key "$HOME/.ssh/id_rsa"     "rsa"     4096 "$PASS_RSA"
  _gen_key "$HOME/.ssh/id_ed25519" "ed25519" ""   "$PASS_ED25519"

  banner
  [[ -f "$HOME/.ssh/id_rsa.pub" ]] && {
    echo -e "  ${BOLD}--- id_rsa.pub ---${RESET}"
    cat "$HOME/.ssh/id_rsa.pub"
    echo
  }
  [[ -f "$HOME/.ssh/id_ed25519.pub" ]] && {
    echo -e "  ${BOLD}--- id_ed25519.pub ---${RESET}"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo
  }

  read -rp "  Presiona ENTER para continuar..."
}

# ================================================================
# LIMPIEZA
# ================================================================
cleanup() {
  step "Limpiando archivos temporales"
  rm -rf "$TMPDIR_PREFIX" 2>/dev/null || true
  ok "Limpieza completada"
}

# ================================================================
# FLUJO — I3NARO
# ================================================================
install_i3naro() {
  step "=== INSTALANDO i3naro ==="

  # Remover i3-wm si existe (conflicto con i3-gaps)
  if pacman -Qi i3-wm &>/dev/null; then
    warn "Removiendo i3-wm (conflicto con i3-gaps)..."
    sudo pacman -Rns --noconfirm i3-wm || true
  fi

  install_pacman "${I3_PACMAN_PKGS[@]}"
  setup_zsh_i3
  setup_dotfiles_i3
  setup_services_i3

  read -rp "  ¿Sincronizar config con root? (y/N): " do_root
  [[ "${do_root,,}" == "y" ]] && setup_root_sync
}

# ================================================================
# FLUJO — BSPWM
# ================================================================
install_bspwm() {
  step "=== INSTALANDO bspwm ==="
  install_pacman "${BSPWM_PACMAN_PKGS[@]}"
  install_yay_pkgs "${BSPWM_AUR_PKGS[@]}"
  setup_zsh_bspwm
  setup_dotfiles_bspwm
  setup_services_bspwm

  read -rp "  ¿Sincronizar config con root? (y/N): " do_root
  [[ "${do_root,,}" == "y" ]] && setup_root_sync

  step "Regenerando initramfs (dracut)"
  sudo dracut --regenerate-all --force 2>/dev/null || \
    warn "dracut no disponible — omitido (no crítico)"
}

# ================================================================
# MAIN
# ================================================================
main() {
  run_train

  banner
  read -rp "  ¿Continuar instalación? (Y/n): " ans
  ans="${ans,,}"
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && exit 0

  choose_mode
  setup_sudo_cache
  setup_sudo_nopasswd
  setup_yay

  case "$MODE" in
    1) install_i3naro ;;
    2) install_bspwm ;;
    3) install_i3naro; install_bspwm ;;
  esac

  setup_ssh
  cleanup

  banner
  echo -e "  ${GREEN}${BOLD}✔  INSTALACIÓN COMPLETADA${RESET}"
  echo -e "  ${CYAN}Reinicia la sesión o ejecuta: ${BOLD}exec zsh${RESET}"
  echo
}

main "$@"
