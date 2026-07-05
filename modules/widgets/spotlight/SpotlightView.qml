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

    visible: spotlightOpen
    exclusionMode: ExclusionMode.Ignore

    // ── Input mask ───────────────────────────────────────────────────────────
    mask: Region {
        item: spotlightOpen ? fullMask : emptyMask
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
    property int selectedIndex: 0
    property var results: []
    property int searchGeneration: 0  // evita race conditions en async

    // ── Terminal integrada ─────────────────────────────────────────────────
    property var cmdProcess: null      // proceso de comando activo
    property var cmdOutput: []         // líneas de salida capturadas
    property string cmdOutputText: ""  // salida como texto plano (forza bindings en QML)
    readonly property bool isCommandMode: searchText.trim().startsWith("/")

    // ── Panel principal centrado ────────────────────────────────────────────
    Item {
        id: mainContainer
        anchors.centerIn: parent
        width: clampWidth()
        height: panelBg.height

        opacity: spotlightOpen ? 1 : 0
        scale: spotlightOpen ? 1 : 0.92

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutBack
                easing.overshoot: 1.1
            }
        }

        function clampWidth()  { return Math.min(620, screen.width  * 0.9) }

        // ── Fondo glassmorphism que se ajusta al contenido ──────────────────
        StyledRect {
            id: panelBg
            variant: "bg"
            width: parent.width
            height: 56 + 32
                + (cmdProcess !== null || isCommandMode
                    ? 8 + 36 + Math.min(cmdOutput.length * 20 + 20, 460)
                    : 0)
                + (results.length > 0 && !isCommandMode
                    ? 8 + Math.min(results.length * 54, 400)
                    : 0)
            radius: Styling.radius(24)
            clip: true

            Behavior on height {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration * 2
                    easing.type: Easing.OutCubic
                }
            }

            layer.enabled: true
            layer.effect: Shadow {}

            // ── Contenido interno ────────────────────────────────────────────
            Column {
                id: contentColumn
                width: parent.width
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                spacing: (results.length > 0 || cmdProcess !== null || isCommandMode) ? 8 : 0

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

                            onTextChanged: {
                                spotlight.searchText = text;
                                spotlight.selectedIndex = 0;
                                // Cancelar proceso al salir del modo comando
                                if (!text.trim().startsWith("/")) {
                                    spotlight.cancelCmdProcess();
                                }
                                spotlight.updateResults();
                            }

                            Keys.onEscapePressed: {
                                if (text.length > 0) {
                                    clear();
                                } else {
                                    Visibilities.setActiveModule("");
                                }
                            }

                            Keys.onReturnPressed: {
                                if (spotlight.isCommandMode && text.trim().length > 1) {
                                    var cmd = text.trim().substring(1); // quitar el /
                                    spotlight.runCmd(cmd);
                                } else {
                                    spotlight.executeSelected();
                                }
                            }

                            Keys.onUpPressed: {
                                if (spotlight.selectedIndex > 0) spotlight.selectedIndex--;
                            }

                            Keys.onDownPressed: {
                                if (spotlight.selectedIndex < spotlight.results.length - 1) spotlight.selectedIndex++;
                            }

                            // Tab → autocompletar con el primer resultado
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Tab && results.length > 0) {
                                    var completion = results[0].name || "";
                                    if (completion.length > searchText.length) {
                                        searchInput.text = completion;
                                        searchInput.cursorPosition = completion.length;
                                    }
                                    event.accepted = true;
                                }
                            }
                        }

                        // Preview inline de cálculo (como Spotlight)
                        Text {
                            id: calcPreview
                            text: {
                                if (spotlight.isCommandMode) return "";
                                var q = spotlight.searchText.trim();
                                if (q.length > 0 && /^[\d+\-*/().\s]+$/.test(q) && /[+\-*/]/.test(q)) {
                                    var r = spotlight.safeEval(q);
                                    if (r !== null && typeof r === "number") {
                                        return "= " + r;
                                    }
                                }
                                return "";
                            }
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize + 2
                            font.weight: Font.Medium
                            color: Colors.primary || Styling.srItem("overprimary")
                            opacity: 0.85
                            visible: text.length > 0
                            verticalAlignment: Text.AlignVCenter
                            Layout.alignment: Qt.AlignVCenter
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

                // ── Terminal integrada (modo comando /) ─────────────────────────
                StyledRect {
                    id: cmdContainer
                    width: contentColumn.width
                    height: isCommandMode || cmdProcess !== null
                        ? 36 + Math.min(cmdOutput.length * 20 + 20, 460)
                        : 0
                    variant: "pane"
                    radius: Styling.radius(12)
                    clip: true
                    opacity: (cmdProcess !== null || isCommandMode) ? 1 : 0
                    visible: opacity > 0

                    Behavior on height {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration * 2
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration
                            easing.type: Easing.OutCubic
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
                        }

                        // Salida del comando
                        Flickable {
                            width: parent.width
                            height: Math.min(cmdOutput.length * 20 + 8, 440)
                            contentHeight: cmdOutputText.length > 0
                                ? cmdOutput.length * 20 + 8
                                : 0
                            clip: true

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
                                width: 4
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    radius: 2
                                    color: Styling.srItem("overprimary")
                                    opacity: 0.3
                                }
                            }
                        }
                    }
                }

                // ── Lista de resultados (solo visible al escribir) ────────────
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
                            duration: Config.animDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    ListView {
                        id: resultsList
                        width: parent.width
                        height: parent.height

                        model: results
                        spacing: 2

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
                                hoverEnabled: true

                                onClicked: {
                                    spotlight.selectedIndex = index;
                                    spotlight.executeItem(modelData);
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

                                    // Icono Phosphor (para calc, web, archivos y fallback)
                                    Text {
                                        id: phosphorIcon
                                        anchors.centerIn: parent
                                        text: {
                                            switch (modelData.type) {
                                                case "calc":   return Icons.notepad;
                                                case "web":    return Icons.globe;
                                                case "file":   return Icons.file;
                                                case "action": return Icons.lightning;
                                                default:       return Icons.apps;
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
                                                case "action": return "⚡";
                                                default: return "";
                                            }
                                        }
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize - 4
                                        color: Styling.srItem("text")
                                        opacity: 0.5
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

                        // Scrollbar
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

        cmdOutput = [];
        cmdOutputText = "";

        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );

        proc.command = ["bash", "-c", cmd + " 2>&1"];
        proc.workingDirectory = Quickshell.env("HOME") || "/tmp";

        proc.stdout.onRead.connect(function(data) {
            var lines = data.trim().split("\n");
            var arr = cmdOutput.slice();
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].length > 0) arr.push(lines[i]);
            }
            cmdOutput = arr;
            cmdOutputText = arr.join("\n");
        });

        proc.onExited.connect(function(code) {
            var arr = cmdOutput.slice();
            arr.push("✦ Hecho (código: " + code + ")");
            cmdOutput = arr;
            cmdOutputText = arr.join("\n");
            cmdProcess = null;
            proc.destroy();
        });

        cmdProcess = proc;
        proc.running = true;
    }

    function cancelCmdProcess() {
        if (cmdProcess) {
            cmdProcess.running = false;
            cmdProcess.destroy();
            cmdProcess = null;
        }
        cmdOutput = [];
        cmdOutputText = "";
    }

    // ── Lógica de búsqueda ─────────────────────────────────────────────────

    function updateResults() {
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

        // Acciones rápidas del sistema
        const systemActions = [
            {
                match: q => /^(bloquea|lock|cerrar|traba)/.test(q),
                name: "🔒 Bloquear pantalla",
                description: "Bloquear la sesión ahora",
                icon: Icons.lock,
                exec: () => {
                    LockscreenService.lock();
                    Visibilities.setActiveModule("");
                }
            },
            {
                match: q => /^(apagar|shutdown|poweroff|off)/.test(q),
                name: "⏻ Apagar sistema",
                description: "Apagar el equipo completamente",
                icon: Icons.shutdown,
                exec: () => {
                    var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    p.command = ["bash", "-c", "systemctl poweroff"];
                    p.onExited.connect(() => p.destroy());
                    p.running = true;
                    Visibilities.setActiveModule("");
                }
            },
            {
                match: q => /^(reiniciar|reboot|reinicia|restart)/.test(q),
                name: "🔄 Reiniciar sistema",
                description: "Reiniciar el equipo",
                icon: Icons.sync,
                exec: () => {
                    var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    p.command = ["bash", "-c", "systemctl reboot"];
                    p.onExited.connect(() => p.destroy());
                    p.running = true;
                    Visibilities.setActiveModule("");
                }
            },
            {
                match: q => /^(suspender|sleep|suspend|hiber)/.test(q),
                name: "💤 Suspender",
                description: "Suspender el sistema",
                icon: Icons.moon,
                exec: () => {
                    var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    p.command = ["bash", "-c", "systemctl suspend"];
                    p.onExited.connect(() => p.destroy());
                    p.running = true;
                    Visibilities.setActiveModule("");
                }
            },
            {
                match: q => /^(captura|screenshot|pantallazo|grim)/.test(q),
                name: "📸 Captura de pantalla",
                description: "Capturar toda la pantalla",
                icon: Icons.camera,
                exec: () => {
                    var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    var dir = Quickshell.env("HOME") + "/Imágenes/Capturas";
                    p.command = ["bash", "-c", "mkdir -p '" + dir + "' && grim '" + dir + "/$(date +%s).png'"];
                    p.onExited.connect(() => p.destroy());
                    p.running = true;
                    Visibilities.setActiveModule("");
                }
            },
            {
                match: q => /^(captura.*(regi|área|area|sele)|screenshot.*(reg|area)|grim.*(slur|reg))/.test(q),
                name: "📐 Captura de región",
                description: "Seleccionar un área para capturar",
                icon: Icons.crop,
                exec: () => {
                    var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    var dir = Quickshell.env("HOME") + "/Imágenes/Capturas";
                    p.command = ["bash", "-c", "mkdir -p '" + dir + "' && grim -g \"$(slurp)\" '" + dir + "/$(date +%s).png'"];
                    p.onExited.connect(() => p.destroy());
                    p.running = true;
                    Visibilities.setActiveModule("");
                }
            }
        ];

        for (var si = 0; si < systemActions.length; si++) {
            if (systemActions[si].match(query)) {
                newResults.push({
                    name: systemActions[si].name,
                    description: systemActions[si].description,
                    icon: systemActions[si].icon,
                    type: "action",
                    exec: systemActions[si].exec
                });
            }
        }

        // 1. Apps
        const appResults = AppSearch.fuzzyQuery(query);
        for (const a of appResults.slice(0, 6)) {
            newResults.push({
                name: a.name,
                description: a.comment || a.id || "",
                icon: a.icon,  // ya viene validado por fuzzyQuery
                type: "app",
                exec: () => a.execute()
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
            item.exec();
        }
        Visibilities.setActiveModule("");
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
    }

    // ── Reset al abrirse ──────────────────────────────────────────────────
    onSpotlightOpenChanged: {
        if (spotlightOpen) {
            Qt.callLater(() => {
                searchInput.forceActiveFocus();
                searchInput.clear();
                searchText = "";
                selectedIndex = 0;
                cancelCmdProcess();
                updateResults();
            });
        }
    }
}
