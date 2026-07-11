



# Hax 🎯

**Hax** es un spotlight/launcher modular para shells Wayland basadas en **Ambxst**, construido con Quickshell y Qt QML. Inspirado en Spotlight de macOS, ofrece búsqueda instantánea de aplicaciones, archivos, cálculos inline, acciones rápidas del sistema, terminal integrada, timers, alarmas, instalación de paquetes, clima y mucho más — todo desde una interfaz limpia, rápida y nativa.

> Este repo contiene **Hax + todas sus dependencias** (servicios, theme, config, componentes). También funciona en **forks y shells personalizadas** basadas en Ambxst.

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
  <em>Terminal integrada: ejecuta comandos con / y muestra la salida en vivo</em>
</p>

<p align="center">
 <video src="https://github.com/user-attachments/assets/9b14eecc-a359-438f-9041-73d1e3866318" width="100%" controls></video>
  <br>
  <em>Video: Demostracion de la nueva animacion que tiene el buscador inspirada en el Spotlight del **ipadOS 27**</em>
</p>

<p align="center">
 <video src="https://github.com/user-attachments/assets/2ec3f49d-d599-4b62-a8e6-8ff708fbc6db" width="100%" controls></video>
  <br>
  <em>Video: Demostracion del poder que tiene **Hax** y showcase de funciones implementadas recientemente</em>
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
| 💻 **Terminal integrada** | `/comando` + `Enter` — ejecuta y ve la salida en vivo |
| 🔒 **Lockscreen** | Bloqueo de pantalla integrado |
| 📸 **Screenshot** | Captura de pantalla con un comando |
| 🔄 **Actualizar sistema** | `update` — pacman -Syu |
| 🗑️ **Desinstalar** | `remove paquete` |
| 🌐 **Búsqueda web** | Cualquier texto que no sea comando se busca en Google |
| 📖 **Ayuda integrada** | Escribe `ayuda`, `help` o `?` para ver todos los comandos |

---

## 📦 Requisitos

- Una **shell basada en Ambxst** (Ambxst original, Ax-shell, o cualquier fork)
- [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell) — Motor QML para Wayland
- Qt6 (base, declarative, wayland, svg)
- **Hyprland** u otro compositor Wayland compatible
- Herramientas: `grim`, `slurp`, `jq`, `playerctl`, `wl-clipboard`, `brightnessctl`

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
| ayuda / help / ? | Muestra la ayuda completa |
| /comando | Ejecuta un comando en la terminal integrada |
| 23*4 | Calcula y muestra el resultado inline 

 Atajos de teclado

| Tecla | Acción |
|-------|--------|
| Super + / | Abrir Hax |
| ↑ / ↓ | Navegar resultados / scroll en terminal |
| Enter | Abrir selección / ejecutar |
| Esc | Cerrar / cerrar monitor |


```
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
│   │   └── SpotlightView.qml             # 🧠 Todo Hax (~2274 líneas)
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

**Nota:** A diferencia de otros launchers, Hax es **monolítico** por diseño — todo el código vive en un solo archivo `SpotlightView.qml` (~2274 líneas). Esto evita la fragmentación y hace que sea fácil de mantener y modificar.

> El repo incluye archivos de **soporte** (`config/`, `assets/`, `modules/tools/`, `version`) para que Hax funcione correctamente incluso en shells personalizadas que no tengan estos archivos. Si tu shell ya los tiene, el instalador no los sobrescribe. En total, el repositorio autocontenido tiene **~13.259 líneas** de código entre QML, JS, JSON y scripts.

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
