#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Hax — Installer
# ═══════════════════════════════════════════════════════════════
# Instala Ambxst (si no está presente) y configura Hax,
# el spotlight/launcher modular para Wayland.
# ═══════════════════════════════════════════════════════════════

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}ℹ  $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✔  $1${NC}" >&2; }
log_warn()    { echo -e "${YELLOW}⚠  $1${NC}" >&2; }
log_error()   { echo -e "${RED}✖  $1${NC}" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ── 1. Detectar distribución ──────────────────────────────────
detect_distro() {
  [[ -f /etc/NIXOS ]] && echo "nixos" && return
  has_cmd pacman && echo "arch" && return
  has_cmd dnf    && echo "fedora" && return
  has_cmd apt    && echo "debian" && return
  echo "unknown"
}
DISTRO=$(detect_distro)
log_info "Distribución detectada: $DISTRO"

# ── 2. Instalar Ambxst si no está ─────────────────────────────
if ! has_cmd ambxst && [[ ! -f /usr/local/bin/ambxst ]] && [[ ! -f "$HOME/.local/bin/ambxst" ]]; then
  log_info "Ambxst no está instalado. Instalando..."
  case "$DISTRO" in
    arch|fedora|debian)
      bash <(curl -sL get.axeni.de/ambxst)
      ;;
    nixos)
      nix profile install github:Axenide/Ambxst --impure
      ;;
    *)
      log_error "Distribución no soportada. Instala Ambxst manualmente."
      exit 1
      ;;
  esac
  log_success "Ambxst instalado correctamente."
else
  log_info "Ambxst ya está instalado."
fi

# ── 3. Verificar dependencias de Hax ──────────────────────────
log_info "Verificando dependencias de Hax..."

DEPS_MISSING=()

# Quickshell (runtime)
if ! has_cmd qs; then
  case "$DISTRO" in
    arch)   DEPS_MISSING+=("quickshell") ;;
    fedora) DEPS_MISSING+=("quickshell") ;;
    *)      log_warn "Quickshell no encontrado. Instálalo manualmente." ;;
  esac
fi

# Herramientas esenciales para Hax
ESSENTIAL_TOOLS=(fuzzel grim slurp jq playerctl wl-clipboard brightnessctl)
for tool in "${ESSENTIAL_TOOLS[@]}"; do
  has_cmd "$tool" || DEPS_MISSING+=("$tool")
done

if [[ ${#DEPS_MISSING[@]} -gt 0 ]]; then
  log_info "Instalando dependencias faltantes: ${DEPS_MISSING[*]}"
  case "$DISTRO" in
    arch)
      AUR_HELPER=""
      has_cmd yay  && AUR_HELPER="yay" || true
      has_cmd paru && AUR_HELPER="paru" || true
      if [[ -z "$AUR_HELPER" ]]; then
        log_info "Instalando yay-bin..."
        YAY_TMP="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay-bin.git "$YAY_TMP"
        (cd "$YAY_TMP" && makepkg -si --noconfirm)
        rm -rf "$YAY_TMP"
        AUR_HELPER="yay"
      fi
      $AUR_HELPER -S --needed --noconfirm "${DEPS_MISSING[@]}"
      ;;
    fedora)
      sudo dnf install -y "${DEPS_MISSING[@]}"
      ;;
    *)
      log_warn "Instala las dependencias manualmente: ${DEPS_MISSING[*]}"
      ;;
  esac
  log_success "Dependencias instaladas."
else
  log_info "Todas las dependencias están presentes."
fi

# ── 4. Instalar Hax (spotlight module) ────────────────────────
INSTALL_PATH="$HOME/.local/src/ambxst"

if [[ -d "$INSTALL_PATH" ]]; then
  log_info "Actualizando módulo Hax en Ambxst..."
  cp -r "$REPO_DIR/modules/widgets/spotlight" "$INSTALL_PATH/modules/widgets/"
  log_success "Hax actualizado."
else
  log_warn "No se encontró Ambxst en $INSTALL_PATH."
  log_info "Clonando Ambxst con Hax integrado..."
  mkdir -p "$(dirname "$INSTALL_PATH")"
  git clone "https://github.com/fabiolopezperez-hue/ambxst-Hax.git" "$INSTALL_PATH"
  log_success "Ambxst + Hax clonados en $INSTALL_PATH."
fi

# ── 5. Configurar atajo de teclado (Super + /) ────────────────
HAX_BIND='bind = SUPER, slash, exec, qs -p "$HOME/.local/src/ambxst/modules/widgets/spotlight/SpotlightView.qml"'
HYPR_CONFIG="$HOME/.config/hypr/hyprland.conf"

if [[ -f "$HYPR_CONFIG" ]]; then
  if ! grep -q "spotlight\|SpotlightView\|hax" "$HYPR_CONFIG" 2>/dev/null; then
    log_info "Añadiendo atajo Super + / para Hax..."
    printf "\n# Hax — Spotlight launcher\n%s\n" "$HAX_BIND" >> "$HYPR_CONFIG"
    log_success "Atajo configurado. Recarga Hyprland con 'hyprctl reload'."
  else
    log_info "El atajo de Hax ya existe en la configuración."
  fi
else
  log_warn "No se encontró $HYPR_CONFIG."
  log_info "Añade manualmente esta línea a tu configuración de Hyprland:"
  echo "  $HAX_BIND"
fi

echo ""
log_success "¡Instalación completada! 🎯"
echo -e "Presiona ${GREEN}Super + /${NC} para abrir Hax."
echo -e "Si ya tienes Hyprland corriendo: ${BLUE}hyprctl reload${NC}"
