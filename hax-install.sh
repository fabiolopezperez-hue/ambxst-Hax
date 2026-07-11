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
#   • Scripts: google_lens.sh, weather.sh
#   • shell.qml (entry point con el Loader de Hax)
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}ℹ  $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✔  $1${NC}" >&2; }
log_warn()    { echo -e "${YELLOW}⚠  $1${NC}" >&2; }
log_error()   { echo -e "${RED}✖  $1${NC}" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ── Si el script se ejecuta via curl | bash, clonar el repo ────
if [[ ! -d "$SCRIPT_DIR/modules/widgets/spotlight" ]]; then
  REPO_DIR="$(mktemp -d)"
  log_info "Ejecutando desde pipe — clonando ambxst-Hax temporalmente..."
  git clone --depth 1 "https://github.com/fabiolopezperez-hue/ambxst-Hax.git" "$REPO_DIR"
  trap "rm -rf '$REPO_DIR'" EXIT
else
  REPO_DIR="$SCRIPT_DIR"
fi

# ── Ayuda ──────────────────────────────────────────────────────
usage() {
  cat <<EOF
Uso: $(basename "$0") [-t <directorio>] [-h]

Instala Hax (spotlight/launcher) con todas sus dependencias.

Opciones:
  -t <directorio>   Ruta donde está tu shell basada en Ambxst
                    (por defecto: \$AMBXST_SRC o ~/.local/src/ambxst)
  -h                Muestra esta ayuda

Ejemplos:
  # Ambxst estándar
  ./hax-install.sh

  # Shell personalizada basada en Ambxst
  ./hax-install.sh -t ~/Repos/mi-shell

  # Misma ruta con variable de entorno
  AMBXST_SRC=~/Repos/mi-shell ./hax-install.sh

¿Cómo funciona?
  Hax se inyecta en cualquier shell basada en Ambxst. No necesitas
  tener Ambxst original — solo una shell que siga su misma estructura
  de módulos (modules/widgets/spotlight, modules/services/, etc.).
  Usa -t para apuntar a tu shell aunque sea un fork o custom.
EOF
  exit 0
}

# ── Parsear argumentos ─────────────────────────────────────────
TARGET_DIR=""
while getopts "t:h" opt; do
  case "$opt" in
    t) TARGET_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

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

# ── 2. Determinar el directorio destino ───────────────────────
if [[ -n "$TARGET_DIR" ]]; then
  SHELL_SRC="$TARGET_DIR"
  log_info "Usando directorio destino: $SHELL_SRC"
else
  SHELL_SRC="${AMBXST_SRC:-$HOME/.local/src/ambxst}"

  # Auto-detección: buscar shells basadas en Ambxst
  if [[ ! -d "$SHELL_SRC" ]]; then
    for candidate in "$HOME/.local/src/ambxst" "$HOME/.local/src/ax-shell" "$HOME/.local/src/mi-shell" "$HOME/Repos/ambxst" "$HOME/Repos/ax-shell"; do
      if [[ -d "$candidate/modules/widgets" ]]; then
        SHELL_SRC="$candidate"
        log_info "Shell detectada en: $SHELL_SRC"
        break
      fi
    done
  fi

  # Si no se encontró, preguntar
  if [[ ! -d "$SHELL_SRC/modules/widgets" ]]; then
    echo ""
    log_warn "No se encontró ninguna shell basada en Ambxst."
    echo ""
    echo -e "${YELLOW}¿Dónde tienes tu shell?${NC}"
    echo "Ejemplos:"
    echo "  ~/.local/src/ambxst         (Ambxst original)"
    echo "  ~/Repos/mi-shell            (tu fork personal)"
    echo "  ~/.local/src/ax-shell       (Ax-shell)"
    echo ""
    read -r -p "👉 Ruta (o pulsa Enter para cancelar): " USER_PATH
    echo ""
    if [[ -z "$USER_PATH" ]]; then
      log_error "Instalación cancelada."
      exit 1
    fi
    SHELL_SRC="$USER_PATH"
  fi
