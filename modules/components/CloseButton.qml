pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.modules.theme

// ✕ Botón de cierre reutilizable para paneles de Hax
// Uso: CloseButton { onClicked: spanel.cerrar() }
Text {
    id: root

    required property var onClicked

    text: "✕"
    font.pixelSize: Config.theme.fontSize + 2
    font.bold: true
    color: Styling.srItem("text")
    opacity: 0.5

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.onClicked()
        onEntered: root.opacity = 1
        onExited: root.opacity = 0.5
    }
}
