



# Hax 🎯

**Hax** es un spotlight/launcher modular para shells Wayland basadas en **Ambxst**, construido con Quickshell y Qt QML. Inspirado en Spotlight de macOS, ofrece búsqueda instantánea de aplicaciones, archivos, cálculos inline, acciones rápidas del sistema, terminal integrada, timers, alarmas, instalación de paquetes, clima y mucho más — todo desde una interfaz limpia, rápida y nativa.

> Este repo contiene **Hax + todas sus dependencias** (servicios, theme, config, componentes, scripts y la fuente Phosphor). Hax es **autocontenido**: se ejecuta directamente con `qs -p modules/widgets/spotlight/SpotlightView.qml`. También funciona inyectado en **forks y shells personalizadas** basadas en Ambxst.

> ⚠️ **`shell.qml` es el entry point de la shell host (Ambxst), no de Hax.** Importa el set completo de módulos de Ambxst (`bar`, `dock`, `notch`, `overview`, `lockscreen`, `shell`…) que **no** se incluyen aquí. Para usar Hax, lanza `SpotlightView.qml` directamente (así lo hace el atajo `Super + /`). `shell.qml` solo se copia si no existe en tu shell y, en ese caso, requiere que Ambxst esté presente.

---

## 📸 Galería

<p align="center">
  <img src="screenshots/hax-search-bar.png" width="620">
</p>

<p align="center">
  <img src="screenshots/hax-terminal.png" width="620"> 
  <br>
  <em>Búsqueda de apps, paquetes, comandos y más</em>
</p>

<p align="center">
 <img src="screenshots/hax-results.png" width="620">
  <br>
  <em>Terminal embebida: escribe / y abre una terminal real (PTY) dentro de Hax</em>
</p>

<p align="center">
 <video src="https://github.com/user-attachments/assets/9b14eecc-a359-438f-9041-73d1e3866318" width="100%" controls></video>
  <br>
  <em>Video: Demostracion de la nueva animacion que tiene el buscador inspirada en el Spotlight del <strong>ipadOS 27</strong></em>
</p>

<p align="center">
 <video src="https://github.com/user-attachments/assets/2ec3f49d-d599-4b62-a8e6-8ff708fbc6db" width="100%" controls></video>
  <br>
  <em>Video: Demostracion del poder que tiene <strong>Hax</strong> y showcase de funciones implementadas recientemente</em>
</p>
---

## ✨ Características

