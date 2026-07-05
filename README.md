# Hax 🎯

**Hax** es un spotlight/launcher modular para el shell Wayland **Ambxst**, construido con Quickshell y Qt QML. Ofrece búsqueda instantánea de aplicaciones, archivos, operaciones aritméticas y comandos del sistema — todo desde una interfaz limpia, rápida y nativa.

## 📸 Galería

<p align="center">
  <img src="screenshots/hax-search-bar.png" alt="Hax — Barra de búsqueda" width="620">
</p>

<p align="center">
  <img src="screenshots/hax-terminal.png" alt="Hax — Terminal integrada" width="620">
  <br>
  <em>Terminal integrada: ejecuta comandos con / y muestra la salida en vivo</em>
</p>

<p align="center">
  <img src="screenshots/hax-results.png" alt="Hax — Resultados de búsqueda" width="620">
  <br>
  <em>Búsqueda de aplicaciones con resultados en tiempo real</em>
</p>

## ✨ Características

- **Búsqueda unificada** — Encuentra apps instaladas, archivos, carpetas y realiza cálculos al instante.
- **Resultados ordenados por uso** — Los elementos que más usas aparecen primero.
- **Autocompletado con Tab** — Navegación rápida por los resultados.
- **Apertura inteligente** — Abre archivos con Thunar/Dolphin directamente desde el launcher.
- **Tema nativo** — Respeta la paleta de colores y estilos de Ambxst.
- **Bajo overhead** — Sin Electron, sin webviews. QML puro sobre Wayland.

## 📦 Requisitos

- [Ambxst](https://github.com/Axenide/Ambxst) — Shell Wayland modular
- [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell) — Motor QML para Wayland
- Qt6 (base, declarative, wayland, svg)
- Hyprland (u otro compositor Wayland compatible)

## 🚀 Instalación

```bash
# Instalación completa (Ambxst + dependencias + Hax)
curl -sSL https://raw.githubusercontent.com/fabiolopezperez-hue/ambxst-Hax/main/hax-install.sh | bash
```

O clona el repositorio y ejecuta el instalador localmente:

```bash
git clone https://github.com/fabiolopezperez-hue/ambxst-Hax.git /tmp/hax
cd /tmp/hax
chmod +x hax-install.sh
./hax-install.sh
```

### Instalación manual

Si ya tienes Ambxst instalado, copia el módulo spotlight:

```bash
cp -r modules/widgets/spotlight ~/.local/src/ambxst/modules/widgets/
```

Y añade este atajo a tu configuración de Hyprland:

```conf
bind = SUPER, slash, exec, qs -p "$HOME/.local/src/ambxst/modules/widgets/spotlight/SpotlightView.qml"
```

## ⌨️ Uso

| Acción | Tecla |
|--------|-------|
| Abrir Hax | `Super + /` |
| Navegar resultados | `↑` / `↓` |
| Autocompletar | `Tab` |
| Abrir selección | `Enter` |
| Cerrar | `Esc` |

## 🧱 Estructura

```
modules/widgets/spotlight/
├── SpotlightView.qml      # Ventana principal del launcher
├── SpotlightResult.qml    # Componente de resultado individual
├── spotlight-apps.qml     # Búsqueda de aplicaciones
├── spotlight-files.qml    # Búsqueda de archivos
├── spotlight-math.qml     # Evaluación aritmética
└── resources/             # Recursos adicionales
```

## 📄 Licencia

Distribuido bajo licencia MIT. Partes del código derivadas de [Ambxst](https://github.com/Axenide/Ambxst).
