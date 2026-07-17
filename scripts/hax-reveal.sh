#!/bin/bash
# Revela un archivo en Thunar.
# Si Thunar no está abierto → abre uno nuevo con el archivo seleccionado
# Si Thunar ya está abierto → navega a la ruta (single instance)
# Acepta rutas absolutas (/home/user/doc.txt) o URIs file://

raw="${1:-}"
[ -z "$raw" ] && exit 0

filepath="${raw#file://}"

# Lanzar Thunar con la ruta del archivo.
# Thunar automáticamente abre la carpeta y selecciona el archivo.
# GApplication maneja single-instance: si Thunar ya está abierto,
# abre la ruta en la ventana existente.
cd ~ && env -u HL_INITIAL_WORKSPACE_TOKEN setsid thunar "$filepath" < /dev/null > /dev/null 2>&1 &
