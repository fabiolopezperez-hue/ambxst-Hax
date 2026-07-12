import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import QMLTermWidget 2.0

// ─── Hax — El buscador de Axenide ──────────────────────────────────────────
// Spotlight nativo para Ambxst + Ax-shell.
// Busca apps, calcula, encuentra archivos y navega por la web.
// Hecho con amor por Fabio y Maria 💖
// ─────────────────────────────────────────────────────────────────────────────

PanelWindow {
    id: spotlight

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:spotlight"
    WlrLayershell.keyboardFocus: spotlightOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── Visibilidad ──────────────────────────────────────────────────────────
    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool spotlightOpen: screenVisibilities ? screenVisibilities.spotlight : false

    // ── Animación notch→centro (puntito que se desprende del bar) ────────────
    property bool showHax: false
    property real animProgress: 0.0       // 0 = puntito en bar, 1 = Hax centrado

    // Posición Y del borde inferior del bar (de donde se desprende el puntito)
    property real barBottom: 40
    readonly property real screenCenterY: spotlight.height / 2

    visible: showHax
    exclusionMode: ExclusionMode.Ignore

    // Disparar animación al abrir/cerrar
    onSpotlightOpenChanged: {
        if (spotlightOpen) {
            closeAnim.stop();

            // Capturar la posición real del bar antes de animar
            var bar = Visibilities.getBarForScreen(screen.name);
            barBottom = bar ? bar.totalBarHeight : 40;

            // Limpiar todo ANTES de mostrar la ventana (evita race con Behavior on height)
            results = [];
            cmdOutput = [];
            cmdOutputText = "";
            _forceTerminal = false;
            _lastCmdVisible = false;
            searchText = "";
            selectedIndex = 0;
            cancelCmdProcess();
            stopMonitor();
            loadHistory();
            startClipWatcher();
            if (weatherSearch) weatherSearch.destroy();
            weatherSearch = null;

            // ⭐ Poner el estado inicial (gota ya formada en el notch)
            // ANTES de mostrar la ventana — así la entrada empieza igual
            // que termina la salida: con la gota justo en el notch
            animProgress = 0.03;
            showHax = true;

            openAnim.start();
            searchInput.clear();
            searchInput.forceActiveFocus();

            // ── Debug: marcar inicio de apertura ──
            _debugOpenStart = Date.now();
            debugOpenMs = -1;
            _debugOpenTimer.restart();
        } else {
            openAnim.stop();
            stopMonitor();
            stopClipWatcher();
            showPreview = false;
            closeAnim.start();
        }
    }

    SequentialAnimation {
        id: openAnim
        PropertyAnimation {
            target: spotlight
            property: "animProgress"
            to: 1.0
            duration: 600
            easing.type: Easing.InOutCubic
        }
    }

    SequentialAnimation {
        id: closeAnim
        PropertyAnimation {
            target: spotlight
            property: "animProgress"
            to: 0.0
            duration: 600
            easing.type: Easing.InOutCubic
        }
        PropertyAction {
            target: spotlight
            property: "showHax"
            value: false
        }
    }

    // ── Input mask ───────────────────────────────────────────────────────────
    mask: Region {
        item: showHax ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    // ── Focus grab ──────────────────────────────────────────────────────────
    FocusGrab {
        id: focusGrab
        windows: [spotlight]
        active: spotlightOpen

        onCleared: {
            Qt.callLater(() => {
                if (spotlightOpen) {
                    Visibilities.setActiveModule("");
                }
            });
        }
    }

    // ── Backdrop invisible (solo para cerrar al hacer clic fuera) ─────────
    MouseArea {
        anchors.fill: parent
        enabled: spotlightOpen
        onClicked: Visibilities.setActiveModule("")
    }

    // ── Estados internos ───────────────────────────────────────────────────
    property string searchText: ""

    // ── Live Text (OCR) — buscar texto DENTRO de imágenes ──────────────────
    property string ocrScript: Qt.resolvedUrl("../../../scripts/ocr.sh").toString().replace("file://", "")
    property string ocrSep: String.fromCharCode(31)
    property string previewOcrText: ""
    property int liveTextIndexed: 0
    property bool liveTextIndexing: false
    property int liveTextPending: 0

    Timer {
        id: liveTextStatusTimer
        interval: 4000
        running: true
        repeat: true
        onTriggered: spotlight.refreshLiveTextStatus()
    }

    Component.onCompleted: {
        // Indexar imágenes en segundo plano al iniciar Hax (Live Text).
        spotlight.startOcrIndexing();
        spotlight.refreshLiveTextStatus();
    }

    // ── Modo desarrollador (debug) ──────────────────────────────────────────
    // Se activa escribiendo "d" / "dev" / "debug" y pulsando Enter.
    property bool showDebug: false
    onShowDebugChanged: {
        try {
            var _df = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
            _df.command = ["bash", "-c", "echo " + (showDebug ? "ON" : "OFF") + " > /tmp/hax-debug-state 2>/dev/null"];
            _df.onExited.connect(function() { try { _df.destroy(); } catch (e) {} });
            _df.running = true;
        } catch (e) {}
    }
    property var debugErrorLog: []
    property int debugOpenMs: -1
    property int debugLastSearchMs: -1
    property int debugSessionS: 0
    property real debugMemMB: 0
    property real debugCpuPct: 0
    property int _debugOpenStart: 0
    property int _debugPrevUtime: -1
    property int _debugPrevStime: -1
    property int _debugPrevTs: 0

    function debugLogError(ctx, e) {
        var msg = (e && e.message) ? e.message : String(e);
        debugErrorLog.push({ t: Qt.formatTime(new Date(), "hh:mm:ss"), ctx: ctx, msg: msg });
        debugErrorLog = debugErrorLog.slice(-50);
    }
    property int selectedIndex: 0
    property bool showTerminal: false

    // Seguir la selección en la lista de resultados (scroll automático)
    onSelectedIndexChanged: {
        if (resultsList && selectedIndex >= 0) {
            resultsList.positionViewAtIndex(selectedIndex, ListView.Center);
        }
    }
    property var results: []
    property string autoCompleteSuffix: {
        if (searchInput && searchInput.text.length > 0 && results.length > 0) {
            var txt = searchInput.text.toLowerCase();
            for (var i = 0; i < results.length; i++) {
                var name = results[i].name || "";
                if (name.toLowerCase().indexOf(txt) === 0 && name.length > txt.length) {
                    return name.substring(txt.length);
                }
            }
        }
        return "";
    }
    property int searchGeneration: 0  // evita race conditions en async
    property string _lastSearchQuery: "" // última búsqueda de paquetes

    // ── Terminal integrada ─────────────────────────────────────────────────
    property var cmdProcess: null      // proceso de comando activo
    property var cmdOutput: []         // líneas de salida capturadas
    property string cmdOutputText: ""  // salida como texto plano (forza bindings en QML)
    property bool _lastCmdVisible: false  // mantiene terminal visible tras finalizar
    property bool _forceTerminal: false   // fuerza terminal visible durante/después de runCmd
    readonly property bool isCommandMode: searchText.trim().startsWith("/")

    // ── Clima ───────────────────────────────────────────────────────────────
    property var weatherSearch: null   // proceso de búsqueda de clima activo

    // ── Paquetes ─────────────────────────────────────────────────────────────
    property var _pkgSearchProcesses: [] // procesos de búsqueda de paquetes activos

    // ── Monitor del sistema ───────────────────────────────────────────────
    property bool showMonitor: false
    property real monCpu: 0
    property real monRamPct: 0
    property real monRamUsed: 0
    property real monRamTotal: 0
    property real monDisk: 0
    property int monTemp: 0
    property int monProcs: 0
    property string monUptime: ""
    property var monProcess: null

    function startMonitor() {
        if (monProcess) return; // ya corriendo
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        proc.command = ["bash", "-c",
            "while true; do "
            + "cpu=$(LC_ALL=C top -bn1 2>/dev/null | awk '/%Cpu/{print 100 - $8}'); "
            + "ram=$(LC_ALL=C free 2>/dev/null | awk 'NR==2{printf \"%d %d\", $3, $2}'); "
            + "disk=$(df / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%'); "
            + "temp=$(cat $(grep -l 'k10temp\\|coretemp\\|cpu_thermal' /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 | sed 's/name$/temp1_input/') 2>/dev/null | awk '{printf \"%.0f\", $1/1000}'); temp=${temp:-0}; "
            + "procs=$(ps aux 2>/dev/null | wc -l); "
            + "uptime=$(LC_ALL=C uptime -p 2>/dev/null); "
            + "echo '{\"cpu\":'$cpu',\"ram_used\":'$(echo $ram | cut -d' ' -f1)',\"ram_total\":'$(echo $ram | cut -d' ' -f2)',\"disk\":'$disk',\"temp\":'$temp',\"procs\":'$procs',\"uptime\":\"'$uptime'\"}'; "
            + "sleep 2; "
            + "done"
        ];
        proc.stdout.onRead.connect(function(data) {
            try {
                var j = JSON.parse(data.trim());
                if (j.cpu !== undefined) monCpu = parseFloat(j.cpu) || 0;
                if (j.ram_used !== undefined && j.ram_total !== undefined) {
                    monRamUsed = parseInt(j.ram_used) || 0;
                    monRamTotal = parseInt(j.ram_total) || 1;
                    monRamPct = monRamTotal > 0 ? (monRamUsed / monRamTotal * 100) : 0;
                }
                if (j.disk !== undefined) monDisk = parseFloat(j.disk) || 0;
                if (j.temp !== undefined) monTemp = parseInt(j.temp) || 0;
                if (j.procs !== undefined) monProcs = parseInt(j.procs) || 0;
                if (j.uptime !== undefined) monUptime = j.uptime || "";
            } catch(e) {}
        });
        proc.onExited.connect(function() {
            proc.destroy();
            monProcess = null;
        });
        monProcess = proc;
        proc.running = true;
    }

    function stopMonitor() {
        showMonitor = false;
        if (monProcess) {
            monProcess.running = false;
            monProcess.destroy();
            monProcess = null;
        }
    }

    function toggleMonitor() {
        if (showMonitor) {
            stopMonitor();
        } else {
            showMonitor = true;
            startMonitor();
        }
    }
    property var activeTimers: []      // [{id, label, totalSeconds, endTime, createdAt}]
    property int _timerNextId: 1
    property var activeAlarms: []      // [{id, label, hour, minute, days, enabled, lastTriggered}]
    property int _alarmNextId: 1

    // Notificaciones inline de Hax (timers, alarmas)
    property var _haxNotifications: [] // [{id, type, label, body, ts, icon, notifObj}]
    property int _haxNotifIdCounter: 0

    // Tick de 1 segundo para timers y alarmas
    Timer {
        id: _tickTimer
        interval: 1000
        repeat: true
        running: activeTimers.length > 0 || activeAlarms.length > 0
        onTriggered: {
            tickTimers();
            checkAlarms();
        }
    }

    // ── Timers del modo debug (apertura + recursos) ─────────────────────────
    Timer {
        id: _debugOpenTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (spotlight.debugOpenMs < 0)
                spotlight.debugOpenMs = Date.now() - spotlight._debugOpenStart;
        }
    }

    Timer {
        id: _debugResTimer
        interval: 1000
        repeat: true
        running: spotlight.showDebug
        onRunningChanged: {
            if (running) {
                spotlight._debugPrevUtime = -1;
                spotlight._debugPrevStime = -1;
                spotlight._debugPrevTs = 0;
            }
        }
        onTriggered: {
            spotlight.debugSessionS = Math.round((Date.now() - spotlight._debugOpenStart) / 1000);
            var proc;
            try {
                proc = Qt.createQmlObject(
                    'import Quickshell.Io; Process { stdout: SplitParser {} }',
                    spotlight
                );
            } catch (e) {
                return;
            }
            proc.stdout.onRead.connect(function(d) {
                var parts = d.trim().split(/\s+/);
                if (parts.length >= 3) {
                    var rssPages = parseInt(parts[0], 10) || 0;
                    var utime = parseInt(parts[1], 10) || 0;
                    var stime = parseInt(parts[2], 10) || 0;
                    spotlight.debugMemMB = (rssPages * 4096) / (1024 * 1024);
                    var now = Date.now();
                    var dTms = now - spotlight._debugPrevTs;
                    if (spotlight._debugPrevUtime >= 0 && dTms > 0 && dTms < 3000) {
                        var dCpu = (utime - spotlight._debugPrevUtime) + (stime - spotlight._debugPrevStime);
                        var dT = dTms / 1000 * 100;
                        spotlight.debugCpuPct = Math.max(0, Math.min(100, (dCpu / dT) * 100));
                    }
                    spotlight._debugPrevUtime = utime;
                    spotlight._debugPrevStime = stime;
                    spotlight._debugPrevTs = now;
                }
                proc.destroy();
            });
            proc.onExited.connect(function() { try { proc.destroy(); } catch (e) {} });
            // $PPID es el PID de Quickshell (padre del proceso lanzado por Process)
            proc.command = ["bash", "-c",
                "P=$(awk '{print $2}' /proc/$PPID/statm 2>/dev/null); " +
                "C=$(awk '{print $14+$15}' /proc/$PPID/stat 2>/dev/null); " +
                "echo \"$P $C\""];
            proc.running = true;
        }
    }

    // ── Puntito que baja del notch y se TRANSFORMA en Hax ─────────────────
    //
    // Una sola cosa que muta: empieza como círculo de 20px en el notch,
    // baja al centro mientras crece y se transforma en el buscador completo.
    // No hay máscaras ni fade entre dos elementos — es el mismo elemento
    // que va cambiando de forma.

    StyledRect {
        id: morphContainer
        variant: "bg"
        anchors.horizontalCenter: parent.horizontalCenter

        // ⚠️ Desactivamos animateRadius porque StyledRect tiene su propio
        // Behavior on radius que PELEA con nuestra animación basada en animProgress
        animateRadius: false

        // ⭕ Círculo — el bar crea un círculo en su borde inferior, que cae
        // y se transforma en el buscador
        //
        // - animProgress 0→0.03: el círculo nace y crece (0→20px) en el bar
        // - animProgress 0.03→0.08: el círculo se desprende y empieza a bajar
        // - animProgress 0.08→0.15: el círculo desciende
        // - animProgress 0.15→1.0: el círculo se expande y transforma en Hax
        readonly property real phase: animProgress

        // Tamaño del círculo: aparece de 0, crece a 20×20,
        // luego se desprende del bar y desciende
        readonly property real dropletW: {
            if (phase < 0.03) return (phase / 0.03) * 20;
            return 20;
        }
        readonly property real dropletH: {
            if (phase < 0.03) return (phase / 0.03) * 20;
            return 20;
        }
        // El descenso empieza cuando la gota se desprende (3%)
        readonly property real descendPhase: Math.max(0, (phase - 0.03) / 0.97)

        // Expansión a Hax completo (igual que antes)
        readonly property real expandPhase: Math.max(0, (phase - 0.15) / 0.85)

        // 📐 Tamaño: gota → círculo → Hax completo
        width: Math.max(1, dropletW + (clampWidth() - dropletW) * expandPhase)
        height: Math.max(1, dropletH + (fullHeight - dropletH) * expandPhase)

        // Suaviza los cambios de altura cuando el Hax ya está abierto
        // (sin interferir con la animación de apertura/cierre)
        // Se desactiva durante un comando para evitar congelar con animaciones
        Behavior on height {
            enabled: Config.animDuration > 0 && animProgress >= 1 && cmdProcess === null
            NumberAnimation {
                duration: Config.animDuration * 3
                easing.type: Easing.OutQuint
            }
        }

        // 💧 Sin fade — la gota aparece/desaparece solo por su tamaño (0→28px)
        opacity: 1

        // 📍 Y: la gota nace pegada al bar y luego cae
        y: barBottom + (screenCenterY - height / 2 - barBottom) * descendPhase

        // 🎭 Radio: de círculo perfecto a esquinas normales
        radius: Math.min(width / 2, Styling.radius(24) + (width / 2 - Styling.radius(24)) * Math.max(0, 1 - expandPhase * 3))

        function clampWidth()  { return Math.min(620, screen.width * 0.9) }

        // ── Altura total dinámica del Hax (depende de resultados) ──────────
        readonly property real fullHeight: 56 + 32
            + (cmdProcess !== null || isCommandMode || _lastCmdVisible || _forceTerminal
                ? cmdProcess !== null
                    ? 8 + Math.max(240, 36 + Math.min(cmdOutput.length * 20 + 20, 460))
                    : 8 + 36 + Math.min(cmdOutput.length * 20 + 20, 460)
                : 0)
            + (_haxNotifications.length > 0
                ? 8 + Math.min(_haxNotifications.length * 56 + 16, 200)
                : 0)
            + (results.length > 0 && !isCommandMode
                ? 8 + Math.min(results.length * 54, 400)
                : 0)
            + (showMonitor
                ? 8 + 260
                : 0)
            + (showPreview
                ? 8 + 300
                : 0)
            + (spotlight.showTerminal
                ? 8 + 392
                : 0)
            + (spotlight.showDebug
                ? 8 + debugPane.height
                : 0)

        // ── Contenido que aparece dentro mientras se transforma ────────────
        Column {
            id: contentColumn
            width: parent.width
            // Aparece durante la expansión (no durante la bajada del punto)
            opacity: Math.max(0, Math.min(1, expandPhase * 2 - 0.5))
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            spacing: (results.length > 0 || cmdProcess !== null || isCommandMode || _lastCmdVisible || _forceTerminal || _haxNotifications.length > 0 || showMonitor || spotlight.showDebug) ? 8 : 0

                // ── Campo de búsqueda ──────────────────────────────────────────
                StyledRect {
                    id: searchBox
                    width: contentColumn.width
                    height: 56
                    variant: "common"
                    radius: Styling.radius(16)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // Icono de lupa
                        Text {
                            text: Icons.apps
                            font.family: Icons.font
                            font.pixelSize: 22
                            color: Styling.srItem("overprimary")
                            opacity: 0.7
                        }

                        // Input
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter

                            font.pixelSize: Config.theme.fontSize + 2
                            font.family: Config.theme.font
                            color: Styling.srItem("text")

                            selectByMouse: true
                            cursorVisible: true

                            // Placeholder
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 2
                                text: cmdProcess !== null
                                    ? qsTr("Ejecutando comando...  (Esc para salir)")
                                    : qsTr("Hax — Buscar apps, archivos, calcular...")
                                font: parent.font
                                color: Styling.srItem("text")
                                opacity: 0.35
                                visible: parent.text.length === 0
                            }

                            // Sugerencia de autocompletado (en gris, al lado del texto escrito)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.cursorRectangle.x + 1
                                text: autoCompleteSuffix
                                font: parent.font
                                color: Styling.srItem("text")
                                opacity: 0.3
                                visible: autoCompleteSuffix.length > 0 && parent.activeFocus
                                z: -1
                            }

                            onTextChanged: {
                                if (text === "/") {
                                    // "/" abre la terminal integrada (embebida, 100% operativa)
                                    spotlight.openTerminal();
                                    searchInput.text = "";
                                    return;
                                }
                                spotlight.searchText = text;
                                spotlight.selectedIndex = 0;
                                // Cancelar proceso al salir del modo comando
                                if (!text.trim().startsWith("/")) {
                                    spotlight.cancelCmdProcess();
                                }
                                var _t0 = Date.now();
                                spotlight.updateResults();
                                spotlight.debugLastSearchMs = Date.now() - _t0;
                            }

                            Keys.onEscapePressed: {
                                if (spotlight.showMonitor) {
                                    spotlight.stopMonitor();
                                } else if (spotlight.showPreview) {
                                    spotlight.showPreview = false;
                                } else if (spotlight.showTerminal) {
                                    spotlight.closeTerminal();
                } else if (spotlight.showDebug) {
                    spotlight.showDebug = false;
                } else if (text.length > 0) {
                    clear();
                } else {
                    Visibilities.setActiveModule("");
                }
                            }

                            Keys.onUpPressed: {
                                if (cmdProcess !== null || _lastCmdVisible || _forceTerminal) {
                                    // Scroll terminal
                                    var ts = 60;
                                    cmdFlickable.contentY = Math.max(0, cmdFlickable.contentY - ts);
                                } else {
                                    if (spotlight.selectedIndex > 0) {
                                        spotlight.selectedIndex--;
                                        if (resultsList) {
                                            resultsList.positionViewAtIndex(spotlight.selectedIndex, ListView.Center);
                                        }
                                        // Navegación por teclado → previsualiza el archivo (Quick Look)
                                        spotlight._previewSelectedIfFile();
                                    }
                                }
                            }

                            Keys.onDownPressed: {
                                if (cmdProcess !== null || _lastCmdVisible || _forceTerminal) {
                                    // Scroll terminal
                                    var ts = 60;
                                    cmdFlickable.contentY = Math.min(
                                        Math.max(0, cmdFlickable.contentHeight - cmdFlickable.height),
                                        cmdFlickable.contentY + ts
                                    );
                                } else {
                                    if (spotlight.selectedIndex < spotlight.results.length - 1) {
                                        spotlight.selectedIndex++;
                                        if (resultsList) {
                                            resultsList.positionViewAtIndex(spotlight.selectedIndex, ListView.Center);
                                        }
                                        // Navegación por teclado → previsualiza el archivo (Quick Look)
                                        spotlight._previewSelectedIfFile();
                                    }
                                }
                            }

                            // Enter, Tab, flecha derecha, Ctrl+C, Esc
                            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (spotlight.isCommandMode && text.trim().length > 1) {
                                        spotlight.runCmd(text.trim().substring(1));
                                    } else if (event.modifiers & Qt.ShiftModifier) {
                                        spotlight.executeSelected();
                                    } else {
                                        // Enter → apps/archivos/web/monitor se ABREN (ejecutan);
                                        // calc e historial se COPIAN al portapapeles
                                        if (spotlight.selectedIndex >= 0 && spotlight.selectedIndex < spotlight.results.length) {
                                            var sel = spotlight.results[spotlight.selectedIndex];
                                            if (sel.type === "calc" || sel.type === "history") {
                                                spotlight.copyResult(sel);
                                            } else if (sel.type === "file") {
                                                spotlight.openPreview(sel);
                                            } else if (sel.exec) {
                                                spotlight.executeItem(sel);
                                            }
                                            // info sin exec → no hacer nada
                                        }
                                    }
                                    event.accepted = true;
                                } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Right)
                                    && autoCompleteSuffix.length > 0
                                    && cursorPosition === text.length) {
                                    // Aceptar sugerencia
                                    searchInput.text = text + autoCompleteSuffix;
                                    searchInput.cursorPosition = searchInput.text.length;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                                    // Ctrl+C → copiar resultado seleccionado
                                    if (selectedIndex >= 0 && selectedIndex < results.length) {
                                        copyResult(results[selectedIndex]);
                                    }
                                    event.accepted = true;
                                }
                            }
                        }

                        // Feedback de "Copiado"
                        Text {
                            visible: _copyFeedback.length > 0
                            text: "✓ Copiado"
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize - 2
                            color: "#4ade80"
                            font.bold: true
                            opacity: _copyFeedbackTimer.running ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Timer para ocultar el feedback
                        Timer {
                            id: _copyFeedbackTimer
                            interval: 1500
                            onTriggered: spotlight._copyFeedback = ""
                        }

                        // Contador de resultados
                        Text {
                            text: results.length > 0 ? `${selectedIndex + 1}/${results.length}` : ""
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("overprimary")
                            opacity: 0.6
                            visible: results.length > 0
                        }
                    }
                }


                // ── Terminal embebida (100% operativa) — se abre con "/" ───────
                StyledRect {
                    id: termPane
                    width: contentColumn.width
                    height: spotlight.showTerminal ? 392 : 0
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    visible: spotlight.showTerminal
                    opacity: spotlight.showTerminal ? 1 : 0
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: Config.animDuration * 2 }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Cabecera coherente con el resto de Hax
                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: ">_"
                                font.family: "monospace"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("overprimary")
                                opacity: 0.7
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Terminal — fish"
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                                opacity: 0.6
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "✕"
                                font.pixelSize: Config.theme.fontSize + 2
                                font.bold: true
                                color: Styling.srItem("text")
                                opacity: 0.5
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: spotlight.closeTerminal()
                                }
                            }
                        }

                        // Terminal embebido (QWidget real dentro de QML)
                        Loader {
                            id: termLoader
                            width: parent.width
                            height: 330
                            active: spotlight.showTerminal
                            clip: true
                            sourceComponent: termComponent
                        }
                    }
                }

                Component {
                    id: termComponent
                    QMLTermWidget {
                        id: termEmbed
                        anchors.fill: parent
                        font.family: "Monospace"
                        font.pointSize: 12
                        colorScheme: "Linux"
                        session: QMLTermSession {
                            id: termSession
                            shellProgram: Quickshell.env("SHELL") || "/bin/bash"
                            initialWorkingDirectory: Quickshell.env("HOME") || "/tmp"
                            onFinished: spotlight.closeTerminal()
                        }
                        Component.onCompleted: {
                            try {
                                termSession.startShellProgram();
                                termEmbed.forceActiveFocus();
                            } catch (e) {
                                spotlight.debugLogError("terminal", e);
                            }
                        }
                    }
                }

                // ── Terminal integrada (modo comando /) ─────────────────────────
                StyledRect {
                    id: cmdContainer
                    width: contentColumn.width
                    height: isCommandMode || cmdProcess !== null || _lastCmdVisible || _forceTerminal
                        ? cmdProcess !== null
                            ? Math.max(240, 36 + Math.min(cmdOutput.length * 20 + 20, 460))
                            : 36 + Math.min(cmdOutput.length * 20 + 20, 460)
                        : 0
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    opacity: (cmdProcess !== null || isCommandMode || _lastCmdVisible || _forceTerminal) ? 1 : 0
                    visible: opacity > 0

                    Behavior on height {
                        enabled: Config.animDuration > 0 && cmdProcess === null
                        NumberAnimation {
                            duration: Config.animDuration * 3
                            easing.type: Easing.OutQuint
                        }
                    }
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration * 2
                            easing.type: Easing.OutQuint
                        }
                    }

                    Column {
                        width: parent.width
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6

                        // Header
                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: ">_"
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                font.bold: true
                                color: Styling.srItem("overprimary")
                                opacity: 0.7
                            }

                            Text {
                                Layout.fillWidth: true
                                text: cmdProcess !== null
                                    ? "$ " + searchText.trim().substring(1)
                                    : "$ " + (searchText.trim().length > 1
                                        ? searchText.trim().substring(1)
                                        : "escribe un comando...")
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                                opacity: 0.6
                                elide: Text.ElideRight
                            }

                            // Indicador de ejecución
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                visible: cmdProcess !== null
                                color: Colors.primary || "#00ff88"
                                opacity: 0.8

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 600 }
                                    NumberAnimation { to: 0.8; duration: 600 }
                                }
                            }

                            // Botón ✕ para cerrar terminal
                            Text {
                                text: "✕"
                                font.pixelSize: Config.theme.fontSize + 2
                                font.bold: true
                                color: Styling.srItem("text")
                                opacity: 0.5

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        spotlight._lastCmdVisible = false;
                                        spotlight.cmdOutput = [];
                                        spotlight.cmdOutputText = "";
                                    }
                                    onEntered: parent.opacity = 1
                                    onExited: parent.opacity = 0.5
                                }
                            }
                        }

                        // Salida del comando
                        Flickable {
                            id: cmdFlickable
                            width: parent.width
                            height: Math.min(cmdOutput.length * 20 + 8, 440)
                            contentHeight: cmdOutputText.length > 0
                                ? cmdOutput.length * 20 + 8
                                : 0
                            clip: true

                            // Capturar rueda del mouse en cualquier parte de la terminal para hacer scroll
                            MouseArea {
                                anchors.fill: parent
                                propagateComposedEvents: true
                                preventStealing: false
                                onWheel: (wheel) => {
                                    // Desplazamiento suave con la rueda
                                    var speed = 0.5;
                                    cmdFlickable.contentY = Math.max(0, Math.min(
                                        cmdFlickable.contentHeight - cmdFlickable.height,
                                        cmdFlickable.contentY - wheel.angleDelta.y * speed
                                    ));
                                }
                            }

                            Text {
                                id: cmdOutputDisplay
                                width: parent.width
                                text: cmdOutput.join("\n")
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                                opacity: 0.85
                                wrapMode: Text.WrapAnywhere
                            }

                            ScrollBar.vertical: ScrollBar {
                                width: 8
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    radius: 4
                                    color: Styling.srItem("overprimary")
                                    opacity: 0.6
                                }
                            }
                        }
                    }
                }

                // ── Notificaciones inline de Hax ─────────────────────────────
                StyledRect {
                    id: haxNotifContainer
                    width: contentColumn.width
                    height: _haxNotifications.length > 0
                        ? Math.min(_haxNotifications.length * 56 + 16, 200)
                        : 0
                    opacity: _haxNotifications.length > 0 ? 1 : 0
                    visible: opacity > 0
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    Behavior on height {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: Config.animDuration * 3; easing.type: Easing.OutQuint }
                    }
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuint }
                    }

                    Column {
                        width: parent.width
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Repeater {
                            model: _haxNotifications

                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: 48

                                RowLayout {
                                    width: parent.width
                                    height: parent.height
                                    spacing: 8

                                    Text {
                                        text: modelData.icon
                                        font.pixelSize: Config.theme.fontSize + 8
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 2
                                        Text {
                                            text: modelData.type === "timer"
                                                ? "⏰ Timer «" + modelData.label + "» completado"
                                                : "🔔 Alarma «" + modelData.label + "»"
                                            font.family: Config.theme.font
                                            font.pixelSize: Config.theme.fontSize
                                            font.bold: true
                                            color: Styling.srItem("text")
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.body
                                            font.family: Config.theme.font
                                            font.pixelSize: Config.theme.fontSize - 2
                                            color: Styling.srItem("overprimary")
                                            opacity: 0.7
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Botón cerrar
                                    StyledRect {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        radius: Styling.radius(8)
                                        variant: "focus"
                                        Layout.alignment: Qt.AlignVCenter
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            font.pixelSize: Config.theme.fontSize - 2
                                            color: Styling.srItem("overprimary")
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { _dismissHaxNotif(modelData.id); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Lista de resultados (solo visible al escribir) ────────────
                // Se despliega con una animación combinada de fade + expansión vertical
                Item {
                    id: resultsContainer
                    width: contentColumn.width
                    height: results.length > 0 ? Math.min(results.length * 54, 400) : 0
                    opacity: results.length > 0 ? 1 : 0
                    visible: opacity > 0
                    clip: true
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration * 2
                            easing.type: Easing.OutQuint
                        }
                    }

                    Behavior on height {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration * 3
                            easing.type: Easing.OutQuint
                        }
                    }


                    ListView {
                        id: resultsList
                        width: parent.width
                        height: parent.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        model: results
                        spacing: 2

                        // Scrollbar vertical para la lista de resultados
                        ScrollBar.vertical: ScrollBar {
                            width: 6
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                radius: 3
                                color: Styling.srItem("overprimary")
                                opacity: 0.4
                            }
                        }

                        delegate: Item {
                            width: resultsList.width
                            height: 52

                            // Resaltado de selección (semitransparente)
                            Rectangle {
                                anchors.fill: parent
                                radius: Styling.radius(10)
                                color: index === spotlight.selectedIndex
                                    ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.25)
                                    : "transparent"

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation { duration: Config.animDuration / 3 }
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent

                                // Hax es 100% teclado: el ratón NO dispara la previsualización.
                                // (El ratón solo se usa en el Historial para borrar copias antiguas.)
                                onClicked: {
                                    spotlight.selectedIndex = index;
                                    // Archivo → previsualizar (Quick Look) dentro de Hax.
                                    // History → copiar. Si tiene exec (stats, etc.) → ejecutar.
                                    if (modelData.type === "file") {
                                        spotlight.openPreview(modelData);
                                    } else if (modelData.exec) {
                                        spotlight.executeItem(modelData);
                                    } else if (modelData.type === "history") {
                                        spotlight.copyResult(modelData);
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 12

                                // Icono (app → system icon, otros → Phosphor)
                                Item {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    Layout.alignment: Qt.AlignVCenter

                                    // Icono del tema del sistema (para apps)
                                    Image {
                                        id: sysIcon
                                        anchors.fill: parent
                                        mipmap: true
                                        source: modelData.type === "app" ? "image://icon/" + (modelData.icon || "image-missing") : ""
                                        sourceSize.width: 32
                                        sourceSize.height: 32
                                        fillMode: Image.PreserveAspectFit
                                        visible: true

                                        onStatusChanged: {
                                            if (status === Image.Error) {
                                                source = "image://icon/image-missing";
                                            }
                                        }
                                    }

                                    // Tinte del theme para que combine con el sistema
                                    Tinted {
                                        anchors.fill: parent
                                        sourceItem: sysIcon
                                        visible: modelData.type === "app"
                                    }

                                    // Icono Phosphor (para calc, web, archivos, history y fallback)
                                    Text {
                                        id: phosphorIcon
                                        anchors.centerIn: parent
                                        text: {
                                            switch (modelData.type) {
                                                case "calc": return Icons.notepad;
                                                case "web":  return Icons.globe;
                                                case "file": return Icons.file;
                                                case "history": return Icons.notepad;
                                                default:     return Icons.apps;
                                            }
                                        }
                                        font.family: Icons.font
                                        font.pixelSize: 20
                                        color: Styling.srItem("overprimary")
                                        opacity: 0.8
                                        visible: modelData.type !== "app" || sysIcon.status === Image.Error
                                    }
                                }

                                // Nombre + descripción
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name || ""
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize
                                        font.weight: Font.Medium
                                        color: Styling.srItem("text")
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.description || modelData.type || ""
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize - 3
                                        color: Styling.srItem("text")
                                        opacity: 0.5
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }

                                // Badge del tipo
                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 20
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: Styling.radius(-4)
                                    color: Qt.rgba(1, 1, 1, 0.08)

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            switch (modelData.type) {
                                                case "app": return "App";
                                                case "calc": return "=";
                                                case "file": return "📁";
                                                case "web": return "🌐";
                                                case "history": return "📋";
                                                default: return "";
                                            }
                                        }
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize - 4
                                        color: Styling.srItem("text")
                                        opacity: 0.5
                                    }
                                }

                                // Botón copiar (visible al hover)
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.rightMargin: 4
                                    radius: Styling.radius(-4)
                                    color: mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    opacity: mouseArea.containsMouse ? 1 : 0
                                    visible: modelData.type !== "calc" && modelData.type !== "info"

                                    Behavior on opacity { NumberAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⎘"  // símbolo de copiar
                                        font.pixelSize: 14
                                        color: Styling.srItem("text")
                                        opacity: 0.7
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spotlight.copyResult(modelData);
                                            mouse.accepted = true;
                                        }
                                    }
                                }

                                // Botón eliminar del historial (solo para items history, visible al hover)
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.rightMargin: 4
                                    radius: Styling.radius(-4)
                                    color: delMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.2) : "transparent"
                                    opacity: (mouseArea.containsMouse && modelData.type === "history") ? 1 : 0
                                    visible: modelData.type === "history"

                                    Behavior on opacity { NumberAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        font.pixelSize: 13
                                        color: "#f87171"
                                        opacity: 0.8
                                    }

                                    MouseArea {
                                        id: delMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spotlight.removeFromHistory(modelData.historyText || modelData.name);
                                            mouse.accepted = true;
                                        }
                                    }
                                }
                            }

                            // Separador
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                height: 1
                                color: Styling.srItem("text")
                                opacity: 0.06
                                visible: index < results.length - 1
                            }
                        }
                    }
                }

                // ── Monitor del sistema (/stats) ───────────────────────────────
                StyledRect {
                    id: monitorContainer
                    width: contentColumn.width
                    height: showMonitor ? 260 : 0
                    visible: showMonitor
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    opacity: showMonitor ? 1 : 0

                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Column {
                        width: parent.width
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        // ── Header ─────────────────────────────────────────────
                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: "📊 Monitor del Sistema"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize + 2
                                color: Styling.srItem("text")
                                Layout.fillWidth: true
                            }

                            // Indicador en vivo
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: "#4ade80"
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 800 }
                                    NumberAnimation { to: 1; duration: 800 }
                                }
                            }
                            Text {
                                text: "EN VIVO"
                                font.pixelSize: Config.theme.fontSize - 4
                                font.bold: true
                                color: "#4ade80"
                                opacity: 0.7
                            }

                            // Botón cerrar
                            Text {
                                text: "✕"
                                font.pixelSize: Config.theme.fontSize + 2
                                font.bold: true
                                color: Styling.srItem("text")
                                opacity: 0.5
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: stopMonitor()
                                    onEntered: parent.opacity = 1
                                    onExited: parent.opacity = 0.5
                                }
                            }
                        }

                        // ── CPU ────────────────────────────────────────────────
                        RowLayout { width: parent.width; spacing: 8
                            Text { text: "💻 CPU"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                            Item { Layout.fillWidth: true; height: 10
                                Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                    Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monCpu / 100, 1)
                                        color: monCpu < 50 ? "#4ade80" : monCpu < 80 ? "#facc15" : "#ef4444"
                                    }
                                }
                            }
                            Text { text: monCpu.toFixed(1) + "%"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                        }

                        // ── RAM ────────────────────────────────────────────────
                        RowLayout { width: parent.width; spacing: 8
                            Text { text: "📦 RAM"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                            Item { Layout.fillWidth: true; height: 10
                                Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                    Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monRamPct / 100, 1)
                                        color: monRamPct < 50 ? "#4ade80" : monRamPct < 80 ? "#facc15" : "#ef4444"
                                    }
                                }
                            }
                            Text { text: (monRamUsed / 1048576).toFixed(1) + "/" + (monRamTotal / 1048576).toFixed(1) + " GB"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight }
                        }

                        // ── Disco ──────────────────────────────────────────────
                        RowLayout { width: parent.width; spacing: 8
                            Text { text: "💾 Disco"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                            Item { Layout.fillWidth: true; height: 10
                                Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                    Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monDisk / 100, 1)
                                        color: monDisk < 50 ? "#4ade80" : monDisk < 80 ? "#facc15" : "#ef4444"
                                    }
                                }
                            }
                            Text { text: monDisk.toFixed(0) + "%"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                        }

                        // ── Temperatura ─────────────────────────────────────────
                        RowLayout { width: parent.width; spacing: 8
                            Text { text: "🌡️ Temp"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                            Item { Layout.fillWidth: true; height: 10
                                Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                    Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monTemp / 100, 1)
                                        color: monTemp < 60 ? "#4ade80" : monTemp < 80 ? "#facc15" : "#ef4444"
                                    }
                                }
                            }
                            Text { text: monTemp + "°C"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                        }

                        // ── Info extra ─────────────────────────────────────────
                        RowLayout { width: parent.width; spacing: 16
                            Text { text: "🔄 " + monProcs + " procesos"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); opacity: 0.7 }
                            Text { text: "⏰ " + monUptime; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); opacity: 0.7; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: "⏱ cada 2s"; font.pixelSize: Config.theme.fontSize - 3; color: Styling.srItem("overprimary"); opacity: 0.4 }
                        }
                    }
                }
                // ── Modo desarrollador (debug) — "d"/"dev"/"debug" + Enter ───────
                // Se muestra EN EL MISMO SITIO que el monitor del sistema (debajo de resultados).
                StyledRect {
                    id: debugPane
                    width: contentColumn.width
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    visible: spotlight.showDebug
                    opacity: spotlight.showDebug ? 1 : 0
                    height: spotlight.showDebug ? Math.max(debugContent.implicitHeight + 20, 120) : 0
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: Config.animDuration * 2 }
                    }

                    Column {
                        id: debugContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 10

                        RowLayout {
                            width: parent.width
                            Text {
                                Layout.fillWidth: true
                                text: "🐞 Modo desarrollador (debug)"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize
                                color: Styling.srItem("text")
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "✕"
                                font.pixelSize: Config.theme.fontSize + 2
                                font.bold: true
                                color: Styling.srItem("text")
                                opacity: 0.5
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: spotlight.showDebug = false
                                }
                            }
                        }

                        // ⚙️ Recursos
                        Column {
                            spacing: 4
                            width: parent.width
                            Text {
                                text: "⚙️ Recursos"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize - 1
                                color: Styling.srItem("overprimary")
                                opacity: 0.85
                            }
                            Text {
                                text: "Memoria (RSS): " + (spotlight.debugMemMB > 0 ? spotlight.debugMemMB.toFixed(1) : "—") + " MB"
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }
                            Text {
                                text: "CPU: " + (spotlight.debugCpuPct > 0 ? spotlight.debugCpuPct.toFixed(1) : "0.0") + " %"
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }
                        }

                        // ⏱️ Tiempos
                        Column {
                            spacing: 4
                            width: parent.width
                            Text {
                                text: "⏱️ Tiempos"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize - 1
                                color: Styling.srItem("overprimary")
                                opacity: 0.85
                            }
                            Text {
                                text: "Apertura (open→listo): " + (spotlight.debugOpenMs >= 0 ? spotlight.debugOpenMs + " ms" : "—")
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }
                            Text {
                                text: "Última búsqueda: " + (spotlight.debugLastSearchMs >= 0 ? spotlight.debugLastSearchMs + " ms" : "—")
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }
                            Text {
                                text: "Sesión abierta: " + spotlight.debugSessionS + " s"
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }
                        }

                        // 🚨 Errores capturados
                        Column {
                            spacing: 4
                            width: parent.width
                            Text {
                                text: "🚨 Errores capturados (" + spotlight.debugErrorLog.length + ")"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize - 1
                                color: Styling.srItem("overprimary")
                                opacity: 0.85
                            }
                            Repeater {
                                model: spotlight.debugErrorLog
                                delegate: Text {
                                    required property var modelData
                                    width: parent.width
                                    text: "• [" + modelData.t + "] " + modelData.ctx + ": " + modelData.msg
                                    font.family: "monospace"
                                    font.pixelSize: Config.theme.fontSize - 3
                                    color: "#ff8a80"
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                            Text {
                                visible: spotlight.debugErrorLog.length === 0
                                text: "✅ Sin errores"
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                                opacity: 0.7
                            }
                        }
                    }
                }

                // ── Previsualización rápida (Quick Look) ───────────────────────
                // Dentro de contentColumn (en el flujo), igual que el Monitor.
                // Cabecera (nombre + ruta) arriba + contenido (imagen/texto) abajo.
                StyledRect {
                    id: previewContainer
                    width: contentColumn.width
                    height: showPreview ? 300 : 0
                    visible: showPreview
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    opacity: showPreview ? 1 : 0

                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    // Cabecera (nombre + ruta) — anclada arriba
                    Column {
                        id: previewHeaderCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "👁 " + (spotlight.previewName || "Quick Look")
                                elide: Text.ElideRight
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize + 1
                                color: Styling.srItem("text")
                            }

                            Text {
                                text: "✕"
                                font.pixelSize: Config.theme.fontSize + 2
                                font.bold: true
                                color: Styling.srItem("text")
                                opacity: 0.5
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: spotlight.showPreview = false
                                    onEntered: parent.opacity = 1
                                    onExited: parent.opacity = 0.5
                                }
                            }
                        }

                        Text {
                            id: previewPathText
                            width: parent.width
                            text: previewPath
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("overprimary")
                            opacity: 0.7
                            elide: Text.ElideMiddle
                        }
                    }

                    // Contenido (imagen o texto) — rellena debajo de la cabecera
                    Item {
                        id: previewContent
                        anchors.top: previewHeaderCol.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 14

                        // Imagen — Image con layer.enabled para evitar el bug de Quickshell
                        Image {
                            id: previewImg
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: ocrBox.visible ? ocrBox.top : parent.bottom
                            source: previewImageSrc
                            fillMode: Image.PreserveAspectFit
                            visible: previewType === "image"
                            mipmap: true
                            smooth: true
                            layer.enabled: true
                            layer.smooth: true
                        }

                        // Texto detectado en la imagen (Live Text / OCR)
                        StyledRect {
                            id: ocrBox
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 116
                            radius: Styling.radius(8)
                            variant: "pane"
                            visible: previewType === "image" && previewOcrText !== ""
                            clip: true

                            Text {
                                id: ocrLabel
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 8
                                text: "📝 Texto en la imagen"
                                font.bold: true
                                font.pixelSize: Config.theme.fontSize - 3
                                color: Styling.srItem("overprimary")
                                opacity: 0.8
                            }

                            Flickable {
                                anchors.top: ocrLabel.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: copyOcrBtn.top
                                anchors.margins: 8
                                contentHeight: ocrTextEl.height
                                clip: true
                                Text {
                                    id: ocrTextEl
                                    width: parent.width
                                    text: previewOcrText
                                    font.family: "monospace"
                                    font.pixelSize: Config.theme.fontSize - 3
                                    color: Styling.srItem("text")
                                    wrapMode: Text.WrapAnywhere
                                }
                                ScrollBar.vertical: ScrollBar {
                                    width: 5
                                    policy: ScrollBar.AsNeeded
                                    contentItem: Rectangle { radius: 3; color: Styling.srItem("overprimary"); opacity: 0.4 }
                                }
                            }

                            Text {
                                id: copyOcrBtn
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                text: "📋 Copiar"
                                font.pixelSize: Config.theme.fontSize - 3
                                color: Styling.srItem("text")
                                opacity: 0.8
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: spotlight.copyOcrText()
                                    onEntered: parent.opacity = 1
                                    onExited: parent.opacity = 0.8
                                }
                            }
                        }

                        // Texto / binario
                        Flickable {
                            anchors.fill: parent
                            contentHeight: previewTextArea.height
                            clip: true
                            visible: previewType !== "image"
                            boundsBehavior: Flickable.StopAtBounds

                            Text {
                                id: previewTextArea
                                width: parent.width
                                text: previewText
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                                opacity: 0.85
                                wrapMode: Text.WrapAnywhere
                            }

                            ScrollBar.vertical: ScrollBar {
                                width: 6
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    radius: 3
                                    color: Styling.srItem("overprimary")
                                    opacity: 0.4
                                }
                            }
                        }
                    }
                }

            }
                }



    // ── Terminal integrada ─────────────────────────────────────────────────

    function runCmd(cmd) {
        // Cancelar proceso anterior si existe
        cancelCmdProcess();

        if (cmd.trim().length === 0) return;

        _forceTerminal = true;  // <-- forzar terminal visible
        cmdOutput = [];
        cmdOutputText = "";

        var proc;
        try {
            proc = Qt.createQmlObject(
                'import Quickshell.Io; Process { stdout: SplitParser {} }',
                spotlight
            );
        } catch (e) {
            spotlight.debugLogError("runCmd", e);
            return;
        }

        // Usar el shell por defecto del usuario en modo interactivo (-i) para
        // respetar sus alias (p. ej. los de fish en config.fish / fish_greeting.fish).
        // Probado: `fish -i -c` carga los alias y no escupe el saludo en la salida.
        var shellBin = Quickshell.env("SHELL") || "bash";
        proc.command = [shellBin, "-i", "-c", cmd + " 2>&1"];
        proc.workingDirectory = Quickshell.env("HOME") || "/tmp";

        proc.stdout.onRead.connect(function(data) {
            var arr = cmdOutput.slice();  // clonar para que QML detecte cambio
            var lines = data.trim().split("\n");
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].length > 0) arr.push(lines[i]);
            }
            cmdOutput = arr;
            cmdOutputText = arr.join("\n");
        });

        proc.onExited.connect(function(code) {
            _forceTerminal = false;
            var arr = cmdOutput.slice();
            arr.push("✦ Hecho (código: " + code + ")");
            cmdOutput = arr;
            cmdOutputText = arr.join("\n");
            cmdProcess = null;
            _lastCmdVisible = true;  // mantener visible
            proc.destroy();
        });

        cmdProcess = proc;
        proc.running = true;
    }

    function cancelCmdProcess() {
        _forceTerminal = false;
        _lastCmdVisible = false;
        if (cmdProcess) {
            cmdProcess.running = false;
            cmdProcess.destroy();
            cmdProcess = null;
        }
        cmdOutput = [];
        cmdOutputText = "";
    }

    // ── Ejecutar comando rápido (fuego y olvido) ──────────────────────────
    function bash(cmd) {
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { }',
            spotlight
        );
        proc.command = ["bash", "-c", cmd];
        proc.onExited.connect(function() { proc.destroy(); });
        proc.running = true;
    }

    // ── Terminal embebida (QMLTermWidget) ────────────────────────────────────
    // Se abre escribiendo "/" en el buscador. Es un terminal real (fish + alias)
    // corriendo en un PTY, 100% operativo (vim, htop, sudo, TAB...).
    function openTerminal() {
        spotlight.showTerminal = true;
        spotlight.showPreview = false;
        spotlight.showMonitor = false;
        spotlight.cancelCmdProcess();
        spotlight.searchText = "";
    }
    function closeTerminal() {
        spotlight.showTerminal = false;
        searchInput.forceActiveFocus();
    }

    // ── Lógica de búsqueda ─────────────────────────────────────────────────

    function updateResults() {
        // Cerrar previsualización al cambiar la búsqueda
        spotlight.showPreview = false;

        // En modo comando, no mostrar resultados normales
        if (isCommandMode) {
            results = [];
            return;
        }

        const query = searchText.trim().toLowerCase();
        const gen = ++searchGeneration;

        // Construir array nuevo y asignarlo para que QML detecte el cambio
        var newResults = [];

        if (query.length === 0) {
            // Vacío hasta que el usuario escriba
            results = [];
            return;
        }

        // Detectar si es cálculo
        // Solo comprobamos que sean dígitos y operadores básicos
        if (/^[\d+\-*/().\s]+$/.test(query) && /[+\-*/]/.test(query)) {
            const result = safeEval(query);
            if (result !== null && typeof result === "number") {
                newResults.push({
                    name: query + " = " + result,
                    description: "Copiar resultado",
                    icon: Icons.notepad,
                    type: "calc",
                    exec: () => {
                        const p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                        p.command = ["wl-copy", String(result)];
                        p.running = true;
                        p.onExited.connect(() => p.destroy());
                        Visibilities.setActiveModule("");
                    }
                });
                results = newResults;
                return;
            }
        }

        // ── Acciones del sistema ────────────────────────────────────────────
        var sysMatch = query.match(/^(l|s|a|r|c|lock|bloquear|suspend|suspender|apagar|shutdown|poweroff|reboot|reiniciar|capturar|screenshot|pantallazo)$/i);
        if (sysMatch) {
            var action = sysMatch[1].toLowerCase();
            var actions = {
                "l": { name: "🔒 Bloquear pantalla", desc: "Lockscreen — bloquear sesión", exec: function() { LockscreenService.lock(); Visibilities.setActiveModule(""); } },
                "lock": { name: "🔒 Bloquear pantalla", desc: "Lockscreen — bloquear sesión", exec: function() { LockscreenService.lock(); Visibilities.setActiveModule(""); } },
                "bloquear": { name: "🔒 Bloquear pantalla", desc: "Lockscreen — bloquear sesión", exec: function() { LockscreenService.lock(); Visibilities.setActiveModule(""); } },
                "s": { name: "💤 Suspender", desc: "systemctl suspend — suspender el sistema", exec: function() { bash("systemctl suspend"); Visibilities.setActiveModule(""); } },
                "suspend": { name: "💤 Suspender", desc: "systemctl suspend — suspender el sistema", exec: function() { bash("systemctl suspend"); Visibilities.setActiveModule(""); } },
                "suspender": { name: "💤 Suspender", desc: "systemctl suspend — suspender el sistema", exec: function() { bash("systemctl suspend"); Visibilities.setActiveModule(""); } },
                "a": { name: "⏻ Apagar", desc: "systemctl poweroff — apagar el sistema", exec: function() { bash("systemctl poweroff"); Visibilities.setActiveModule(""); } },
                "apagar": { name: "⏻ Apagar", desc: "systemctl poweroff — apagar el sistema", exec: function() { bash("systemctl poweroff"); Visibilities.setActiveModule(""); } },
                "shutdown": { name: "⏻ Apagar", desc: "systemctl poweroff — apagar el sistema", exec: function() { bash("systemctl poweroff"); Visibilities.setActiveModule(""); } },
                "poweroff": { name: "⏻ Apagar", desc: "systemctl poweroff — apagar el sistema", exec: function() { bash("systemctl poweroff"); Visibilities.setActiveModule(""); } },
                "r": { name: "🔄 Reiniciar", desc: "systemctl reboot — reiniciar el sistema", exec: function() { bash("systemctl reboot"); Visibilities.setActiveModule(""); } },
                "reboot": { name: "🔄 Reiniciar", desc: "systemctl reboot — reiniciar el sistema", exec: function() { bash("systemctl reboot"); Visibilities.setActiveModule(""); } },
                "reiniciar": { name: "🔄 Reiniciar", desc: "systemctl reboot — reiniciar el sistema", exec: function() { bash("systemctl reboot"); Visibilities.setActiveModule(""); } },
                "c": { name: "📸 Capturar pantalla", desc: "Screenshot — herramienta de captura", exec: function() { Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; Visibilities.setActiveModule(""); } },
                "capturar": { name: "📸 Capturar pantalla", desc: "Screenshot — herramienta de captura", exec: function() { Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; Visibilities.setActiveModule(""); } },
                "screenshot": { name: "📸 Capturar pantalla", desc: "Screenshot — herramienta de captura", exec: function() { Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; Visibilities.setActiveModule(""); } },
                "pantallazo": { name: "📸 Capturar pantalla", desc: "Screenshot — herramienta de captura", exec: function() { Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; Visibilities.setActiveModule(""); } }
            };
            var a = actions[action];
            if (a) {
                results = [{
                    name: a.name,
                    description: a.desc,
                    icon: Icons.notepad,
                    type: "info",
                    exec: a.exec
                }];
                return;
            }
        }

        // ── Ayuda ─────────────────────────────────────────────────────────────
        var helpMatch = query.match(/^(ayuda|help|h|commands|comandos|\?)$/i);
        if (helpMatch) {
            newResults = [
                { name: "📖 Comandos disponibles", description: "Escribe lo que quieras hacer", icon: Icons.notepad, type: "info", exec: null },
                { name: "🔍 Buscar apps", description: "Escribe el nombre de cualquier app (firefox, vscode, terminal...)", icon: Icons.notepad, type: "info", exec: null },
                { name: "📦 install <paquete>", description: "Busca en pacman + AUR + flatpak y muestra dónde instalarlo", icon: Icons.notepad, type: "info", exec: null },
                { name: "📦 pacman <paquete>", description: "Instalar paquete directamente con pacman (sudo)", icon: Icons.notepad, type: "info", exec: null },
                { name: "📦 yay <paquete>", description: "Instalar paquete desde AUR con yay", icon: Icons.notepad, type: "info", exec: null },
                { name: "📦 flatpak install <paquete>", description: "Instalar paquete desde Flathub", icon: Icons.notepad, type: "info", exec: null },
                { name: "🗑️ remove <paquete>", description: "Desinstalar paquete con pacman", icon: Icons.notepad, type: "info", exec: null },
                { name: "🔄 update", description: "Actualizar sistema (pacman -Syu)", icon: Icons.notepad, type: "info", exec: null },
                { name: "⏱️ timer <duración>", description: "Crea un timer (ej: timer 5m, timer pizza 10m, timer 30s)", icon: Icons.notepad, type: "info", exec: null },
                { name: "🔔 alarm <hora>", description: "Crea una alarma (ej: alarm 8:00, alarm 7:30 l-v, alarm 14:30 comida)", icon: Icons.notepad, type: "info", exec: null },
                { name: "🌤️ weather / clima / tiempo", description: "Consulta el clima (ej: weather, weather Madrid)", icon: Icons.notepad, type: "info", exec: null },
                { name: "🧮 Calculadora", description: "Escribe una operación (ej: 2+2, 5*3, (10+5)/3)", icon: Icons.notepad, type: "info", exec: null },
                { name: "🔒 lock / bloquear", description: "Bloquear la pantalla", icon: Icons.notepad, type: "info", exec: null },
                { name: "💤 s / suspend", description: "Suspender el sistema", icon: Icons.notepad, type: "info", exec: null },
                { name: "⏻ a / apagar / shutdown", description: "Apagar el sistema", icon: Icons.notepad, type: "info", exec: null },
                { name: "🔄 r / reboot / reiniciar", description: "Reiniciar el sistema", icon: Icons.notepad, type: "info", exec: null },
                { name: "📸 c / capturar / screenshot", description: "Capturar pantalla", icon: Icons.notepad, type: "info", exec: null },
                { name: "🔍 Buscar archivos", description: "Escribe cualquier nombre de archivo (mín 2 caracteres)", icon: Icons.notepad, type: "info", exec: null },
                { name: "🌐 Buscar en web", description: "Cualquier texto que no sea comando se busca en Google", icon: Icons.notepad, type: "info", exec: null },
                { name: "/", description: "Abre la terminal integrada (fish) dentro de Hax — 100% operativa (vim, htop, sudo...)", icon: Icons.notepad, type: "info", exec: null },
                { name: "/stats", description: "Abre el monitor del sistema en vivo (CPU, RAM, disco, temp)", icon: Icons.notepad, type: "info", exec: null },
                { name: "❓ ayuda / help / h / ?", description: "Muestra esta ayuda", icon: Icons.notepad, type: "info", exec: null }
            ];
            results = newResults;
            return;
        }

        // ── Monitor del sistema ──────────────────────────────────────────────
        var statsMatch = query.match(/^(stats|monitor|sistema)$/i);
        if (statsMatch) {
            newResults.push({
                name: showMonitor ? "📊 Cerrar monitor del sistema" : "📊 Monitor del Sistema",
                description: showMonitor
                    ? "Toca para cerrar el monitor en vivo"
                    : "Muestra CPU, RAM, disco y temperatura en tiempo real",
                icon: Icons.notepad, type: "info",
                exec: function() { toggleMonitor(); }
            });
            results = newResults;
            return;
        }

        // ── Timers ────────────────────────────────────────────────────────────
        var timerMatch = query.match(/^timer(?:\s+(.+))?$/i);
        if (timerMatch) {
            var timerArgs = (timerMatch[1] || "").trim();

            if (!timerArgs) {
                if (activeTimers.length === 0) {
                    newResults.push({ name: "⏱️ No hay timers activos", description: "Ej: timer 5m, timer pizza 10m, timer 30s", icon: Icons.notepad, type: "info", exec: null });
                } else {
                    for (var ti = 0; ti < activeTimers.length; ti++) {
                        var t = activeTimers[ti];
                        var remain = Math.max(0, Math.floor((t.endTime - Date.now()) / 1000));
                        (function(tmr) {
                            newResults.push({
                                name: "⏱️ " + tmr.label + " — " + _fmtDur(remain) + " restantes",
                                description: "Termina ~" + new Date(tmr.endTime).toLocaleTimeString(),
                                icon: Icons.notepad, type: "info",
                                exec: null
                            });
                            newResults.push({
                                name: "❌ Cancelar «" + tmr.label + "»",
                                description: "Detener este temporizador",
                                icon: Icons.notepad, type: "info",
                                exec: function() { cancelTimer(tmr.id); Visibilities.setActiveModule(""); }
                            });
                        })(t);
                    }
                }
                newResults.push({ name: "🗑️ Cancelar todos los timers", description: "", icon: Icons.notepad, type: "info", exec: function() { clearAllTimers(); Visibilities.setActiveModule(""); } });
                results = newResults;
                return;
            }

            if (/^(cancel|clear|stop)\s*$/i.test(timerArgs)) {
                newResults.push({ name: "🗑️ Cancelar todos los timers", description: "Detener todos los temporizadores activos", icon: Icons.notepad, type: "info", exec: function() { clearAllTimers(); Visibilities.setActiveModule(""); } });
                results = newResults;
                return;
            }

            var cancelMatch = timerArgs.match(/^cancel\s+(.+)$/i);
            if (cancelMatch) {
                var target = cancelMatch[1].trim();
                var found = false;
                for (var ti2 = 0; ti2 < activeTimers.length; ti2++) {
                    if (activeTimers[ti2].label.toLowerCase() === target.toLowerCase()) {
                        (function(tmr2) {
                            newResults.push({ name: "❌ Cancelar «" + tmr2.label + "»", description: "Detener este temporizador", icon: Icons.notepad, type: "info", exec: function() { cancelTimer(tmr2.id); Visibilities.setActiveModule(""); } });
                        })(activeTimers[ti2]);
                        found = true;
                    }
                }
                if (!found) {
                    var num = parseInt(target);
                    if (!isNaN(num)) {
                        for (var ti3 = 0; ti3 < activeTimers.length; ti3++) {
                            if (activeTimers[ti3].id === num) {
                                (function(tmr3) {
                                    newResults.push({ name: "❌ Cancelar «" + tmr3.label + "»", description: "Detener este temporizador", icon: Icons.notepad, type: "info", exec: function() { cancelTimer(tmr3.id); Visibilities.setActiveModule(""); } });
                                })(activeTimers[ti3]);
                                found = true;
                                break;
                            }
                        }
                    }
                }
                if (!found) {
                    newResults.push({ name: "⚠️ Timer no encontrado", description: "No hay ningún timer con ese nombre o ID", icon: Icons.notepad, type: "info", exec: null });
                }
                results = newResults;
                return;
            }

            var durMatch = timerArgs.match(/(\d+)\s*([smh])\s*(.*)$/i) || timerArgs.match(/(\d+):(\d{1,2})\s*(.*)$/);
            if (durMatch) {
                var label = "";
                var seconds = 0;
                if (durMatch[2] === undefined) {
                    seconds = parseInt(durMatch[1]) * 60 + parseInt(durMatch[2]);
                    label = (durMatch[3] || "").trim();
                } else {
                    var unit = durMatch[2].toLowerCase();
                    var val = parseInt(durMatch[1]);
                    if (unit === 's') seconds = val;
                    else if (unit === 'm') seconds = val * 60;
                    else if (unit === 'h') seconds = val * 3600;
                    label = (durMatch[3] || "").trim();
                }
                if (!label) {
                    var beforeDur = timerArgs.replace(durMatch[0], '').trim();
                    if (beforeDur) label = beforeDur;
                }
                if (seconds > 0 && seconds <= 86400) {
                    var timerLabel = label || ("Timer " + _timerNextId);
                    (function(lbl, sec) {
                        newResults.push({
                            name: "✅ Iniciar timer «" + lbl + "» — " + _fmtDur(sec),
                            description: "Temporizador de " + (sec >= 3600 ? (sec/3600).toFixed(1) + "h" : sec >= 60 ? (sec/60) + "m" : sec + "s"),
                            icon: Icons.notepad, type: "info",
                            exec: function() { startTimer(lbl, sec); Visibilities.setActiveModule(""); }
                        });
                    })(timerLabel, seconds);
                } else {
                    newResults.push({ name: "⚠️ Duración inválida", description: "Máximo 24 horas. Ej: timer 5m, timer 30s, timer 2h", icon: Icons.notepad, type: "info", exec: null });
                }
                results = newResults;
                return;
            }

            newResults.push({ name: "⏱️ Timer — cómo usarlo", description: "timer 5m · timer pizza 10m · timer 30s descanso · timer cancel · timer clear", icon: Icons.notepad, type: "info", exec: null });
            results = newResults;
            return;
        }

        // ── Alarmas ───────────────────────────────────────────────────────────
        var alarmMatch = query.match(/^alarm(?:[ea]s)?(?:\s+(.+))?$/i);
        if (alarmMatch) {
            var alarmArgs = (alarmMatch[1] || "").trim();

            if (!alarmArgs) {
                if (activeAlarms.length === 0) {
                    newResults.push({ name: "🔔 No hay alarmas", description: "Ej: alarm 7:30, alarm 8:00 despertar, alarm 14:30 comida L M X J V", icon: Icons.notepad, type: "info", exec: null });
                } else {
                    for (var ai = 0; ai < activeAlarms.length; ai++) {
                        var al = activeAlarms[ai];
                        var daysStr = al.days.length > 0 ? al.days.map(function(d) { return ["Dom","Lun","Mar","Mié","Jue","Vie","Sáb"][d]; }).join(" ") : "📅 Todos";
                        var timeStr = (al.hour < 10 ? "0" : "") + al.hour + ":" + (al.minute < 10 ? "0" : "") + al.minute;
                        (function(alm) {
                            newResults.push({
                                name: (alm.enabled ? "🔔" : "🔕") + " " + alm.label + " — " + timeStr + " " + daysStr,
                                description: alm.enabled ? "Activa · Toca para desactivar" : "Inactiva · Toca para activar",
                                icon: Icons.notepad, type: "info",
                                exec: function() { alm.enabled = !alm.enabled; Visibilities.setActiveModule(""); }
                            });
                            newResults.push({
                                name: "❌ Eliminar alarma «" + alm.label + "»",
                                description: "Borrar esta alarma permanentemente",
                                icon: Icons.notepad, type: "info",
                                exec: function() { cancelAlarm(alm.id); Visibilities.setActiveModule(""); }
                            });
                        })(al);
                    }
                }
                newResults.push({ name: "🗑️ Eliminar todas las alarmas", description: "", icon: Icons.notepad, type: "info", exec: function() { clearAllAlarms(); Visibilities.setActiveModule(""); } });
                results = newResults;
                return;
            }

            if (/^(clear|cancel)\s*$/i.test(alarmArgs)) {
                newResults.push({ name: "🗑️ Eliminar todas las alarmas", description: "Borrar todas las alarmas", icon: Icons.notepad, type: "info", exec: function() { clearAllAlarms(); Visibilities.setActiveModule(""); } });
                results = newResults;
                return;
            }

            var timeMatch = alarmArgs.match(/^(\d{1,2}):(\d{2})\s*(.*)$/);
            if (timeMatch) {
                var hour = parseInt(timeMatch[1]);
                var minute = parseInt(timeMatch[2]);
                var rest = (timeMatch[3] || "").trim();
                if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
                    var days = [];
                    var dayParse = rest.match(/([L M X J V S D]+)$/i);
                    if (dayParse) {
                        var dayStr = dayParse[1].toUpperCase();
                        var dayMap = { 'L': 1, 'M': 2, 'X': 3, 'J': 4, 'V': 5, 'S': 6, 'D': 0 };
                        for (var dk = 0; dk < dayStr.length; dk++) {
                            var dval = dayMap[dayStr[dk]];
                            if (dval !== undefined && days.indexOf(dval) < 0) days.push(dval);
                        }
                        rest = rest.substring(0, rest.length - dayParse[0].length).trim();
                    }
                    var alarmLabel = rest || ("Alarma " + _alarmNextId);
                    var daysLabel = days.length > 0 ? days.map(function(d) { return ["Dom","Lun","Mar","Mié","Jue","Vie","Sáb"][d]; }).join(" ") : "Todos los días";
                    var timeLabel = (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute;
                    (function(alLabel, alHour, alMin, alDays) {
                        newResults.push({
                            name: "✅ Crear alarma «" + alLabel + "» — " + timeLabel + " " + daysLabel,
                            description: "Toca para confirmar",
                            icon: Icons.notepad, type: "info",
                            exec: function() { setAlarm(alLabel, alHour, alMin, alDays); Visibilities.setActiveModule(""); }
                        });
                    })(alarmLabel, hour, minute, days);
                } else {
                    newResults.push({ name: "⚠️ Hora inválida", description: "Usa formato HH:MM (ej: alarm 7:30 despertar)", icon: Icons.notepad, type: "info", exec: null });
                }
                results = newResults;
                return;
            }

            newResults.push({ name: "🔔 Alarma — cómo usarlo", description: "alarm 8:00 · alarm 7:30 despertar · alarm 14:30 comida L M X J V · alarm clear", icon: Icons.notepad, type: "info", exec: null });
            results = newResults;
            return;
        }

        // ── Paquetes ──────────────────────────────────────────────────────────
        var pkgMatch = query.match(/^(install|pacman|yay|flatpak|remove|update)\b\s*(.*)$/i);
        if (pkgMatch) {
            var pkgCmd = pkgMatch[1].toLowerCase();
            var pkgArgs = (pkgMatch[2] || "").trim();

            if (pkgCmd === "update") {
                newResults.push({
                    name: "🔄 Actualizar sistema",
                    description: "sudo pacman -Syu — actualiza todos los paquetes",
                    icon: Icons.notepad, type: "info",
                    exec: function() {
                        runCmd('echo "F200607" | sudo -S rm -f /var/lib/pacman/db.lck 2>/dev/null; echo "F200607" | sudo -S pacman -Syu --noconfirm');
                    }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "remove") {
                if (!pkgArgs) {
                    newResults.push({ name: "🗑️ Especifica qué paquete desinstalar", description: "Ej: remove firefox", icon: Icons.notepad, type: "info", exec: null });
                } else {
                    var rmPkg = pkgArgs;
                    newResults.push({
                        name: "🗑️ Desinstalar «" + rmPkg + "»",
                        description: "sudo pacman -R " + rmPkg,
                        icon: Icons.notepad, type: "info",
                        exec: function() { runCmd('echo "F200607" | sudo -S pacman -R --noconfirm ' + rmPkg); }
                    });
                }
                results = newResults;
                return;
            }

            if (!pkgArgs) {
                newResults.push({ name: "📦 Especifica un paquete", description: "Ej: install firefox, pacman vim, yay chrome, flatpak spotify, remove vim, update", icon: Icons.notepad, type: "info", exec: null });
                results = newResults;
                return;
            }

            if (pkgCmd === "pacman") {
                var pmPkg = pkgArgs;
                newResults.push({
                    name: "📦 Instalar «" + pmPkg + "» (pacman)",
                    description: "sudo pacman -S " + pmPkg,
                    icon: Icons.notepad, type: "info",
                    exec: function() { runCmd('echo "F200607" | sudo -S pacman -S --noconfirm ' + pmPkg); }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "yay") {
                var yyPkg = pkgArgs;
                newResults.push({
                    name: "📦 Instalar «" + yyPkg + "» (AUR/yay)",
                    description: "yay -S " + yyPkg,
                    icon: Icons.notepad, type: "info",
                    exec: function() { runCmd('echo "F200607" | sudo -S yay -S --noconfirm ' + yyPkg); }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "flatpak") {
                var fpParts = pkgArgs.match(/^(install|remove|search)\s+(.+)$/i);
                if (fpParts) {
                    var fpAction = fpParts[1].toLowerCase();
                    var fpName2 = fpParts[2].trim();
                    if (fpAction === "install") {
                        var fpInstPkg = fpName2;
                        newResults.push({
                            name: "📦 Instalar «" + fpInstPkg + "» (flatpak)",
                            description: "flatpak install " + fpInstPkg,
                            icon: Icons.notepad, type: "info",
                            exec: function() { runCmd('flatpak install -y flathub ' + fpInstPkg); }
                        });
                        results = newResults;
                        return;
                    } else if (fpAction === "remove") {
                        var fpRmPkg = fpName2;
                        newResults.push({
                            name: "🗑️ Desinstalar «" + fpRmPkg + "» (flatpak)",
                            description: "flatpak uninstall " + fpRmPkg,
                            icon: Icons.notepad, type: "info",
                            exec: function() { runCmd('flatpak uninstall -y ' + fpRmPkg); }
                        });
                        results = newResults;
                        return;
                    }
                }
                var fpQuery = pkgArgs;
                newResults.push({
                    name: "🔍 Buscar «" + fpQuery + "» en Flathub...",
                    description: "Pulsa Enter para buscar en flatpak",
                    icon: Icons.notepad, type: "info",
                    exec: function() { _searchFlatpak(fpQuery, gen); }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "install") {
                var instPkg = pkgArgs;
                if (!instPkg) {
                    newResults.push({ name: "📦 Especifica un paquete", description: "Ej: install firefox, install vim, install spotify", icon: Icons.notepad, type: "info", exec: null });
                    results = newResults;
                } else if (instPkg === _lastSearchQuery) {
                    // Ya buscamos este paquete (esté en curso o completado), no reiniciar
                    return;
                } else {
                    _lastSearchQuery = instPkg;
                    newResults.push({
                        name: "🔍 Buscando «" + instPkg + "» en pacman, AUR y flatpak...",
                        description: "Espera mientras se buscan los gestores compatibles",
                        icon: Icons.notepad, type: "info",
                        exec: null
                    });
                    results = newResults;
                    _searchPackages(instPkg, gen);
                }
                return;
            }
        }

        // ── Clima ────────────────────────────────────────────────────────────
        var weatherMatch = query.match(/^(weather|tiempo|clima|w(?:eather)?)\b/i);
        if (weatherMatch) {
            if (weatherSearch) {
                weatherSearch.running = false;
                weatherSearch.destroy();
                weatherSearch = null;
            }
            const loc = query.substring(weatherMatch[0].length).trim();
            newResults.push({
                name: "🌤 Consultando clima" + (loc ? " — " + loc : "") + "...",
                description: "Obteniendo datos...",
                icon: Icons.globe,
                type: "info",
                exec: null
            });
            results = newResults;
            startWeatherSearch(loc, gen);
            return;
        }

        // ── Historial inteligente ──────────────────────────────────────────
        // Si busca "historial", "clip", etc. → mostrar TODO el historial
        var histMatch = query.match(/^(historial|history|clip|clipboard|portapapeles)$/i);
        if (histMatch) {
            var histItems = searchHistory(""); // sin límite, devuelve todos
            for (var hi = 0; hi < histItems.length; hi++) {
                var hItem = histItems[hi];
                newResults.push({
                    name: "📋 " + hItem.text,
                    description: "Copiado " + hItem.count + " vez" + (hItem.count !== 1 ? "es" : ""),
                    icon: Icons.notepad,
                    type: "history",
                    historyText: hItem.text,
                    exec: null
                });
            }
            if (newResults.length === 0) {
                newResults.push({
                    name: "📋 Historial vacío",
                    description: "Copia algo con Enter o Ctrl+C y aparecerá aquí",
                    icon: Icons.notepad,
                    type: "info",
                    exec: null
                });
            }
            results = newResults;
            return;
        }

        // Buscar coincidencias en el historial para cualquier query
        if (query.length >= 2 && _historyItems.length > 0) {
            var histMatches = searchHistory(query, 3);
            for (var hi2 = 0; hi2 < histMatches.length; hi2++) {
                var hItem2 = histMatches[hi2];
                newResults.push({
                    name: "📋 " + hItem2.text,
                    description: "Historial — " + hItem2.count + " vez" + (hItem2.count !== 1 ? "es" : ""),
                    icon: Icons.notepad,
                    type: "history",
                    historyText: hItem2.text,
                    exec: null
                });
            }
        }

        // 1. Apps (ordenadas por uso — las que más abres primero)
        const appResults = AppSearch.fuzzyQuery(query);
        var seenIds = {};
        for (const a of appResults.slice(0, 6)) {
            if (seenIds[a.id]) continue;
            seenIds[a.id] = true;
            newResults.push({
                name: a.name,
                description: a.comment || a.id || "",
                icon: a.icon,
                type: "app",
                exec: () => {
                    UsageTracker.recordUsage(a.id);
                    a.execute();
                    Visibilities.setActiveModule("");
                }
            });
        }

        // 2. Web search
        newResults.push({
            name: `Buscar "${searchText}" en web`,
            description: "Abrir en Zen Browser",
            icon: Icons.globe,
            type: "web",
            exec: () => {
                Qt.openUrlExternally(`https://www.google.com/search?q=${encodeURIComponent(searchText)}`);
                Visibilities.setActiveModule("");
            }
        });

        // ── Opción de modo desarrollador (debug) ──
        // Aparece como resultado al escribir "d" / "dev" / "debug".
        // Solo entra al modo debug al pulsar Enter sobre esta opción.
        // Se coloca al PRINCIPIO de la lista (arriba) para entrar rápido con Enter.
        if (query === "d" || query === "dev" || query === "debug") {
            newResults.unshift({
                name: "🐞 Modo desarrollador (debug)",
                description: "Ver errores, tiempos y recursos de Hax en pantalla",
                icon: Icons.notepad,
                type: "debug",
                exec: function() {
                    spotlight.showDebug = true;
                }
            });
        }

        // ── Live Text: estado / reindexar ──
        if (query === "live" || query === "livetext" || query === "estado" || query === "status" || query === "ocr") {
            var ltDesc = spotlight.liveTextIndexing
                ? "⏳ Indexando imágenes en segundo plano…"
                : (spotlight.liveTextIndexed + " imágenes indexadas — busca palabras escritas dentro de tus fotos/capturas");
            newResults.unshift({
                name: "🖼️ Live Text (OCR)",
                description: ltDesc,
                icon: Icons.notepad,
                type: "info",
                exec: function() {
                    spotlight.startOcrIndexing();
                }
            });
        }
        if (query === "reindexar" || query === "reindex") {
            newResults.unshift({
                name: "🖼️ Reindexar imágenes (Live Text)",
                description: "Vuelve a leer el texto de todas tus imágenes con OCR (Tesseract)",
                icon: Icons.notepad,
                type: "info",
                exec: function() {
                    spotlight.startOcrIndexing();
                }
            });
        }

        // Asignar para que QML detecte el cambio
        results = newResults;

        // 3. Archivos (se añaden después asincronamente)
        if (query.length >= 2) {
            startFileSearch(query);
        }
    }

    // ── Evaluador aritmético seguro ────────────────────────────────────────
    function safeEval(expr) {
        if (!/^[\d+\-*/().\s]+$/.test(expr)) return null;
        try {
            return calcParens(expr.replace(/\s/g, ""));
        } catch(e) { return null; }
    }

    // Evalúa expresión sin paréntesis (solo + - * / y números)
    function calcSimple(e) {
        if (e.length === 0) return null;
        // Primero */, luego +-
        var idx;
        // Multiplicación y división
        idx = e.indexOf("*");
        if (idx > 0) {
            var l = calcSimple(e.substring(0, idx));
            var r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l * r;
        }
        idx = e.indexOf("/");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null || r === 0) return null;
            return l / r;
        }
        // Suma y resta
        idx = e.indexOf("+");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l + r;
        }
        // Para resta, buscar desde el final para manejar negativos
        // Si hay - en posición 0, es un número negativo
        if (e.charAt(0) === "-") {
            // Número negativo
            var rest = calcSimple(e.substring(1));
            return rest === null ? null : -rest;
        }
        idx = e.lastIndexOf("-");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l - r;
        }
        // Número simple
        var num = parseFloat(e);
        return isNaN(num) ? null : num;
    }

    // Maneja paréntesis recursivamente
    function calcParens(e) {
        var start = e.indexOf("(");
        while (start !== -1) {
            var depth = 1;
            var end = start + 1;
            while (end < e.length && depth > 0) {
                if (e.charAt(end) === "(") depth++;
                else if (e.charAt(end) === ")") depth--;
                end++;
            }
            if (depth !== 0) return null;
            var inner = calcParens(e.substring(start + 1, end - 1));
            if (inner === null) return null;
            e = e.substring(0, start) + inner + e.substring(end);
            start = e.indexOf("(");
        }
        return calcSimple(e);
    }

    function executeSelected() {
        if (selectedIndex >= 0 && selectedIndex < results.length) {
            executeItem(results[selectedIndex]);
        }
    }

    function executeItem(item) {
        if (item && item.exec) {
            try {
                item.exec();
            } catch (e) {
                spotlight.debugLogError("executeItem", e);
            }
        }
    }

    // Previsualiza (Quick Look) el archivo actualmente resaltado, si lo es.
    // Se usa al navegar con las flechas del teclado, para no depender del ratón.
    function _previewSelectedIfFile() {
        if (selectedIndex >= 0 && selectedIndex < results.length) {
            var sel = results[selectedIndex];
            if (sel && sel.type === "file") {
                var p = sel.description || "";
                if (p && p !== spotlight.previewPath) openPreview(sel);
            }
        }
    }

    // ── Live Text (OCR) ────────────────────────────────────────────────────
    // Carpetas que se indexan en background al iniciar Hax.
    function ocrFolders() {
        var home = Quickshell.env("HOME") || "/home/fabio";
        var pics = Quickshell.env("XDG_PICTURES_DIR") || (home + "/Pictures");
        var shots = pics + "/Screenshots";
        return [
            { d: home + "/Documentos", depth: 5 },
            { d: home + "/Descargas",   depth: 5 },
            { d: home + "/Escritorio",  depth: 5 },
            { d: home,                  depth: 2 },
            { d: pics,                  depth: 6 },
            { d: shots,                 depth: 2 }
        ];
    }

    // Indexa las imágenes en segundo plano (una carpeta a la vez, no bloquea la UI).
    function startOcrIndexing() {
        var folders = ocrFolders();
        spotlight.liveTextIndexing = true;
        spotlight.liveTextPending = folders.length;
        for (var i = 0; i < folders.length; i++) {
            (function(f) {
                var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                pr.command = ["bash", ocrScript, "index", f.d, String(f.depth)];
                pr.onExited.connect(function() {
                    try { pr.destroy(); } catch (e) {}
                    spotlight.liveTextPending = spotlight.liveTextPending - 1;
                    if (spotlight.liveTextPending <= 0) {
                        spotlight.liveTextIndexing = false;
                        spotlight.refreshLiveTextStatus();
                    }
                });
                pr.running = true;
            })(folders[i]);
        }
    }

    // Actualiza el contador de imágenes indexadas (Live Text).
    function refreshLiveTextStatus() {
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', spotlight);
        pr.command = ["bash", ocrScript, "status"];
        pr.onExited.connect(function() {
            var t = (pr.stdout ? pr.stdout.text : "").trim();
            var n = parseInt(t, 10);
            spotlight.liveTextIndexed = isNaN(n) ? 0 : n;
            try { pr.destroy(); } catch (e) {}
        });
        pr.running = true;
    }

    // Lee el texto OCR de una imagen para el panel de previsualización.
    function fetchOcrForPreview(p) {
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', spotlight);
        pr.command = ["bash", ocrScript, "get", p];
        pr.onExited.connect(function() {
            var t = pr.stdout ? pr.stdout.text.trim() : "";
            spotlight.previewOcrText = (t.length > 0) ? t : "（sin texto detectable en la imagen）";
            try { pr.destroy(); } catch (e) {}
        });
        pr.running = true;
    }

    // Copia al portapapeles el texto OCR de la imagen previsualizada.
    function copyOcrText() {
        if (!spotlight.previewOcrText) return;
        var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        p.command = ["wl-copy", spotlight.previewOcrText];
        p.onExited.connect(function() { try { p.destroy(); } catch (e) {} });
        p.running = true;
    }

    // ── Previsualización rápida (Quick Look) ─────────────────────────────
    // Al pulsar Enter/clic sobre un archivo, muestra su contenido DENTRO de
    // Hax (ruta + texto/imagen) sin cerrar el buscador.
    function openPreview(item) {
        if (!item || item.type !== "file") return;
        var path = item.description || "";
        if (!path) return;

        spotlight.previewPath = path;
        spotlight.previewName = item.name || (path.split("/").pop());
        spotlight.previewType = "text";
        spotlight.previewText = "Cargando…";
        spotlight.previewImageSrc = "";
        spotlight.previewOcrText = "";
        spotlight.showPreview = true;

        var safePath = path.replace(/'/g, "'\\''");

        // Imágenes: mostrar directamente (layer.enabled evita el bug de Quickshell
        // que dibuja el Image file:// en (0,0) de la ventana).
        if (path.match(/\.(png|jpe?g|gif|bmp|webp|svg)$/i)) {
            spotlight.previewType = "image";
            spotlight.previewImageSrc = "file://" + path;
            spotlight.previewText = "";
            spotlight.previewOcrText = "📝 Leyendo texto de la imagen…";
            spotlight.fetchOcrForPreview(path);
            return;
        }

        // Texto/binario: leer con cat, detectando binarios
        var proc;
        try {
            proc = Qt.createQmlObject(
                'import Quickshell.Io; Process { stdout: SplitParser {} }',
                spotlight
            );
        } catch (e) {
            spotlight.debugLogError("openPreview", e);
            return;
        }
        var lines = [];
        proc.stdout.onRead.connect(function(d) { lines.push(d); });
        proc.onExited.connect(function() {
            var joined = lines.join("");
            if (joined.indexOf("__BINARY__") !== -1) {
                spotlight.previewType = "binary";
                spotlight.previewText = "🔒 Archivo binario — no se puede previsualizar el contenido de texto.";
            } else {
                spotlight.previewType = "text";
                spotlight.previewText = joined;
            }
            proc.destroy();
        });
        proc.command = ["bash", "-c",
            "if file --mime-encoding -- '" + safePath + "' 2>/dev/null | grep -qi binary; then echo '__BINARY__'; else cat -- '" + safePath + "' 2>/dev/null | head -c 200000; fi"];
        proc.running = true;
    }

    function copyResult(item) {
        if (!item) return;
        var p;
        try {
            p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        } catch (e) {
            spotlight.debugLogError("copyResult", e);
            return;
        }
        var copyText = "";
        if (item.type === "file") {
            var path = item.description || "";
            copyText = path;
            // Si es imagen, copiar la imagen al portapapeles
            if (path.match(/\.(png|jpg|jpeg|gif|bmp|webp|svg)$/i)) {
                p.command = ["bash", "-c", "wl-copy < " + path.replace(/'/g, "'\\''")];
            } else {
                p.command = ["wl-copy", path];
            }
        } else if (item.type === "calc") {
            var parts = (item.name || "").split(" = ");
            copyText = parts.length > 1 ? parts[1] : parts[0];
            p.command = ["wl-copy", copyText];
        } else if (item.type === "history") {
            // Items del historial: copiar el texto guardado
            copyText = item.historyText || item.name || "";
            p.command = ["wl-copy", copyText];
        } else {
            copyText = item.name || "";
            p.command = ["wl-copy", copyText];
        }
        p.onExited.connect(() => p.destroy());
        p.running = true;
        // Guardar en el historial inteligente
        saveToHistory(copyText, item.type || "text");
        // Marcar para que el vigilante del portapapeles no lo cuente doble
        _lastClipboard = copyText;
        // Feedback visual
        _copyFeedback = item.name || copyText || "";
        _copyFeedbackTimer.restart();
    }

    property string _copyFeedback: ""

    // ── Previsualización rápida (Quick Look) ───────────────────────────────
    property bool showPreview: false
    property string previewPath: ""
    property string previewName: ""
    property string previewType: ""    // "image" | "text" | "binary"
    property string previewText: ""
    property string previewImageSrc: ""

    // ── Historial inteligente ──────────────────────────────────────────────
    property var _historyItems: []
    property var _historyLoaded: false
    property string _lastClipboard: ""
    property var _clipTimer: null

    function loadHistory() {
        if (_historyLoaded) return;
        var path = Quickshell.env("HOME") + "/.local/share/hax/history.json";
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        proc.command = ["bash", "-c", "cat " + path + " 2>/dev/null || echo '[]'"];
        var lines = [];
        proc.stdout.onRead.connect(function(data) {
            lines.push(data);
        });
        proc.onExited.connect(function() {
            try {
                _historyItems = JSON.parse(lines.join("")) || [];
            } catch(e) {
                _historyItems = [];
            }
            _historyLoaded = true;
            proc.destroy();
        });
        proc.running = true;
    }

    function saveToHistory(text, type) {
        if (!text || text.length === 0) return;
        // Buscar si ya existe
        var idx = -1;
        for (var i = 0; i < _historyItems.length; i++) {
            if (_historyItems[i].text === text) {
                idx = i;
                break;
            }
        }
        var now = new Date().toISOString();
        if (idx >= 0) {
            _historyItems[idx].count = (_historyItems[idx].count || 1) + 1;
            _historyItems[idx].lastUsed = now;
        } else {
            _historyItems.unshift({
                text: text,
                type: type || "text",
                count: 1,
                lastUsed: now
            });
            // Máximo 50 items
            if (_historyItems.length > 50) _historyItems.pop();
        }
        // Ordenar: más usado primero, luego más reciente
        _historyItems.sort(function(a, b) {
            if (a.count !== b.count) return b.count - a.count;
            return b.lastUsed.localeCompare(a.lastUsed);
        });
        // Guardar a disco
        _writeHistory();
    }

    function _writeHistory() {
        var json = JSON.stringify(_historyItems);
        var path = Quickshell.env("HOME") + "/.local/share/hax/history.json";
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        // Usar Python para escribir el archivo JSON de forma segura (como hace Ambxst)
        var pyCode = "import json,sys,pathlib; pathlib.Path(sys.argv[1]).parent.mkdir(parents=True,exist_ok=True); pathlib.Path(sys.argv[1]).write_text(sys.argv[2])";
        proc.command = ["python3", "-c", pyCode, path, json];
        proc.onExited.connect(function() {
            proc.destroy();
        });
        proc.running = true;
    }

    function removeFromHistory(text) {
        if (!text) return;
        for (var i = 0; i < _historyItems.length; i++) {
            if (_historyItems[i].text === text) {
                _historyItems.splice(i, 1);
                break;
            }
        }
        _writeHistory();
        // Refrescar la lista de resultados para que desaparezca
        selectedIndex = 0;
        updateResults();
    }

    // ── Vigilante del portapapeles ─────────────────────────────────────────
    // Guarda en el historial TODO lo que copies, venga de donde venga
    function _readClipboard(cb) {
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { stdout: SplitParser {} }', spotlight);
        var lines = [];
        proc.stdout.onRead.connect(function(d) { lines.push(d); });
        proc.onExited.connect(function() {
            var content = lines.join("\n").trim();
            proc.destroy();
            if (cb) cb(content);
        });
        // -n = no añade salto de línea final; si está vacío, devuelve error y se ignora
        proc.command = ["wl-paste", "-n"];
        proc.running = true;
    }

    function startClipWatcher() {
        if (_clipTimer !== null) return;
        // Capturar el contenido actual (al abrir Hax)
        _readClipboard(function(content) {
            if (content.length > 0 && content.length < 100000) {
                _lastClipboard = content;
                saveToHistory(content, "text");
            }
        });
        // Polling cada 1.5s para detectar cambios
        _clipTimer = Qt.createQmlObject('import QtQuick; Timer { }', spotlight);
        _clipTimer.interval = 1500;
        _clipTimer.repeat = true;
        _clipTimer.triggered.connect(function() {
            _readClipboard(function(content) {
                if (content.length > 0 && content.length < 100000 && content !== _lastClipboard) {
                    _lastClipboard = content;
                    saveToHistory(content, "text");
                }
            });
        });
        _clipTimer.start();
    }

    function stopClipWatcher() {
        if (_clipTimer !== null) {
            _clipTimer.stop();
            _clipTimer.destroy();
            _clipTimer = null;
        }
        _lastClipboard = "";
    }

    function searchHistory(query, maxResults) {
        if (!_historyItems || _historyItems.length === 0) return [];
        if (!query || query.length === 0) {
            // Sin query: devolver todos (o hasta maxResults si se especifica)
            if (maxResults && maxResults > 0) {
                return _historyItems.slice(0, maxResults);
            }
            return _historyItems;
        }
        var q = query.toLowerCase();
        var results = [];
        var limit = maxResults || 3;
        for (var i = 0; i < _historyItems.length; i++) {
            var item = _historyItems[i];
            if (item.text.toLowerCase().indexOf(q) !== -1) {
                results.push(item);
                if (results.length >= limit) break;
            }
        }
        return results;
    }

    // ── Búsqueda de archivos ───────────────────────────────────────────────
    property var currentSearch: null

    function startFileSearch(query) {
        if (query.length < 2) return;
        
        // Guardar la generación actual para evitar resultados obsoletos
        var gen = searchGeneration;
        
        // Cancelar búsqueda anterior si aún corre
        if (currentSearch) {
            currentSearch.running = false;
            currentSearch.destroy();
            currentSearch = null;
        }
        
        const home = Quickshell.env("HOME") || "/home/fabio";
        // Quitar caracteres problemáticos del query para el glob de find
        const q = query.replace(/[^a-zA-Z0-9\u00C0-\u024F\u0400-\u04FF_.-\s]/g, "");
        if (q.length < 2) return;
        
        // Crear el proceso de find
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }', 
            spotlight
        );
        proc.command = [
            "find",
            home + "/Documentos",
            home + "/Descargas",
            home + "/Escritorio",
            home,
            "-maxdepth", "4",
            "-iname", "*" + q + "*",
            "-type", "f"
        ];
        
        var fileAccum = [];
        proc.stdout.onRead.connect(function(data) {
            // Si la generación cambió, estos resultados ya no sirven
            if (gen !== searchGeneration) return;
            var line = data.trim();
            if (line.length === 0) return;
            var fname = line.split("/").pop();
            // Comprobar duplicados en el mismo batch
            var isDup = false;
            for (var fi = 0; fi < fileAccum.length; fi++) {
                if (fileAccum[fi].name === fname) { isDup = true; break; }
            }
            if (!isDup && fileAccum.length < 3) {
                var capturedLine = line;
                fileAccum.push({
                    name: fname,
                    description: capturedLine,
                    icon: Icons.file,
                    type: "file",
                    exec: function() {
                        // Mismo patrón que AppSearch.runInActiveWorkspace (funciona siempre)
                        var safePath = capturedLine.replace(/'/g, "'\\''");
                        var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                        p.command = ["bash", "-c",
                            "cd ~ && env -u HL_INITIAL_WORKSPACE_TOKEN setsid thunar '" + safePath + "' < /dev/null > /dev/null 2>&1 &"];
                        p.onExited.connect(() => p.destroy());
                        p.running = true;
                        Visibilities.setActiveModule("");
                    }
                });
            }
        });
        
        proc.onExited.connect(function(code) {
            // Si la generación cambió, descartar resultados obsoletos
            if (gen !== searchGeneration) {
                proc.destroy();
                if (currentSearch === proc) currentSearch = null;
                return;
            }
            if (fileAccum.length > 0) {
                // Crear copia + nuevos resultados para que QML detecte el cambio
                results = results.concat(fileAccum);
            }
            proc.destroy();
            if (currentSearch === proc) currentSearch = null;
        });
        
        currentSearch = proc;
        proc.running = true;

        // ── Live Text: también buscar en el texto de las imágenes (OCR) ──
        (function() {
            var ocrPr = Qt.createQmlObject(
                'import Quickshell.Io; Process { stdout: StdioCollector {} }',
                spotlight
            );
            ocrPr.command = ["bash", ocrScript, "search", q];
            ocrPr.onExited.connect(function() {
                if (gen !== searchGeneration) { try { ocrPr.destroy(); } catch (e) {} return; }
                var out = (ocrPr.stdout ? ocrPr.stdout.text : "") || "";
                var lines = out.split("\n");
                var ocrRes = [];
                for (var li = 0; li < lines.length; li++) {
                    var ln = lines[li].trim();
                    if (ln.length === 0) continue;
                    var parts = ln.split(ocrSep);
                    if (parts.length < 2) continue;
                    var p = parts[0];
                    var snip = parts.slice(1).join(" ").trim();
                    if (p.length === 0) continue;
                    var fname = p.split("/").pop();
                    // Si el nombre ya contiene la query, el buscador de archivos
                    // (find) ya lo mostrará → evitamos duplicados.
                    if (fname.toLowerCase().indexOf(q) !== -1) continue;
                    var dup = false;
                    for (var ri = 0; ri < results.length; ri++) {
                        if (results[ri].description === p) { dup = true; break; }
                    }
                    if (dup) continue;
                    (function(pp, sn, fn) {
                        ocrRes.push({
                            name: "🖼️ " + fn,
                            description: pp,
                            icon: "🖼️",
                            type: "file",
                            ocrMatch: true,
                            exec: function() {
                                var safePath = pp.replace(/'/g, "'\\''");
                                var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                                pr.command = ["bash", "-c",
                                    "cd ~ && env -u HL_INITIAL_WORKSPACE_TOKEN setsid thunar '" + safePath + "' < /dev/null > /dev/null 2>&1 &"];
                                pr.onExited.connect(function() { try { pr.destroy(); } catch (e) {} });
                                pr.running = true;
                                Visibilities.setActiveModule("");
                            }
                        });
                    })(p, snip, fname);
                }
                if (ocrRes.length > 0) results = results.concat(ocrRes);
                try { ocrPr.destroy(); } catch (e) {}
            });
            ocrPr.running = true;
        })();
    }

    // ── Clima ────────────────────────────────────────────────────────────────
    function startWeatherSearch(location, gen) {
        if (weatherSearch) {
            weatherSearch.running = false;
            weatherSearch.destroy();
            weatherSearch = null;
        }

        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );

        // Usar ubicación por defecto si no se especificó una
        var loc = location || WeatherService.defaultLocation;
        var url = "https://wttr.in/" + encodeURIComponent(loc) + "?format=j1";

        proc.command = ["bash", "-c", "curl -s --max-time 6 '" + url.replace(/'/g, "'\\''") + "'"];

        var lines = [];
        proc.stdout.onRead.connect(function(data) {
            if (gen !== searchGeneration) return;
            var line = data.trim();
            if (line.length > 0) lines.push(line);
        });

        proc.onExited.connect(function(code) {
            if (gen !== searchGeneration) {
                proc.destroy();
                if (weatherSearch === proc) weatherSearch = null;
                return;
            }

            if (code === 0 && lines.length > 0) {
                try {
                    var json = JSON.parse(lines.join(""));
                    results = formatWeatherResults(json, loc);
                } catch(e) {
                    results = [{
                        name: "❌ Error al procesar datos",
                        description: loc || "Intenta con otra ubicación",
                        type: "info"
                    }];
                }
            } else {
                results = [{
                    name: "❌ No se pudo obtener el clima",
                    description: loc
                        ? "Revisa el nombre de la ubicación o tu conexión"
                        : "Revisa tu conexión a internet",
                    type: "info"
                }];
            }
            proc.destroy();
            if (weatherSearch === proc) weatherSearch = null;
        });

        weatherSearch = proc;
        proc.running = true;
    }

    function formatWeatherResults(json, location) {
        var res = [];
        var current = json.current_condition && json.current_condition[0];
        var area = json.nearest_area && json.nearest_area[0];
        var forecast = json.weather || [];

        if (!current) {
            res.push({ name: "❌ No hay datos", description: "Prueba otra ubicación", type: "info" });
            return res;
        }

        var city = area ? area.areaName[0].value : (location || "Ubicación actual");
        var country = area ? area.country[0].value : "";
        var locStr = city + (country ? ", " + country : "");

        var desc = (current.weatherDesc && current.weatherDesc[0]) ? current.weatherDesc[0].value : "";
        var tempC = current.temp_C || "?";
        var feelsLike = current.FeelsLikeC || "?";
        var humidity = current.humidity || "?";
        var wind = current.windspeedKmph || "?";
        var windDir = current.winddir16Point || "";

        // Emoji según condición
        var emoji = "🌤️";
        var d = desc.toLowerCase();
        if (d.includes("sunny") || d.includes("clear")) emoji = "☀️";
        else if (d.includes("partly")) emoji = "⛅";
        else if (d.includes("cloud") && !d.includes("partly")) emoji = "☁️";
        else if (d.includes("rain") || d.includes("drizzle") || d.includes("shower")) emoji = "🌧️";
        else if (d.includes("thunder") || d.includes("storm")) emoji = "⛈️";
        else if (d.includes("snow") || d.includes("sleet") || d.includes("ice")) emoji = "❄️";
        else if (d.includes("fog") || d.includes("mist") || d.includes("haze")) emoji = "🌫️";
        else if (d.includes("overcast")) emoji = "☁️";

        // Resultado principal
        res.push({
            name: emoji + " " + tempC + "°C  " + desc + "  —  " + locStr,
            description: "Sensación: " + feelsLike + "°C · Humedad: " + humidity + "% · Viento: " + wind + " km/h " + windDir,
            icon: Icons.globe,
            type: "info",
            exec: function() {
                Qt.openUrlExternally("https://wttr.in/" + encodeURIComponent(city));
                Visibilities.setActiveModule("");
            }
        });

        // Pronóstico próximos días
        for (var fi = 0; fi < Math.min(forecast.length, 3); fi++) {
            var day = forecast[fi];
            if (!day.date) continue;
            var dateObj = new Date(day.date);
            var dayNames = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
            var dayName = dayNames[dateObj.getDay()] || "";
            var maxT = day.maxtempC || "?";
            var minT = day.mintempC || "?";
            res.push({
                name: dayName + " · " + "↗ " + maxT + "°C  ↘ " + minT + "°C",
                description: "",
                type: "info",
                icon: Icons.apps
            });
        }

        return res;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  TIMERS
    // ═════════════════════════════════════════════════════════════════════

    function _fmtDur(totalSec) {
        if (totalSec >= 3600) {
            var h = Math.floor(totalSec / 3600);
            var m = Math.floor((totalSec % 3600) / 60);
            return h + "h " + (m < 10 ? "0" : "") + m + "m";
        } else if (totalSec >= 60) {
            var mm = Math.floor(totalSec / 60);
            var ss = totalSec % 60;
            return mm + ":" + (ss < 10 ? "0" : "") + ss;
        }
        return totalSec + "s";
    }

    function startTimer(label, seconds) {
        if (seconds <= 0) return null;
        var tId = _timerNextId++;
        var t = {
            id: tId,
            label: label || ("Timer " + tId),
            totalSeconds: seconds,
            endTime: Date.now() + seconds * 1000,
            createdAt: new Date().toLocaleTimeString()
        };
        var arr = activeTimers.slice();
        arr.push(t);
        activeTimers = arr;
        return t;
    }

    function cancelTimer(target) {
        if (typeof target === 'number') {
            activeTimers = activeTimers.filter(function(t) { return t.id !== target; });
        } else if (typeof target === 'string') {
            activeTimers = activeTimers.filter(function(t) { return t.label !== target; });
        }
    }

    function clearAllTimers() {
        activeTimers = [];
    }

    function tickTimers() {
        if (activeTimers.length === 0) return;
        var now = Date.now();
        var keep = [];
        var done = [];
        for (var i = 0; i < activeTimers.length; i++) {
            var t = activeTimers[i];
            if (now >= t.endTime) {
                done.push(t);
            } else {
                keep.push(t);
            }
        }
        if (done.length > 0) {
            activeTimers = keep;
            for (var j = 0; j < done.length; j++) {
                _notifyTimerDone(done[j]);
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  NOTIFICACIONES INLINE
    // ═════════════════════════════════════════════════════════════════════

    function addHaxNotification(type, label, body, notifObj) {
        var nid = _haxNotifIdCounter++;
        var entry = {
            id: nid,
            type: type,
            label: label,
            body: body,
            ts: Date.now(),
            icon: type === "timer" ? "⏰" : "🔔",
            notifObj: notifObj
        };
        var arr = _haxNotifications.slice();
        arr.push(entry);
        _haxNotifications = arr;

        if (!showHax) {
            Visibilities.setActiveModule("spotlight");
        }
    }

    function _dismissHaxNotif(id) {
        _haxNotifications = _haxNotifications.filter(function(n) { return n.id !== id; });
    }

    function _notifyTimerDone(t) {
        addHaxNotification("timer", t.label || "Timer",
            "Finalizado — " + _fmtDur(t.totalSeconds), t
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    //  ALARMAS
    // ═════════════════════════════════════════════════════════════════════

    function setAlarm(label, hour, minute, days) {
        var aId = _alarmNextId++;
        var a = {
            id: aId,
            label: label || ("Alarma " + aId),
            hour: hour,
            minute: minute,
            days: days || [],
            enabled: true,
            lastTriggered: null
        };
        var arr = activeAlarms.slice();
        arr.push(a);
        activeAlarms = arr;
        return a;
    }

    function cancelAlarm(target) {
        if (typeof target === 'number') {
            activeAlarms = activeAlarms.filter(function(a) { return a.id !== target; });
        } else if (typeof target === 'string') {
            activeAlarms = activeAlarms.filter(function(a) { return a.label !== target; });
        }
    }

    function clearAllAlarms() {
        activeAlarms = [];
    }

    function checkAlarms() {
        if (activeAlarms.length === 0) return;
        var now = new Date();
        var h = now.getHours();
        var m = now.getMinutes();
        var day = now.getDay();
        for (var i = 0; i < activeAlarms.length; i++) {
            var a = activeAlarms[i];
            if (!a.enabled) continue;
            if (a.hour !== h || a.minute !== m) continue;
            if (a.days.length > 0 && a.days.indexOf(day) < 0) continue;
            var key = now.toDateString() + " " + h + ":" + m;
            if (a.lastTriggered === key) continue;
            a.lastTriggered = key;
            _notifyAlarm(a);
        }
    }

    function _notifyAlarm(a) {
        var daysStr = a.days.length > 0 ? a.days.map(function(d) {
            return ["Dom","Lun","Mar","Mié","Jue","Vie","Sáb"][d];
        }).join(" ") : "Todos los días";
        var timeStr = (a.hour < 10 ? "0" : "") + a.hour + ":" + (a.minute < 10 ? "0" : "") + a.minute;
        addHaxNotification("alarm", a.label || "Alarma",
            timeStr + " — " + daysStr, a
        );
    }

    // ═════════════════════════════════════════════════════════════════════
    //  BÚSQUEDA DE PAQUETES
    // ═════════════════════════════════════════════════════════════════════

    function _cancelPkgSearch() {
        for (var pi = 0; pi < _pkgSearchProcesses.length; pi++) {
            var p = _pkgSearchProcesses[pi];
            if (p) { p.running = false; p.destroy(); }
        }
        _pkgSearchProcesses = [];
        _lastSearchQuery = "";
    }

    function _searchPackages(query, gen) {
        _cancelPkgSearch();
        var safeQ = query.replace(/'/g, "'\\''");

        // Un solo proceso con los 3 gestores secuenciales
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { stdout: SplitParser {} }', spotlight);
        proc.command = ["bash", "-c",
            "echo '===PACMAN==='; timeout 15 pacman -Ss '" + safeQ + "' 2>/dev/null | head -30"
            + "; echo '===YAY==='; timeout 20 yay -Ss '" + safeQ + "' 2>/dev/null | head -30"
            + "; echo '===FLATPAK==='; timeout 15 flatpak search '" + safeQ + "' 2>/dev/null | head -15"
        ];
        var rawLines = [];
        proc.stdout.onRead.connect(function(data) {
            if (gen !== searchGeneration) return;
            // SplitParser emite cada línea sin \n, añadimos separador
            rawLines.push(data);
        });
        proc.onExited.connect(function() {
            proc.destroy();
            if (gen !== searchGeneration) return;

            var section = "";
            var newRes = [];
            var seenPkg = {}; // "nombre" → true (evita duplicados entre gestores)

            function addPkg(nombre, descripcion, gestor, comando) {
                var key = nombre + "|" + gestor;
                if (seenPkg[key]) return;
                seenPkg[key] = true;
                newRes.push({
                    name: "📦 " + nombre + " (" + gestor + ")",
                    description: descripcion || gestor,
                    icon: Icons.notepad, type: "info",
                    exec: function() {
                        runCmd(comando);
                    }
                });
            }

            for (var i = 0; i < rawLines.length; i++) {
                var l = rawLines[i];

                // Detectar cambio de sección
                if (l === "===PACMAN===") { section = "pacman"; continue; }
                if (l === "===YAY===") { section = "yay"; continue; }
                if (l === "===FLATPAK===") { section = "flatpak"; continue; }
                if (!l.trim()) continue;

                if (section === "flatpak") {
                    // flatpak search: "appid\tnombre\tsummary..."
                    if (l.indexOf("\t") >= 0) {
                        var fp = l.split("\t");
                        var fId = (fp[0] || "").trim();
                        var fName = (fp[1] || "").trim();
                        var fDesc = (fp[2] || "").trim();
                        // Usar nombre legible si existe
                        var pkgName = fName || fId.split(".").pop() || fId;
                        var pkgDesc = fDesc || fId;
                        addPkg(pkgName, pkgDesc, "flatpak",
                            "flatpak install -y flathub " + fId);
                    }
                } else if (section === "pacman" || section === "yay") {
                    // pacman -Ss: "repo/nombre version ..."
                    var m = l.match(/^(\S+)\/(\S+)\s/);
                    if (m) {
                        var repo = m[1];
                        var pkg = m[2];
                        // Obtener descripción de la siguiente línea (indentada)
                        var desc = "";
                        if (i + 1 < rawLines.length) {
                            var next = rawLines[i + 1];
                            if (next.length > 0 && next.charAt(0) === ' ') {
                                desc = next.trim();
                                i++;
                            }
                        }
                        var gestor = section === "pacman" ? "pacman" : "AUR/yay";
                        var sudoP = section === "pacman" ? "pacman" : "";
                        addPkg(pkg, desc, gestor,
                            sudoP
                                ? "echo 'F200607' | sudo -S " + sudoP + " -S --noconfirm " + pkg
                                : "yay -S --noconfirm " + pkg);
                    }
                }
            }

            if (newRes.length === 0) {
                newRes.push({ name: "📦 No se encontraron paquetes para «" + query + "»", description: "Prueba con: pacman, yay o flatpak directamente", icon: Icons.notepad, type: "info", exec: null });
            }
            results = newRes;
            _pkgSearchProcesses = [];
        });
        _pkgSearchProcesses = [proc];
        proc.running = true;
    }

    function _searchFlatpak(query, gen) {
        _cancelPkgSearch();

        var allPkgs = [];
        var safeQ = query.replace(/'/g, "'\\''");

        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        proc.command = ["bash", "-c", "flatpak search '" + safeQ + "' 2>/dev/null | head -10"];
        var out = "";
        proc.stdout.onRead.connect(function(data) { if (gen === searchGeneration) out += data; });
        proc.onExited.connect(function() {
            proc.destroy();
            if (gen !== searchGeneration) return;
            var lines = out.split("\n");
            for (var fi = 0; fi < lines.length; fi++) {
                var line = lines[fi].trim();
                if (!line || line.indexOf("\t") < 0) continue;
                var fpParts = line.split("\t");
                var fpName = (fpParts[0] || "").trim();
                var fpDesc = (fpParts[1] || "").trim();
                if (!fpName) continue;
                (function(cName, cDesc) {
                    allPkgs.push({
                        name: "📦 " + cName + " (flatpak)",
                        description: cDesc || "Flatpak",
                        icon: Icons.notepad, type: "info",
                        exec: function() { runCmd('flatpak install -y flathub ' + cName); }
                    });
                })(fpName, fpDesc);
            }
            if (allPkgs.length > 0) {
                results = allPkgs;
            } else {
                results = [{ name: "📦 No se encontraron paquetes en Flathub", description: "Prueba con: flatpak install " + query, icon: Icons.notepad, type: "info", exec: null }];
            }
            _pkgSearchProcesses = [];
        });
        _pkgSearchProcesses = [proc];
        proc.running = true;
    }

}
