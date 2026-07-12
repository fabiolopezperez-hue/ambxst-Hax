#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Hax — Live Text (OCR)
# Extrae el texto escrito DENTRO de imágenes con Tesseract y lo indexa
# para que el buscador de Hax pueda encontrar palabras que están en
# una foto/captura, no solo en archivos de texto.
#
# Caché: ~/.local/share/hax/ocr.txt
#   Formato por línea:  <mtime>\x1f<ruta>\x1f<texto OCR (una línea)>
#   El separador es el carácter US (unit separator, \x1f) para poder
#   usar rutas y textos con espacios sin ambigüedad.
#
# Uso:
#   ocr.sh get    <ruta>          → imprime el texto OCR (lo genera si hace falta)
#   ocr.sh search <query>         → imprime "<ruta>\x1f<snippet>" por cada coincidencia
#   ocr.sh index  <dir> [prof]    → indexa imágenes de <dir> (profundidad opcional)
# ═══════════════════════════════════════════════════════════════════

set -u

# Idiomas por defecto (inglés + español). Se puede ampliar.
LANGS="${HAX_OCR_LANGS:-eng+spa}"

# Separador US (ascii 31)
SEP=$'\x1f'

CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hax"
CACHE="$CACHE_DIR/ocr.txt"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
touch "$CACHE" 2>/dev/null || true

cmd="${1:-}"

case "$cmd" in
  get)
    path="${2:-}"
    [ -f "$path" ] || { echo ""; exit 0; }
    mtime=$(stat -c %Y "$path" 2>/dev/null || echo 0)
    # ¿Ya está en caché con el mismo mtime?
    cached=$(awk -F"$SEP" -v p="$path" -v m="$mtime" '$2==p && $1==m {print $3; exit}' "$CACHE" 2>/dev/null)
    if [ -n "$cached" ]; then
      echo "$cached"
      exit 0
    fi
    # OCR al vuelo
    text=$(tesseract "$path" stdout -l "$LANGS" 2>/dev/null || true)
    text_oneline=$(printf '%s' "$text" | tr '\n' ' ' | sed 's/  */ /g')
    # Actualizar caché (reescribir la entrada de esta ruta)
    grep -v -F "${SEP}${path}${SEP}" "$CACHE" > "$CACHE.tmp" 2>/dev/null || true
    printf '%s%s%s%s%s\n' "$mtime" "$SEP" "$path" "$SEP" "$text_oneline" >> "$CACHE.tmp"
    mv "$CACHE.tmp" "$CACHE" 2>/dev/null || cp "$CACHE.tmp" "$CACHE" 2>/dev/null || true
    echo "$text_oneline"
    ;;

  search)
    q="${2:-}"
    [ -z "$q" ] && exit 0
    ql=$(printf '%s' "$q" | tr '[:upper:]' '[:lower:]')
    awk -F"$SEP" -v sep="$SEP" -v q="$ql" '
      $3 != "" && tolower($3) ~ q {
        low = tolower($3)
        idx = index(low, q)
        snip = substr($3, idx, 90)
        printf "%s%s%s\n", $2, sep, snip
      }
    ' "$CACHE" 2>/dev/null
    ;;

  index)
    dir="${2:-}"
    maxd="${3:-5}"
    [ -d "$dir" ] || exit 0
    # Listar imágenes con su mtime; una por línea: "<mtime>|<ruta>"
    find "$dir" -maxdepth "$maxd" -type f \( \
        -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o \
        -iname '*.webp' -o -iname '*.bmp' -o -iname '*.tiff' -o -iname '*.gif' \
      \) -printf '%T@|%p\n' 2>/dev/null || true | \
    while IFS='|' read -r mt path; do
      [ -z "$path" ] && continue
      mtime=${mt%.*}
      # ¿Ya indexada con el mismo mtime?
      if ! awk -F"$SEP" -v p="$path" -v m="$mtime" '$2==p && $1==m {f=1} END{exit !f}' "$CACHE" 2>/dev/null; then
        text=$(tesseract "$path" stdout -l "$LANGS" 2>/dev/null || true)
        text_oneline=$(printf '%s' "$text" | tr '\n' ' ' | sed 's/  */ /g')
        grep -v -F "${SEP}${path}${SEP}" "$CACHE" > "$CACHE.tmp" 2>/dev/null || true
        printf '%s%s%s%s%s\n' "$mtime" "$SEP" "$path" "$SEP" "$text_oneline" >> "$CACHE.tmp"
        mv "$CACHE.tmp" "$CACHE" 2>/dev/null || cp "$CACHE.tmp" "$CACHE" 2>/dev/null || true
      fi
      sleep 0.15
    done
    ;;

  *)
    echo "Uso: ocr.sh get|search|index" >&2
    exit 1
    ;;
esac
