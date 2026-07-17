#!/bin/bash
# Revela un archivo en Dolphin.
# Si Dolphin no está abierto → abre ventana nueva con --select
# Si Dolphin ya está abierto → navega la MISMA pestaña (sin crear nuevas)
# Acepta rutas absolutas (/home/user/doc.txt) o URIs file://

raw="${1:-}"
[ -z "$raw" ] && exit 0

filepath="${raw#file://}"
dirpath="$(dirname "$filepath")"
filename="$(basename "$filepath")"

if ! pgrep -x dolphin >/dev/null 2>&1; then
    # ── No hay Dolphin → abrir ventana nueva ──
    export QT_QPA_PLATFORMTHEME=qtengine
    cd ~ && env -u HL_INITIAL_WORKSPACE_TOKEN setsid dolphin --select "$filepath" < /dev/null > /dev/null 2>&1 &
    exit 0
fi

# ── Dolphin ya abierto → navegar la MISMA pestaña ──
hyprctl dispatch focuswindow "class:org.kde.dolphin" 2>/dev/null
sleep 0.05

ydotool key ctrl+l
sleep 0.03

ydotool type "$dirpath"
sleep 0.02

ydotool key enter
sleep 0.15

ydotool key ctrl+f
sleep 0.03

ydotool type "$filename"