| Característica | Descripción |
|----------------|-------------|
| 🔍 **Búsqueda de apps** | Encuentra apps instaladas con resultados ordenados por uso |
| 📊 **Monitor del sistema** | `stats` — muestra CPU, RAM, disco y temperatura en vivo con barras de progreso |
| 📦 **Buscador de paquetes** | `install firefox` — busca en pacman + AUR (yay) + flatpak a la vez |
| ⏱️ **Timers** | `timer 5m`, `timer pizza 10m`, `timer 30s` — con notificación al terminar |
| 🔔 **Alarmas** | `alarm 8:00`, `alarm 7:30 l-v`, `alarm 14:30 comida` |
| 🌤️ **Clima** | `weather`, `weather Madrid` — pronóstico actual |
| 🧮 **Calculadora inline** | Escribe `23*4` → muestra `= 92` al instante |
| ⚡ **Acciones rápidas** | `lock`, `apagar`, `reiniciar`, `suspender`, `capturar` |
| 💻 **Terminal embebida** | Escribe `/` para abrir una **terminal real (PTY)** dentro de Hax (tu shell por defecto, p. ej. fish) — cierra con `exit` o `Esc` |
| 🔒 **Lockscreen** | Bloqueo de pantalla integrado |
| 📸 **Screenshot** | Captura de pantalla con un comando |
| 🔄 **Actualizar sistema** | `update` — pacman -Syu |
| 🗑️ **Desinstalar** | `remove paquete` |
| 🌐 **Búsqueda web** | Cualquier texto que no sea comando se busca en Google |
| 📖 **Ayuda integrada** | Escribe `ayuda`, `help` o `?` para ver todos los comandos |
| 👁 **Vista rápida (Quick Look)** | 100% teclado: navega con **↑/↓** y los archivos se previsualizan solos dentro de Hax (imágenes renderizadas, texto/binario leído al instante). Cierra con ✕ o **Esc** |
| 🐞 **Modo desarrollador (debug)** | Escribe `d`, `dev` o `debug` → la opción **🐞 Modo desarrollador (debug)** aparece la **primera** en la lista. Pulsa **Enter** (o clic) para abrir un panel **persistente abajo, en el sitio del monitor del sistema**, con errores capturados, tiempos de carga (apertura + última búsqueda + sesión) y consumo de recursos del propio Hax (memoria/CPU). No abre el monitor del sistema. Ciérralo con el botón **✕** o **Esc** |
| 📜 **Historial inteligente** | `historial`, `clip` o `portapapeles` muestra todo lo copiado, ordenado por uso, con borrado individual al hover |
| 📋 **Copiar al portapapeles** | **Enter** copia el resultado, **Shift+Enter** lo ejecuta/abre. También Ctrl+C o el botón ⎘ al hover |
| 🎯 **Autocompletado inline** | Mientras escribes, Hax sugiere en gris el resultado que coincide; acepta con **Tab** / **→** |
| 🔍 **Google Lens** | `scripts/google_lens.sh` sube capturas a Google Lens para búsqueda visual |
| 🖼️ **Live Text (OCR)** | Busca **palabras escritas DENTRO de imágenes** (tipo macOS): escribe `factura` y Hax encuentra la captura que la contiene. Indexa tus imágenes en segundo plano con Tesseract y muestra el texto detectado en la Vista rápida (copiable). Reindexa con `reindexar` |
| 📖 **Glosario / Diccionario** | Escribe `g`, `glo` o `glosario` y pulsa **Enter**: Hax entra en modo diccionario y se queda esperando la palabra. Al escribirla, la **definición aparece en vivo abajo** (es→en, vía Wiktionary). **Enter** copia la definición, **Esc** sale del modo |

---

## 📦 Requisitos