fi

# Validar que exista
if [[ ! -d "$SHELL_SRC/modules/widgets" ]]; then
  log_error "No se encontró la estructura de módulos en $SHELL_SRC"
  log_error "¿Seguro que es una shell basada en Ambxst? Debe contener modules/widgets/"
  exit 1
fi

log_success "Shell destino: $SHELL_SRC"
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

# ── 4. Verificar/instalar Ambxst (solo si es Ambxst original) ──
if [[ "$SHELL_SRC" == "$HOME/.local/src/ambxst" ]] || [[ "$SHELL_SRC" == *"ambxst" ]]; then
  if ! has_cmd ambxst && [[ ! -f /usr/local/bin/ambxst ]] && [[ ! -f "$HOME/.local/bin/ambxst" ]]; then
    log_info "Ambxst no está instalado. Instalando..."
    bash <(curl -sL get.axeni.de/ambxst)
    log_success "Ambxst instalado correctamente."
  else
    log_info "Ambxst ya está instalado."
  fi

  # Si el source no existe, clonar Ambxst original
  if [[ ! -d "$SHELL_SRC" ]]; then
    log_info "Source no encontrado en $SHELL_SRC. Clonando Ambxst original..."
    mkdir -p "$(dirname "$SHELL_SRC")"
    git clone "https://github.com/Axenide/Ambxst.git" "$SHELL_SRC"
    log_success "Ambxst original clonado en $SHELL_SRC."
  fi
else
  log_info "Shell personalizada detectada — saltando instalación de Ambxst."
fi

# ── 5. Instalar Hax + dependencias en la shell ────────────────
log_info "Instalando Hax en $SHELL_SRC..."

# Crear estructura de directorios si no existe
mkdir -p "$SHELL_SRC/modules/widgets"
mkdir -p "$SHELL_SRC/modules/services"
mkdir -p "$SHELL_SRC/modules/globals"
mkdir -p "$SHELL_SRC/modules/theme"
mkdir -p "$SHELL_SRC/modules/components"
mkdir -p "$SHELL_SRC/modules/tools"
mkdir -p "$SHELL_SRC/config/defaults"
mkdir -p "$SHELL_SRC/scripts"
mkdir -p "$SHELL_SRC/assets/presets"

# Módulos propios de Hax
cp -r "$REPO_DIR/modules/widgets/spotlight"   "$SHELL_SRC/modules/widgets/"

# Dependencias (servicios, theme, etc.)
cp    "$REPO_DIR/modules/services/"*.qml      "$SHELL_SRC/modules/services/" 2>/dev/null || true
cp    "$REPO_DIR/modules/globals/"*.qml       "$SHELL_SRC/modules/globals/" 2>/dev/null || true
cp    "$REPO_DIR/modules/theme/"*.qml         "$SHELL_SRC/modules/theme/" 2>/dev/null || true
cp    "$REPO_DIR/modules/components/"*.qml    "$SHELL_SRC/modules/components/" 2>/dev/null || true
cp -n "$REPO_DIR/modules/tools/"*.qml         "$SHELL_SRC/modules/tools/" 2>/dev/null || true

# Scripts de servicio (google_lens.sh, weather.sh)
cp -n "$REPO_DIR/scripts/"*.sh                "$SHELL_SRC/scripts/" 2>/dev/null || true

# JS de configuración (KeybindActions, ConfigValidator)
cp -n "$REPO_DIR/config/"*.js                 "$SHELL_SRC/config/" 2>/dev/null || true

# Config (preservar la existente si la hay)
if [[ -f "$SHELL_SRC/config/Config.qml" ]]; then
  log_info "Config.qml ya existe — no se sobrescribe."
  log_info "  Revisa manualmente si necesitas fusionar los cambios de Hax."
