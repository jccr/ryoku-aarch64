import QtQuick
import Ryoku.PluginKit.Singletons

// content/Widget.qml: the bar glyph. A keyboard mark, lit in the accent while the
// backlight is on and dim while it is off; a click only toggles the panel (a
// widget click never changes anything). Optionally shows the level beside it.
Item {
    id: root

    property var pluginApi
    property var screen
    property bool active: false
    property string density: "glyph"
    property real s: 1
    property real widthBudget: 0

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property bool available: service ? service.available : false
    readonly property int percent: service ? service.percent : 0
    readonly property bool lit: available && percent > 0
    readonly property bool showPercent: {
        const v = pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings.showPercent : undefined;
        return v === true;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, 18 * root.s)

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4 * root.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "keyboard"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 17 * root.s
            color: root.lit ? Theme.accent : Theme.iconDim
            opacity: root.available ? 1 : 0.45
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Text {
            visible: root.showPercent && root.available
            anchors.verticalCenter: parent.verticalCenter
            text: root.percent + "%"
            color: Theme.bright
            font.family: Theme.mono
            font.pixelSize: 11 * root.s
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.pluginApi) root.pluginApi.togglePanel()
    }
}
