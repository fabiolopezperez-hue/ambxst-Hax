#!/usr/bin/env bash
# dict.sh — Glosario / Diccionario para Hax
# Uso: dict.sh <palabra> [lang]
#   lang: "es" (por defecto) o "en".
#   Fuentes en cascada: Wiktionary (es) -> Wiktionary (en) -> Wikipedia (es).
#   Muestra la primera fuente que devuelva definición.
set -u

word="${1:-}"
lang="${2:-es}"

if [ -z "$word" ]; then
    echo "Uso: dict.sh <palabra> [es|en]"
    exit 1
fi

urlencode() {
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

# Wiktionary: devuelve definiciones limpias (una por línea "N. texto") o cadena vacía.
fetch_wikt() {
    local L="$1" W="$2"
    local u="https://$L.wiktionary.org/w/api.php?action=query&titles=$(urlencode "$W")&redirects=1&prop=revisions&rvprop=content&rvslots=main&format=json"
    curl -s --max-time 15 "$u" | python3 -c '
import sys, json, re
L = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
pages = (d.get("query") or {}).get("pages") or {}
for pid, p in pages.items():
    if pid == "-1":
        continue
    revs = p.get("revisions") or []
    if not revs:
        continue
    txt = revs[0].get("slots", {}).get("main", {}).get("*", "")
    if not txt:
        continue
    if L == "es":
        key = "{{lengua|es}}"
        start = txt.find(key)
        if start == -1:
            continue
        nl = txt.find("\n", start)
        begin = nl + 1 if nl != -1 else start + len(key)
        nxt = txt.find("{{lengua|", begin)
        sec = txt[begin:nxt] if nxt != -1 else txt[begin:]
        prefix = r"^\s*;\s*\d+\b[^:]*:\s*(.+)"
    else:
        key = "==English=="
        start = txt.find(key)
        if start == -1:
            continue
        nl = txt.find("\n", start)
        begin = nl + 1 if nl != -1 else start + len(key)
        mm = re.search(r"\n==\s", txt[begin:])
        nxt = begin + mm.start() if mm else -1
        sec = txt[begin:nxt] if nxt != -1 else txt[begin:]
        prefix = r"^\s*#\s+(.+)"
    def re_clean(s):
        s = re.sub(r"\{\{plm\|([^}|]+?)(?:\|[^{}]*)?\}\}", r"\1", s)
        s = re.sub(r"\{\{[^}]*\}\}", "", s)
        s = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", s)
        s = re.sub(r"<[^>]+>", "", s)
        s = s.replace(chr(39) + chr(39), "")
        return re.sub(r"\s+", " ", s).strip()
    defs = []
    for line in sec.splitlines():
        mm = re.match(prefix, line)
        if not mm:
            continue
        s = re_clean(mm.group(1))
        if s:
            defs.append(s)
        if len(defs) >= 5:
            break
    if defs:
        for i, t in enumerate(defs, 1):
            print("%d. %s" % (i, t))
        sys.exit(0)
' "$L"
}

# Wikipedia (es): extracto enciclopédico de la página.
fetch_wiki() {
    local W="$1"
    curl -s --max-time 15 "https://es.wikipedia.org/api/rest_v1/page/summary/$(urlencode "$W")" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ext = (d.get("extract") or "").strip()
if ext:
    print(ext[:700])
' 2>/dev/null
}

# 1) Wiktionary en el idioma pedido
res=$(fetch_wikt "$lang" "$word")
src="Wiktionary ($lang)"

# 2) Wiktionary en el otro idioma como respaldo
if [ -z "$res" ]; then
    other="en"
    [ "$lang" = "en" ] && other="es"
    res=$(fetch_wikt "$other" "$word")
    src="Wiktionary ($other)"
fi

# 3) Wikipedia en español como última fuente
if [ -z "$res" ]; then
    res=$(fetch_wiki "$word")
    src="Wikipedia"
fi

if [ -n "$res" ]; then
    echo "📚 $src:"
    echo "$res"
    exit 0
fi

echo "No se encontró definición para \"$word\"."
exit 0