- Una **shell basada en Ambxst** (Ambxst original, Ax-shell, o cualquier fork)
- [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell) — Motor QML para Wayland
- Qt6 (base, declarative, wayland, svg)
- **Hyprland** u otro compositor Wayland compatible
- Herramientas: `grim`, `slurp`, `jq`, `playerctl`, `wl-clipboard`, `brightnessctl`
- **Para la terminal embebida:** el instalador compila e instala [`qmltermwidget`](https://github.com/Swordfish90/qmltermwidget) (plugin QML para Qt6) automáticamente. En instalación manual, instálalo tú mismo.
- **Fuente de iconos Phosphor:** Hax usa la fuente *Phosphor* (`Phosphor-Bold`, etc.) para sus iconos. El instalador la copia automáticamente desde `assets/fonts/` a `~/.local/share/fonts/Hax` y ejecuta `fc-cache`. En instalación manual, instala el paquete `phosphor-icons` (o copia los `.ttf` a tu directorio de fuentes).
- **Para Live Text (OCR):** el instalador instala **Tesseract** + los datos de idioma **inglés y español** (`tesseract-data-eng`, `tesseract-data-spa` en Arch; equivalentes en Debian/Fedora). Sin esto, la búsqueda dentro de imágenes no funciona. Puedes ampliar los idiomas con la variable `HAX_OCR_LANGS` (p. ej. `eng+spa+fra`).

---

## 🚀 Instalación

### 🔹 Ambxst original (automático — recomendado)

```bash
curl -sSL https://raw.githubusercontent.com/fabiolopezperez-hue/ambxst-Hax/main/hax-install.sh | bash
```

> El instalador funciona incluso desde `curl | bash`: detecta que se ejecuta desde un pipe, clona el repo temporalmente y hace la instalación completa. Cuando termina, se limpia solo.

O localmente (te permite elegir rama):

```bash
git clone https://github.com/fabiolopezperez-hue/ambxst-Hax.git
cd ambxst-Hax
chmod +x hax-install.sh
./hax-install.sh
```

**¿Qué hace?**
1. Si no tienes Ambxst instalado, lo instala (binario + fuente desde `Axenide/Ambxst`)
2. Copia Hax y sus dependencias (spotlight, servicios, theme, componentes, tools, config, assets)
3. Configura el atajo `Super + /` en Hyprland (soporta `.lua` y `.conf`)
4. Si ya tenías Ambxst, no sobrescribe tu `shell.qml` ni `Config.qml`

### 🔹 Fork / shell personalizada

```bash
./hax-install.sh -t ~/Repos/mi-shell
```

O con variable de entorno:

```bash
AMBXST_SRC=~/Repos/mi-shell ./hax-install.sh
```

**¿Qué hace?**
- Copia solo los archivos de Hax en tu shell
- **No toca** tu `shell.qml` ni `Config.qml` si ya existen
- **No instala Ambxst** (asume que ya tienes tu propia shell)
- **No necesita** que tu shell sea Ambxst — funciona en cualquier shell con estructura de módulos de Quickshell

### 🔹 Manual

```bash
# Copia Hax y todas sus dependencias
cp -r modules/widgets/spotlight   /ruta/a/tu-shell/modules/widgets/
cp    modules/services/*.qml      /ruta/a/tu-shell/modules/services/
cp    modules/globals/*.qml       /ruta/a/tu-shell/modules/globals/
cp    modules/theme/*.qml         /ruta/a/tu-shell/modules/theme/
cp    modules/components/*.qml    /ruta/a/tu-shell/modules/components/
cp    modules/tools/*.qml         /ruta/a/tu-shell/modules/tools/
cp    config/*.js                 /ruta/a/tu-shell/config/

# Y añade a tu config de Hyprland:

**Formato hyprlang (`.conf`):**
```conf
bind = SUPER, slash, exec, qs -p "/ruta/a/tu-shell/modules/widgets/spotlight/SpotlightView.qml"
```

**Formato Lua (`hyprland.lua`, Hyprland 0.55+):**
```lua
hl.bind("SUPER + Slash", hl.dsp.exec_cmd('qs -p "/ruta/a/tu-shell/modules/widgets/spotlight/SpotlightView.qml"'))
```

> El instalador detecta automáticamente si usas `hyprland.lua` o `hyprland.conf` y configura el atajo en el formato correcto.


---

## ⌨️ Uso

### Comandos principales

 Escribe | Qué hace |
|---------|----------|
| firefox (o cualquier app) | Busca y abre la aplicación |
| install firefox | Busca el paquete en pacman + AUR + flatpak |
| timer 5m | Crea un timer de 5 minutos |
| timer pizza 10m | Timer con nombre "pizza", 10 minutos |
| alarm 8:00 | Alarma a las 8:00 |
| alarm 7:30 l-v | Alarma a las 7:30 de lunes a viernes |
| weather | Clima actual |
| weather Madrid | Clima de Madrid |
| lock / bloquear | Bloquear pantalla |
| apagar / shutdown | Apagar sistema |
| reiniciar / reboot | Reiniciar |
| suspender / suspend | Suspender |
| capturar / screenshot | Capturar pantalla |
| update | Actualizar sistema (pacman -Syu) |
| remove firefox | Desinstalar paquete |
| stats / monitor | Monitor del sistema con CPU, RAM, disco y temperatura en vivo |
| d / dev / debug | Abre el **Modo desarrollador (debug)** — panel con errores, tiempos y recursos de Hax (abajo, donde el monitor) |
| ayuda / help / ? | Muestra la ayuda completa |
| reindexar / ocr | **Live Text:** reindexa todas tus imágenes (vuelve a leer el texto con OCR) |
| / | Abre la **terminal embebida** (PTY real) dentro de Hax |
| 23*4 | Calcula y muestra el resultado inline 

 Atajos de teclado

| Tecla | Acción |
|-------|--------|
| Super + / | Abrir Hax |
| ↑ / ↓ | Navegar resultados / scroll en terminal |
| Tab / → | Aceptar sugerencia de autocompletado |
| Esc | Cerrar / cerrar monitor / cerrar modo debug |
| historial / clip | Muestra el historial de copias |


```
### 👁 Vista rápida (Quick Look)

**Hax es 100% teclado.** Navega con **↑/↓** por los resultados y, al resaltar un **archivo**, Hax lo **previsualiza dentro del propio buscador** automáticamente, sin tocar el ratón. También puedes pulsar **Enter** sobre el archivo para previsualizarlo. (El ratón solo se usa en el Historial para borrar copias antiguas.)

- 🖼️ **Imágenes** (`png`, `jpg`, `gif`, `webp`, `svg`…): se muestran dentro del panel, centradas y con su proporción.
- 📄 **Texto**: se lee el contenido al instante (con `cat`) y se muestra con scroll.
- 🔒 **Binarios**: avisan de que no se pueden previsualizar.

El panel de previsualización aparece en el mismo sitio que el Monitor del sistema (abajo, integrado en el buscador) y se cierra con el botón **✕** o **Esc**.

## 🧱 Estructura del repo


ambxst-Hax/
├── hax-install.sh                        # Instalador automático
├── shell.qml                             # Entry point (Loader de Hax)
├── version                               # Versión de Ambxst
├── README.md
├── config/
│   ├── Config.qml                        # Config central
│   ├── KeybindActions.js                 # Acciones de atajos
│   ├── ConfigValidator.js                # Validación de config
│   └── defaults/
│       ├── ai.js
│       ├── bar.js
│       ├── compositor.js
│       ├── desktop.js
│       ├── dock.js
│       ├── lockscreen.js
│       ├── notch.js
│       ├── overview.js
│       ├── performance.js
│       ├── prefix.js
│       ├── system.js
│       ├── theme.js
│       ├── weather.js
│       └── workspaces.js
├── assets/
│   └── presets/
│       └── Ambxst Default/
│           ├── bar.json
│           ├── compositor.json
│           ├── desktop.json
│           ├── dock.json
│           ├── info.json
│           ├── lockscreen.json
│           ├── notch.json
│           ├── overview.json
│           ├── performance.json
│           ├── system.json
│           ├── theme.json
│           └── workspaces.json
├── modules/
│   ├── widgets/spotlight/
│   │   ├── qmldir                       # Registro del módulo
│   │   └── SpotlightView.qml             # 🧠 Todo Hax (~3265 líneas)
│   ├── services/
│   │   ├── AppSearch.qml                 # Búsqueda de apps
│   │   ├── AxctlService.qml              # Abstracción del compositor
│   │   ├── GlobalShortcuts.qml           # Atajo de teclado
│   │   ├── LockscreenService.qml         # Bloquear pantalla
│   │   ├── Screenshot.qml                # Capturas
│   │   ├── SuspendManager.qml            # Gestión de suspensión
│   │   ├── Visibilities.qml              # Abrir/cerrar Hax
│   │   └── WeatherService.qml            # Clima
│   ├── globals/
│   │   └── GlobalStates.qml              # Estado global transitorio
│   ├── theme/
│   │   ├── Colors.qml                    # Paleta de colores
│   │   ├── Icons.qml                     # Iconos Phosphor
│   │   └── Styling.qml                   # Estilos compartidos
│   ├── components/
│   │   └── StyledRect.qml                # Contenedor base con theming
│   └── tools/
│       ├── MirrorWindow.qml              # Espejo de ventana
│       ├── ScreenrecordTool.qml          # Grabación de pantalla
│       ├── ScreenshotOverlay.qml         # Overlay de captura
│       └── ScreenshotTool.qml            # Captura de pantalla
└── screenshots/
    ├── hax-search-bar.png
    ├── hax-results.png
    ├── hax-terminal.png
    ├── new-animation-Hax.mp4
    └── new-functions-Hax.mp4`
```

**Nota:** A diferencia de otros launchers, Hax es **monolítico** por diseño — todo el código vive en un solo archivo `SpotlightView.qml` (~3265 líneas). Esto evita la fragmentación y hace que sea fácil de mantener y modificar.

> El repo incluye archivos de **soporte** (`config/`, `assets/`, `modules/tools/`, `version`) para que Hax funcione correctamente incluso en shells personalizadas que no tengan estos archivos. Si tu shell ya los tiene, el instalador no los sobrescribe. En total, el repositorio autocontenido tiene **~13.093 líneas** de código entre QML, JS, JSON y scripts.

---

## 🔧 ¿Usas una shell personalizada (fork, custom, etc)?

¡Funciona igual! Solo usa el flag `-t`:

```bash
./hax-install.sh -t /ruta/a/tu-shell
```

**No necesitas tener Ambxst.** Hax se instala en cualquier shell basada en Quickshell que tenga la estructura de módulos (`modules/widgets/`, `modules/services/`, etc.).

El instalador:
- Copia Hax y todas sus dependencias en tu shell
- **No toca** tu `Config.qml` ni `shell.qml` si ya existen
- **No instala Ambxst** — respeta tu shell actual
- **Añade archivos de soporte** (KeybindActions.js, ConfigValidator.js, assets/presets) solo si no los tienes
- Configura el atajo `Super + /` en Hyprland si no existe

---

## 📋 Changelog

### v3.0 — Julio 2026 — 🎉 VERSIÓN ESTABLE

Esta es la **primera versión estable** de Hax. Reúne todas las funciones grandes añadidas durante el ciclo 2.x, las deja pulidas, documentadas y con instalación de un solo comando.

**Lo que se ha añadido (resumen del ciclo 2.x → 3.0):**
- **🖥️ Terminal embebida (PTY real)** — Escribe `/` y abre una terminal completa e interactiva dentro de Hax (tu shell por defecto, p. ej. fish), con `vim`, `htop`, `sudo`, TAB… Cierra con `exit` o `Esc`.
- **🐞 Modo desarrollador (debug)** — Escribe `d` / `dev` / `debug` para ver errores capturados, tiempos de carga y consumo de recursos de Hax, en un panel persistente abajo.
- **🖼️ Live Text (OCR)** — Busca **palabras escritas dentro de tus imágenes** (tipo macOS): indexado en background con Tesseract, resultados 🖼️ con snippet, texto detectable en la Vista rápida (copiable) y `reindexar` para re-escanear. Escribe `live` / `estado` / `ocr` para ver el estado.
- **👁 Vista rápida (Quick Look)** — Previsualiza archivos dentro de Hax (imagen o texto) al navegar con ↑/↓; el texto OCR aparece debajo de las imágenes.
- **📜 Historial inteligente** — Hax guarda todo lo que copias y lo sugiere en cualquier búsqueda; borrado individual al hover.
- **📊 Monitor del sistema** — `stats` / `monitor` con CPU, RAM, disco y temperatura en vivo.
- **🔧 Instalador 100% automático** — `hax-install.sh` instala Quickshell (si falta), compila **qmltermwidget**, instala **Tesseract + datos de idioma (eng/spa)**, copia la **fuente Phosphor** y todo Hax. Un solo `curl | bash` lo deja listo.
- **🧩 Autocontenido y portable** — Repo con todas las dependencias; funciona tanto solo (`qs -p …/SpotlightView.qml`) como inyectado en forks/shells personalizadas (`-t`).

> ✅ **Estado: ESTABLE.** Todo lo anterior está probado de punta a punta y documentado. No se esperan cambios disruptivos.

> 📌 **Política de versiones (a partir de 3.0):**
> - **Correcciones y mejoras pequeñas** → parche: `3.0.1`, `3.0.2`… o `3.x.1` dentro de una minor.
> - **Cambios grandes / nuevas funciones principales** → se harán como antes (p. ej. la `2.1` fue un salto grande), subiendo la versión menor/major (`3.1`, `4.0`…). No habrá saltos disruptivos silenciosos: lo gordo se anunciará claramente.

### v3.0.2 — Julio 2026 — 📖 Glosario reescrito (XMLHttpRequest nativo)

- **♻️ Glosario reescrito desde cero** — El diccionario ahora usa **XMLHttpRequest nativo de QML** en vez de scripts bash+curl+python3. Esto elimina:
  - Procesos huérfanos (cada tecla ya no deja curls colgados)
  - Dependencia de `curl`, `python3` y scripts externos
  - Saturación de la API (solo una petición HTTP a la vez)
  - Problemas de case-sensitivity y comparación de strings
- **⚡ Más rápido y fiable** — Una sola llamada a la API REST de Wikipedia, sin 3 fuentes en cascada. Todas las palabras con artículo en Wikipedia funcionan al instante.
- **🧹 Limpieza al borrar** — Cuando borras la palabra, el resultado se limpia automáticamente y el modo glosario se queda esperando la siguiente palabra.
- **📦 Script `scripts/dict.sh` eliminado de la instalación** — Ya no se necesita.

### v3.0.1 — Julio 2026 — 📖 Glosario / Diccionario

- **📖 Glosario / Diccionario** — Escribe `g`, `glo` o `glosario` y pulsa **Enter**: Hax entra en modo diccionario y **se queda esperando la palabra**. Al escribirla, la **definición aparece en vivo abajo** del buscador (busca en español y hace fallback a inglés vía `dictionaryapi.dev`, sin API key). **Enter** copia la definición al portapapeles; **Esc** sale del modo. Cubre el hueco que dejaba Spotlight de macOS (que no trae diccionario integrado en el launcher).
  - Nuevo script `scripts/dict.sh` (es→en vía Wiktionary, con fallback automático).

### v2.7 — Julio 2026

- **🖼️ Live Text (OCR)** — Busca **texto escrito DENTRO de imágenes**, tipo "Texto en Vivo" de macOS. Al escribir `factura`, Hax encuentra la captura que la contiene aunque el archivo se llame `Screenshot_0142.png`.
  - **Indexado en background** al iniciar Hax: escanea `Documentos`, `Descargas`, `Escritorio`, tu carpeta de `Imágenes`/`Pictures` y `Screenshots`, y lee el texto con **Tesseract** (sin bloquear la UI, con caché por archivo para no re-OCRizar).
  - **Búsqueda:** los resultados por OCR aparecen como 🖼️ con un snippet del texto encontrado.
  - **Vista rápida:** al previsualizar una imagen, Hax muestra el **texto detectado debajo** (copiable con el botón 📋 Copiar).
  - **Reindexar:** escribe `reindexar` (o `ocr`) para volver a leer todas tus imágenes.
  - El instalador añade **Tesseract + datos de idioma (eng/spa)**; ampliable con `HAX_OCR_LANGS`.

### v2.6 — Julio 2026

- **🐞 Modo desarrollador (debug)** — Escribe `d`, `dev` o `debug` y la opción **🐞 Modo desarrollador (debug)** aparece la **primera** en la lista de resultados. Pulsa **Enter** (o clic) para entrar: se abre un panel **persistente abajo, en la misma ubicación que el Monitor del sistema** (no abre el monitor del sistema). Mientras está activo puedes seguir usando el buscador (los resultados se quedan arriba) y ver en vivo:
  - **❌ Errores capturados** de `executeItem`, `openPreview`, `copyResult`, `runCmd` y la terminal embebida.
  - **⏱️ Tiempos**: apertura (open→listo), última búsqueda y sesión abierta.
  - **⚙️ Recursos** del propio Hax: memoria RSS y CPU leídos de `/proc/$PPID` (Quickshell es el padre del proceso).
  - Se cierra con el botón **✕** del panel o con **Esc** (si no hay texto escrito).
- **🪟 Tamaño de ventana corregido en modo debug** — `fullHeight` ahora suma resultados **+** panel de debug, así el panel de debug (abajo) nunca queda recortado fuera de pantalla.
- **🐛 Lectura de recursos del debug corregida** — Se eliminó una señal inexistente (`onError`) que dejaba memoria/CPU en blanco; ahora se actualizan correctamente.

### v2.5 — Julio 2026

- **🖥️ Terminal embebida (PTY real)** — Escribe `/` en el buscador para abrir una **terminal real** dentro de Hax (emulador PTY con `qmltermwidget`, usando tu shell por defecto como fish). Cierra con `exit` o `Esc`. Ya no es un `runCmd` que solo mostraba salida: ahora es interactiva y completa.
- **⌨️ Hax 100% teclado** — La vista rápida (Quick Look) se activa al **navegar con ↑/↓** por los resultados, sin tocar el ratón (el ratón solo se usa para borrar copias en el Historial).
- **🐟 Alias del shell en comandos** — `runCmd` ahora ejecuta con `$SHELL -i -c`, así que respeta tus alias (p. ej. `ls` → `eza` en fish).
- **🔧 Instalador: qmltermwidget automático** — `hax-install.sh` compila e instala el plugin `qmltermwidget` (Qt6) de forma idempotente, para que la terminal embebida funcione en un clone limpio sin pasos manuales.

### v2.4 — Julio 2026

- **👁 Vista rápida (Quick Look)** — Pasa el ratón o pulsa **Enter** sobre un archivo para previsualizarlo **dentro de Hax** (sin abrir nada externo). Imágenes renderizadas en el panel (centradas y con su proporción), texto leído al instante con `cat` y binarios marcados como no previsualizables. El panel se abre integrado en el buscador, en la misma posición que el Monitor del sistema, y se cierra con ✕ o **Esc**.
- **🐛 Posición de la previsualización corregida** — El panel de Quick Look se renderizaba en la esquina superior izquierda de la ventana porque estaba fuera del flujo de layout (`contentColumn`). Ahora vive dentro de `contentColumn`, igual que el Monitor, así que aparece siempre en su sitio.
- **🖼️ Imágenes sin escapes** — Se usa `layer.enabled` en el `Image` para evitar el bug de Quickshell que dibujaba las texturas `file://` en `(0,0)` de la ventana.

### v2.3 — Julio 2026

- **🧠 Historial inteligente** — Hax vigila el portapapeles y guarda TODO lo que copias (de webs, archivos, apps...) en `~/.local/share/hax/history.json`. Escribe `historial`, `clip` o `portapapeles` para verlo. Cada item tiene un botón **✕** al hover para borrarlo. Los items más usados salen primero (aprende de tu uso).
- **📋 Copiar al portapapeles** — **Enter** copia el resultado seleccionado, **Shift+Enter** lo ejecuta/abre. También Ctrl+C o el botón **⎘** al hover. Apps → nombre, archivos → ruta (imágenes → la imagen), calculadora → resultado.
- **🎯 Autocompletado inline** — Mientras escribes, Hax te sugiere en gris el nombre del resultado que coincide con lo que escribes. Acepta con **Tab** o **→**. Escanea **todos los resultados** (apps, archivos, webs...), no solo el primero. Así `virt` → sugiere `ualBox` aunque VirtualBox no sea el primer resultado.
- **🐛 RAM stats corregido** — Mostraba valores incorrectos; ahora divide entre 1048576 (bytes → MB) en vez de 1024
- **🌡️ Temperatura corregida** — Ya no se queda pillada en 20°C (sensor `acpitz`). Ahora lee `k10temp`/`coretemp`/`cpu_thermal` desde `/sys/class/hwmon/` para CPUs AMD/Intel
- **📜 Google Lens** — Nuevo script `scripts/google_lens.sh` para subir capturas a Google Lens y buscarlas
- **🌤️ Clima vía Open-Meteo** — Nuevo script `scripts/weather.sh` usando Open-Meteo API (sin API key, gratuita)
- **🔧 Instalador mejorado** — `hax-install.sh` ahora copia también los `scripts/*.sh` al destino
- **💡 Ideas trackeadas** — Archivo `ideas/notas-hax` con ideas anotadas para futuras mejoras (plugins, snippets, historial, debug mode, traducciones, etc.)

### v2.2 — Julio 2026

- **📦 Repositorio auto-contenido** — Añadidos archivos faltantes para que Hax funcione al clonar desde GitHub sin necesidad de tener Ambxst pre-instalado
- **🐛 Instalador arreglado** — `hax-install.sh` ahora clona el Ambxst original (`Axenide/Ambxst`) en vez de clonarse a sí mismo
- **➕ Archivos de soporte** — Añadidos `config/KeybindActions.js`, `config/ConfigValidator.js`, `version`, `modules/tools/*.qml` y `assets/presets/Ambxst Default/*.json` como fallback para shells personalizadas
- **🔧 Compatible con cualquier shell** — Hax se instala en forks y shells custom con `-t`, sin necesidad de Ambxst
- **📜 Soporte para hyprland.lua** — El instalador detecta automáticamente si usas el nuevo formato Lua (Hyprland 0.55+) y configura el atajo `Super + /` en la sintaxis correcta
- **📖 README actualizado** — Instrucciones claras para Ambxst original, shells personalizadas y ambos formatos de Hyprland

### v2.1 — Julio 2026

- **📊 Monitor del sistema** — `stats` / `monitor` abre un panel con CPU, RAM, disco y temperatura en vivo, con barras de progreso coloreadas (verde/amarillo/rojo) que se actualizan cada 2 segundos
- **🔁 Scroll con flechas** — Navegación por resultados y scroll en terminal con ↑↓, scroll en terminal con la rueda del ratón
- **🖥️ Terminal integrada estable** — Animación de altura desactivada durante procesos, altura mínima de 240px, `.slice()` para que QML detecte cambios en el array de salida
- **⬆️⬇️ Scroll en terminal** — Flechas arriba/abajo hacen scroll cuando la terminal está activa

### v2.0 — Julio 2026

- **🎯 Comando `ayuda`** — Escribe `ayuda`, `help` o `?` para ver el manual completo de comandos
- **⏱️ Timers y Alarmas** — `timer 5m`, `alarm 8:00`, notificaciones inline, auto-apertura al completarse
- **📦 Buscador de paquetes** — `install firefox` busca en pacman + AUR + flatpak y deja elegir
- **🧹 Apps sin duplicados** — Deduplicación por ID en resultados de búsqueda
- **🔄 Procesos estables** — Timeouts de 15-20s, SplitParser, sin cuelgues
- **🚫 Sin reinicios espurios** — `_lastSearchQuery` evita reinicios de búsqueda
- **🖥️ Terminal integrada mejorada** — Hax se queda abierto al instalar paquetes
- **📦 Repositorio completo** — Este repo incluye todas las dependencias, no solo el spotlight

### v1.0

- Búsqueda unificada de apps, archivos y cálculos inline
- Acciones rápidas del sistema (bloquear, apagar, reiniciar, suspender, capturar)
- Terminal integrada con `/comando`
- Tema nativo Ambxst
- Resultados ordenados por uso

---

## 📄 Licencia

Distribuido bajo licencia MIT. Partes del código derivadas de [Ambxst](https://github.com/Axenide/Ambxst).

---


</p>
