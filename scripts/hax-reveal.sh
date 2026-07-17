#!/bin/bash
# Revela un archivo en el gestor de archivos predeterminado (Dolphin).
# Primero intenta D-Bus (org.freedesktop.FileManager1) para reusar ventana existente.
# Si falla, arranca Dolphin nuevo con --select.
# Acepta rutas absolutas (/home/user/doc.txt) o URIs file://

set -euo pipefail

raw="${1:-}"
[ -z "$raw" ] && exit 1

# Limpiar posible prefijo file://
filepath="${raw#file://}"
uri="file://$filepath"

# 1. Intentar D-Bus (reusa ventana existente de Dolphin)
if dbus-send --session --dest=org.freedesktop.FileManager1 \
    /org/freedesktop/FileManager1 \
    org.freedesktop.FileManager1.ShowItems \
    array:string:"$uri" \
    string:"" >/dev/null 2>&1; then
    exit 0
fi

# 2. Fallback: arrancar Dolphin nuevo con el archivo seleccionado
export QT_QPA_PLATFORMTHEME=qtengine
cd ~ && env -u HL_INITIAL_WORKSPACE_TOKEN setsid dolphin --select "$filepath" < /dev/null > /dev/null 2>&1 &
