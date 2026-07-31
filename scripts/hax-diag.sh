#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Hax — Diagnóstico del atajo Super + space
#  Comprueba por qué no se abre Hax con Super + space y da la solución.
#
#  Uso:
#    bash <(curl -sSL https://raw.githubusercontent.com/fabiolopezperez-hue/ambxst-Hax/main/scripts/hax-diag.sh)
#    o directamente: ./hax-diag.sh
# ─────────────────────────────────────────────────────────────

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠ ${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${CYAN}ℹ${NC} $1"; }

echo -e "${BOLD}🔍 Diagnóstico de Hax — atajo Super + space${NC}\n"
ISSUES=0

# ── 1. ¿Existe Quickshell (qs)? ──────────────────────────────
if command -v qs >/dev/null 2>&1; then
  ok "Quickshell (qs) encontrado: $(command -v qs)"
else
  err "No se encuentra 'qs' en el PATH. Hax no puede abrirse sin Quickshell."
  ISSUES=$((ISSUES+1))
fi

# ── 2. ¿Está Hax instalado? ──────────────────────────────────
SHELL_SRC=""
for s in "$HOME/.local/src/ambxst" "$HOME/.local/src/ambxst-Hax"; do
  if [[ -f "$s/modules/widgets/spotlight/SpotlightView.qml" ]]; then
    SHELL_SRC="$s"; break
  fi
done
if [[ -n "$SHELL_SRC" ]]; then
  ok "Hax instalado en: $SHELL_SRC"
else
  err "No se encuentra SpotlightView.qml en $HOME/.local/src/ambxst ni ambxst-Hax."
  ISSUES=$((ISSUES+1))
fi

# ── 3. ¿Estamos dentro de Hyprland? ──────────────────────────
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
  ok "Sesión Hyprland detectada (hyprctl responde)"
else
  warn "No hay sesión Hyprland activa (hyprctl no responde). El atajo solo se configura en Hyprland."
  ISSUES=$((ISSUES+1))
fi

# ── 4. Buscar binds de Hax en las configs de Hyprland ────────
CONF_FILES=()
[[ -f "$HOME/.config/hypr/hyprland.conf" ]] && CONF_FILES+=("$HOME/.config/hypr/hyprland.conf")
[[ -f "$HOME/.config/hypr/hyprland.lua"   ]] && CONF_FILES+=("$HOME/.config/hypr/hyprland.lua")
if [[ -d "$HOME/.config/hypr/hyprland.conf.d" ]]; then
  while IFS= read -r f; do CONF_FILES+=("$f"); done < <(find "$HOME/.config/hypr/hyprland.conf.d" -name "*.conf" 2>/dev/null)
fi

if [[ ${#CONF_FILES[@]} -eq 0 ]]; then
  warn "No se encontró ninguna config de Hyprland en ~/.config/hypr (¿está en otra ruta?)."
  ISSUES=$((ISSUES+1))
fi

HAS_SPACE_BIND=0
HAS_OLD_BIND=0
for f in "${CONF_FILES[@]}"; do
  while IFS= read -r line; do
    if [[ "$line" == *"SpotlightView"* ]]; then
      if [[ "$line" == *"SUPER, space"* || "$line" == *"SUPER + Space"* ]]; then
        HAS_SPACE_BIND=1
      else
        HAS_OLD_BIND=1
      fi
    fi
  done < <(grep -n "SpotlightView\|hax" "$f" 2>/dev/null)
done

if [[ "$HAS_SPACE_BIND" -eq 1 ]]; then
  ok "Bind de Hax con Super + space encontrado en la config"
elif [[ "$HAS_OLD_BIND" -eq 1 ]]; then
  warn "Tienes un bind de Hax con OTRA tecla (p.ej. Super + /). Se necesita Super + space."
  ISSUES=$((ISSUES+1))
else
  err "No hay ningún bind de Hax en la config de Hyprland."
  ISSUES=$((ISSUES+1))
fi

# ── 5. ¿Super + space está ocupado por otro programa? ────────
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
  OTHER_SPACE=$(hyprctl binds 2>/dev/null | grep -i "SUPER" | grep -i "space" | grep -iv "SpotlightView")
  if [[ -n "$OTHER_SPACE" ]]; then
    warn "Super + space ya está asignado a OTRO programa:"
    echo "$OTHER_SPACE" | sed 's/^/    → /'
    ISSUES=$((ISSUES+1))
  else
    ok "No hay conflictos: Super + space no está usado por otro programa"
  fi
fi

# ── Resumen y soluciones ─────────────────────────────────────
echo
if [[ "$ISSUES" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✅ Todo parece correcto.${NC} ${BOLD}Prueba esto:${NC}"
  echo -e "   1.  ${BOLD}hyprctl reload${NC}"
  echo -e "   2.  Pulsa ${BOLD}Super + space${NC} — si sigue sin abrir, prueba con ${BOLD}hyprctl dispatch exec 'qs -p \"$SHELL_SRC/modules/widgets/spotlight/SpotlightView.qml\"'${NC}"
else
  echo -e "${YELLOW}${BOLD}Se encontraron $ISSUES problema(s). Soluciones:${NC}"
  echo -e "   1.  Re-ejecuta el instalador (ya migra solo al nuevo atajo):"
  echo -e "       ${BOLD}curl -sSL https://raw.githubusercontent.com/fabiolopezperez-hue/ambxst-Hax/main/hax-install.sh | bash${NC}"
  echo -e "   2.  O añade a mano en tu config de Hyprland y luego ${BOLD}hyprctl reload${NC}:"
  echo -e "       ${BOLD}bind = SUPER, space, exec, qs -p \"$HOME/.local/src/ambxst/modules/widgets/spotlight/SpotlightView.qml\"${NC}"
  echo -e "   3.  Si Super + space ya lo usa otro programa, cambia esa tecla (o el atajo de Hax)."
fi
echo
echo -e "${CYAN}ℹ  Si nada de esto funciona, comparte esta salida en el Discord de Hax (fabio_777).${NC}"
