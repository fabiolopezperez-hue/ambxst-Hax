#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Hax — Installer
# ═══════════════════════════════════════════════════════════════
# Instala Hax (el spotlight/launcher de Axenide) con todas
# sus dependencias sobre Ambxst.
#
# ¿Qué instala?
#   • Hax (SpotlightView.qml) — buscador universal
#   • Servicios: Visibilities, GlobalShortcuts, LockscreenService,
#     Screenshot, WeatherService, AppSearch, AxctlService, SuspendManager
#   • GlobalStates
#   • Theme: Colors, Icons, Styling
#   • Componentes: StyledRect
#   • Config + defaults
#   • shell.qml (entry point con el Loader de Hax)
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

# ── 2. Detectar / instalar Ambxst ─────────────────────────────
AMBXST_SRC="${AMBXST_SRC:-$HOME/.local/src/ambxst}"

install_ambxst() {
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
}

if has_cmd ambxst || [[ -f /usr/local/bin/ambxst ]] || [[ -f "$HOME/.local/bin/ambxst" ]]; then
  log_info "Ambxst ya está instalado."
else
  install_ambxst
fi

# Si el source no existe, clonarlo
if [[ ! -d "$AMBXST_SRC" ]]; then
  log_info "Source de Ambxst no encontrado en $AMBXST_SRC. Clonando..."
  mkdir -p "$(dirname "$AMBXST_SRC")"
  git clone "https://github.com/fabiolopezperez-hue/ambxst-Hax.git" "$AMBXST_SRC"
  log_success "ambxst-Hax clonado en $AMBXST_SRC."
fi

# ── 3. Verificar dependencias del sistema ─────────────────────
log_info "Verificando dependencias del sistema..."

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
ESSENTIAL_TOOLS=(grim slurp jq playerctl wl-clipboard brightnessctl)
for tool in "${ESSENTIAL_TOOLS[@]}"; do
  has_cmd "$tool" || DEPS_MISSING+=("$tool")
done

if [[ ${#DEPS_MISSING[@]} -gt 0 ]]; then
  log_info "Instalando dependencias: ${DEPS_MISSING[*]}"
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
      log_warn "Instala manualmente: ${DEPS_MISSING[*]}"
      ;;
  esac
  log_success "Dependencias del sistema instaladas."
else
  log_info "Todas las dependencias del sistema están presentes."
fi

# ── 4. Instalar / actualizar Hax + dependencias en Ambxst ─────
log_info "Instalando Hax y sus dependencias en $AMBXST_SRC..."

# Módulos
cp -r "$REPO_DIR/modules/widgets/spotlight"   "$AMBXST_SRC/modules/widgets/"
cp -r "$REPO_DIR/modules/services/"*          "$AMBXST_SRC/modules/services/"
cp -r "$REPO_DIR/modules/globals/"*           "$AMBXST_SRC/modules/globals/"
cp -r "$REPO_DIR/modules/theme/"*             "$AMBXST_SRC/modules/theme/"
cp -r "$REPO_DIR/modules/components/"*        "$AMBXST_SRC/modules/components/"

# Config
cp -r "$REPO_DIR/config/Config.qml"           "$AMBXST_SRC/config/Config.qml"
cp -r "$REPO_DIR/config/defaults/"*           "$AMBXST_SRC/config/defaults/"

# Entry point
cp "$REPO_DIR/shell.qml"                      "$AMBXST_SRC/shell.qml"

log_success "Hax y todas sus dependencias instalados en $AMBXST_SRC."

# ── 5. Configurar atajo de teclado (Super + /) ────────────────
HAX_BIND="bind = SUPER, slash, exec, qs -p \"$AMBXST_SRC/modules/widgets/spotlight/SpotlightView.qml\""
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

# ── 6. Mensaje final ─────────────────────────────────────────
echo ""
log_success "¡Instalación completada! 🎯"
echo -e "Presiona ${GREEN}Super + /${NC} para abrir Hax."
echo -e "Si ya tienes Hyprland corriendo: ${BLUE}hyprctl reload${NC}"
echo ""
echo -e "${YELLOW}📌  Para lanzar Hax manualmente:${NC}"
echo -e "    ${BLUE}qs -p $AMBXST_SRC/modules/widgets/spotlight/SpotlightView.qml${NC}"
