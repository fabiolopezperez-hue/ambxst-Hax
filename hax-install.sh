#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Hax — Installer
# ═══════════════════════════════════════════════════════════════
# Instala Hax (el spotlight/launcher de Axenide) sobre Ambxst.
#
# ¿Qué instala?
#   • Hax (SpotlightView.qml + qmldir) — buscador universal (~5490 líneas)
#   • Config.qml — con persistencia de acciones rápidas
#   • config/defaults/hax.js — defaults de Hax
#   • assets/presets/.../hax.json — preset inicial
#   • Terminal embebida: qmltermwidget (plugin QML que compila contra Qt6)
#
# El resto (servicios, theme, componentes, scripts, fuentes) los provee
# Ambxst, que se instala automáticamente si no está presente.
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

  # Si no se encontró, preguntar (o usar el default si no hay terminal interactiva)
  if [[ ! -d "$SHELL_SRC/modules/widgets" ]]; then
    if [[ ! -t 0 ]]; then
      # Sin terminal (p. ej. curl | bash): usamos la ruta por defecto y el paso 4
      # clona Ambxst automáticamente si hace falta.
      log_info "Sin terminal interactiva — usando ruta por defecto: $SHELL_SRC"
    else
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
fi

# (La validación de la estructura de módulos se hace después del paso 4,
#  porque este puede clonar Ambxst automáticamente en la ruta por defecto.)

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

# OCR (Live Text) — Tesseract + datos de idioma (inglés + español por defecto)
case "$DISTRO" in
  arch)
    has_cmd tesseract || DEPS_MISSING+=("tesseract" "tesseract-data-eng" "tesseract-data-spa") ;;
  fedora)
    has_cmd tesseract || DEPS_MISSING+=("tesseract" "tesseract-langpack-eng" "tesseract-langpack-spa") ;;
  debian)
    has_cmd tesseract || DEPS_MISSING+=("tesseract-ocr" "tesseract-ocr-eng" "tesseract-ocr-spa") ;;
  *)
    has_cmd tesseract || log_warn "Tesseract no encontrado — Live Text necesita 'tesseract' + datos de idioma (eng/spa)." ;;
esac

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

  # Validar que la shell destino tenga la estructura de módulos
  # (ya sea la que había o la que acabamos de clonar en el paso 4).
  if [[ ! -d "$SHELL_SRC/modules/widgets" ]]; then
    log_error "No se encontró la estructura de módulos en $SHELL_SRC"
    log_error "¿Seguro que es una shell basada en Ambxst? Debe contener modules/widgets/"
    exit 1
  fi

