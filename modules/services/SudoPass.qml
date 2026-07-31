pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Guarda la contraseña sudo de Hax de forma LOCAL (cifrada, ~/.config/hax/sudo.pass).
// Se usa ÚNICAMENTE para los comandos de paquetes dentro de Hax (install, update,
// remove...). Nunca se muestra ni se envía a ningún sitio.
Singleton {
    id: root

    property string dbPath: Quickshell.dataPath("sudo.pass")
    property string scriptPath: Qt.resolvedUrl("../../scripts/sudopass.py").toString().replace("file://", "")

    // Contraseña cargada en memoria (no se relee de disco a cada comando)
    property string password: ""
    // true si hay contraseña guardada
    property bool hasPassword: false
    // true mientras carga desde disco
    property bool loading: false

    Component.onCompleted: {
        refresh();
    }

    // Recarga la contraseña desde disco
    function refresh() {
        getProcess.command = ["python3", scriptPath, dbPath, "get"];
        getProcess.running = true;
    }

    // Guarda una contraseña nueva (vacía la borra)
    function set(pass) {
        setProcess.command = ["python3", scriptPath, dbPath, "set", pass];
        setProcess.running = true;
    }

    function clear() {
        clearProcess.command = ["python3", scriptPath, dbPath, "clear"];
        clearProcess.running = true;
    }

    // ── Cargar ──
    Process {
        id: getProcess
        stdout: StdioCollector { id: getStdout }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(getStdout.text);
                    root.password = data.password || "";
                    root.hasPassword = root.password.length > 0;
                    root.loading = false;
                    root.passwordChanged();
                } catch (e) {
                    root.password = "";
                    root.hasPassword = false;
                    root.loading = false;
                }
            } else {
                root.password = "";
                root.hasPassword = false;
                root.loading = false;
            }
        }
    }

    // ── Guardar ──
    Process {
        id: setProcess
        stdout: StdioCollector { id: setStdout }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.refresh();
            } else {
                console.warn("SudoPass: Failed to set password:", setStdout.text);
            }
        }
    }

    // ── Borrar ──
    Process {
        id: clearProcess
        stdout: StdioCollector { id: clearStdout }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.refresh();
            } else {
                console.warn("SudoPass: Failed to clear password:", clearStdout.text);
            }
        }
    }
}