else
  cp "$REPO_DIR/config/Config.qml" "$SHELL_SRC/config/Config.qml"
fi

cp -n "$REPO_DIR/config/defaults/"*.js "$SHELL_SRC/config/defaults/" 2>/dev/null || true

# Assets (presets para configuración inicial)
cp -rn "$REPO_DIR/assets/"* "$SHELL_SRC/assets/" 2>/dev/null || true

# Archivo de versión
cp -n "$REPO_DIR/version" "$SHELL_SRC/version" 2>/dev/null || true

# Entry point (solo si no existe)
if [[ ! -f "$SHELL_SRC/shell.qml" ]]; then
  cp "$REPO_DIR/shell.qml" "$SHELL_SRC/shell.qml"
  log_info "shell.qml creado como entry point con el Loader de Hax."
else
  log_info "shell.qml ya existe — no se sobrescribe."
fi

log_success "Hax instalado en $SHELL_SRC."

# ── 6. Configurar atajo de teclado (Super + /) ────────────────
# Soporta tanto hyprland.conf (hyprlang) como hyprland.lua (nuevo formato 0.55+)
HAX_CMD="qs -p \"$SHELL_SRC/modules/widgets/spotlight/SpotlightView.qml\""
HAX_CONF_BIND="bind = SUPER, slash, exec, $HAX_CMD"
HAX_LUA_BIND="hl.bind(\"SUPER + Slash\", hl.dsp.exec_cmd('$HAX_CMD'))"

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"

if [[ -f "$HYPR_LUA" ]]; then
  if ! grep -q "spotlight\|SpotlightView\|hax" "$HYPR_LUA" 2>/dev/null; then
    log_info "Añadiendo atajo Super + / para Hax (formato Lua)..."
    printf "\n-- Hax — Spotlight launcher\n%s\n" "$HAX_LUA_BIND" >> "$HYPR_LUA"
    log_success "Atajo configurado. Recarga Hyprland con 'hyprctl reload'."
  else
    log_info "El atajo de Hax ya existe en hyprland.lua."
  fi
elif [[ -f "$HYPR_CONF" ]]; then
  if ! grep -q "spotlight\|SpotlightView\|hax" "$HYPR_CONF" 2>/dev/null; then
    log_info "Añadiendo atajo Super + / para Hax (formato hyprlang)..."
    printf "\n# Hax — Spotlight launcher\n%s\n" "$HAX_CONF_BIND" >> "$HYPR_CONF"
    log_success "Atajo configurado. Recarga Hyprland con 'hyprctl reload'."
  else
    log_info "El atajo de Hax ya existe en hyprland.conf."
  fi
else
  log_warn "No se encontró hyprland.lua ni hyprland.conf."
  log_info "Añade manualmente a tu configuración de Hyprland:"
  log_info "  Formato hyprlang (.conf):  $HAX_CONF_BIND"
  log_info "  Formato Lua (.lua):        $HAX_LUA_BIND"
fi

# ── 7. Mensaje final ─────────────────────────────────────────
echo ""
log_success "¡Instalación completada! 🎯"
echo ""
echo -e "${GREEN}📌  Hax está listo en:${NC}"
echo -e "    $SHELL_SRC/modules/widgets/spotlight/SpotlightView.qml"
echo ""
echo -e "Presiona ${GREEN}Super + /${NC} para abrir Hax."
echo -e "Si ya tienes Hyprland corriendo: ${BLUE}hyprctl reload${NC}"
echo ""
echo -e "${YELLOW}🔄  Para lanzar Hax manualmente:${NC}"
echo -e "    ${BLUE}qs -p $SHELL_SRC/modules/widgets/spotlight/SpotlightView.qml${NC}"
echo ""
echo -e "${YELLOW}💡  ¿Usas un fork?${NC} La próxima vez puedes hacer:"
echo -e "    ${BLUE}$(basename "$0") -t $SHELL_SRC${NC}"