# ── 4b. Terminal embebida: build + install de qmltermwidget ──
# Hax integra una terminal real (PTY) vía el plugin QMLTermWidget.
# Se compila desde fuentes contra Qt6 y se instala en el árbol de QML.
install_qmltermwidget() {
  # Detectar sudo (si no existe, lo usamos vacío y daremos error claro)
  local SUDO=""
  if has_cmd sudo; then SUDO="sudo"; fi

  # Detectar el qmake de Qt6 (el MISMO que usa Quickshell)
  local QMAKE_BIN=""
  if has_cmd qmake6; then QMAKE_BIN="qmake6"
  elif has_cmd qmake-qt6; then QMAKE_BIN="qmake-qt6"
  elif has_cmd qmake; then QMAKE_BIN="qmake"
  fi

  # Ruta de instalación del plugin (árbol de imports QML de Qt6)
  local QML_DIR PLUGIN_DIR
  if [[ -n "$QMAKE_BIN" ]]; then
    QML_DIR="$($QMAKE_BIN -query QT_INSTALL_QML 2>/dev/null)"
  fi
  QML_DIR="${QML_DIR:-/usr/lib/qt6/qml}"
  PLUGIN_DIR="$QML_DIR/QMLTermWidget"

  if [[ -f "$PLUGIN_DIR/libqmltermwidget.so" ]]; then
    log_info "qmltermwidget ya está instalado ($PLUGIN_DIR) — saltando."
    return 0
  fi

  log_info "Instalando qmltermwidget (terminal embebida de Hax)..."

  # Si no hay qmake de Qt6, no podemos compilar
  if [[ -z "$QMAKE_BIN" ]]; then
    log_error "No se encontró qmake (Qt6). No se puede compilar qmltermwidget."
    log_error "Instálalo manualmente: https://github.com/Swordfish90/qmltermwidget"
    return 1
  fi

  # Dependencias de build por distro
  local BUILD_DEPS=()
  case "$DISTRO" in
    arch)
      has_cmd qmake6 || has_cmd qmake-qt6 || BUILD_DEPS+=("qt6-base")
      [[ -d /usr/include/qt6/QtQml ]] || BUILD_DEPS+=("qt6-declarative")
      has_cmd gcc || BUILD_DEPS+=("base-devel")
      ;;
    fedora)
      has_cmd qmake-qt6 || BUILD_DEPS+=("qt6-qtbase-devel" "qt6-qtdeclarative-devel")
      has_cmd gcc || BUILD_DEPS+=("gcc-c++" "make")
      ;;
    *)
      log_warn "Distro '$DISTRO' no soportada para build automático de qmltermwidget."
      log_warn "Instálalo manualmente desde https://github.com/Swordfish90/qmltermwidget"
      return 0
      ;;
  esac

  if [[ ${#BUILD_DEPS[@]} -gt 0 ]]; then
    log_info "Instalando dependencias de build: ${BUILD_DEPS[*]}"
    case "$DISTRO" in
      arch)
        if has_cmd yay || has_cmd paru; then
          local AUR=""; has_cmd yay && AUR=yay || AUR=paru
          $AUR -S --needed --noconfirm "${BUILD_DEPS[@]}"
        else
          $SUDO pacman -S --needed --noconfirm "${BUILD_DEPS[@]}"
        fi
        ;;
      fedora)
        $SUDO dnf install -y "${BUILD_DEPS[@]}"
        ;;
    esac
  fi

  # Re-detectar qmake tras instalar dependencias
  if has_cmd qmake6; then QMAKE_BIN="qmake6"
  elif has_cmd qmake-qt6; then QMAKE_BIN="qmake-qt6"
  elif has_cmd qmake; then QMAKE_BIN="qmake"
  else
    log_error "No se encontró qmake (Qt6) tras instalar dependencias. Abortando."
    return 1
  fi

  # Clonar fuentes — con la revisión fija (commit 8913504) para API estable.
  # NOTA: NO usamos --depth para poder hacer checkout de un commit concreto.
  local SRC_TMP="$(mktemp -d)"
  git clone "https://github.com/Swordfish90/qmltermwidget.git" "$SRC_TMP" \
    || { log_error "No se pudo clonar qmltermwidget."; rm -rf "$SRC_TMP"; return 1; }
  if ! git -C "$SRC_TMP" checkout 8913504 2>/dev/null; then
    log_warn "No se pudo hacer checkout del commit fijo (8913504) — usando rama por defecto."
  fi

  # Compilar
  log_info "Compilando qmltermwidget (esto puede tardar un poco)..."
  ( cd "$SRC_TMP" && "$QMAKE_BIN" && make -j"$(nproc 2>/dev/null || echo 4)" ) \
    || { log_error "Falló la compilación de qmltermwidget."; rm -rf "$SRC_TMP"; return 1; }

  # Instalar en el árbol de QML de Qt6 (con sudo si hace falta)
  if [[ -w "$QML_DIR" ]]; then
    make -C "$SRC_TMP" install \
      || { log_error "Falló la instalación de qmltermwidget."; rm -rf "$SRC_TMP"; return 1; }
  else
    if [[ -z "$SUDO" ]]; then
      log_error "El directorio $QML_DIR no es escribible y no hay 'sudo'."
      log_error "Ejecuta como root o instala manualmente qmltermwidget."
      rm -rf "$SRC_TMP"
      return 1
    fi
    $SUDO make -C "$SRC_TMP" install \
      || { log_error "Falló la instalación de qmltermwidget."; rm -rf "$SRC_TMP"; return 1; }
  fi

  rm -rf "$SRC_TMP"

  if [[ -f "$PLUGIN_DIR/libqmltermwidget.so" ]]; then
    log_success "qmltermwidget instalado en $PLUGIN_DIR."
  else
    log_error "La instalación de qmltermwidget no produjo el plugin en $PLUGIN_DIR."
    return 1
  fi
}

install_qmltermwidget \
  || log_warn "No se pudo instalar qmltermwidget — la terminal embebida no funcionará, pero Hax se instala igual."

# ── 4c. Fuente de iconos Phosphor ──
# La fuente Phosphor la provee Ambxst — no se empaqueta en el repo.

# ── 5. Instalar Hax + dependencias en la shell ────────────────
log_info "Instalando Hax en $SHELL_SRC..."

# Crear estructura de directorios donde va Hax
mkdir -p "$SHELL_SRC/modules/widgets"
mkdir -p "$SHELL_SRC/config/defaults"
mkdir -p "$SHELL_SRC/assets/presets"

# Módulos propios de Hax
cp -r "$REPO_DIR/modules/widgets/spotlight"   "$SHELL_SRC/modules/widgets/"

# Carpeta de plugins del usuario (~/.config/hax/plugins)
HAX_PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hax/plugins"
mkdir -p "$HAX_PLUGINS_DIR"
if [[ -f "$REPO_DIR/modules/widgets/spotlight/plugin-ejemplo.sh" ]]; then
  cp -n "$REPO_DIR/modules/widgets/spotlight/plugin-ejemplo.sh" "$HAX_PLUGINS_DIR/ejemplo.sh" 2>/dev/null || true
  chmod +x "$HAX_PLUGINS_DIR/ejemplo.sh" 2>/dev/null || true
  log_success "Carpeta de plugins creada en $HAX_PLUGINS_DIR (con plugin de ejemplo)."
fi

# Config (SIEMPRE se sobrescribe — Hax necesita su versión con persistencia)
if [[ -f "$SHELL_SRC/config/Config.qml" ]]; then
  cp "$SHELL_SRC/config/Config.qml" "$SHELL_SRC/config/Config.qml.bak.$(date +%s)"
  log_info "Config.qml anterior respaldado como Config.qml.bak.*"
fi
cp "$REPO_DIR/config/Config.qml" "$SHELL_SRC/config/Config.qml"
log_success "Config.qml actualizado con la versión de Hax (persistencia de acciones rápidas)."

cp -n "$REPO_DIR/config/defaults/"*.js "$SHELL_SRC/config/defaults/" 2>/dev/null || true

# Assets (presets para configuración inicial)
cp -rn "$REPO_DIR/assets/"* "$SHELL_SRC/assets/" 2>/dev/null || true

# Archivo de versión
cp -n "$REPO_DIR/version" "$SHELL_SRC/version" 2>/dev/null || true

# shell.qml lo provee Ambxst — no se toca

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
echo -e "Dentro de Hax escribe ${GREEN}/${NC} para abrir la terminal embebida (necesita el plugin qmltermwidget)."
echo -e "Si ya tienes Hyprland corriendo: ${BLUE}hyprctl reload${NC}"
echo ""
echo -e "${YELLOW}🔄  Para lanzar Hax manualmente:${NC}"
echo -e "    ${BLUE}qs -p $SHELL_SRC/modules/widgets/spotlight/SpotlightView.qml${NC}"
echo ""
echo -e "${YELLOW}💡  ¿Usas un fork?${NC} La próxima vez puedes hacer:"
echo -e "    ${BLUE}$(basename "$0") -t $SHELL_SRC${NC}"
