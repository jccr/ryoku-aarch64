import QtQuick
import Ryoku.PluginKit.Singletons

// content/Panel.qml: the card under the glyph, laid out like Ryoku's own
// Brightness panel: a mono eyebrow with the level in the accent, a hairline,
// an 8 px track you click or drag, then step and preset buttons.
Item {
    id: root

    property var pluginApi
    property string density: "full"
    property real s: 1
    property real widthBudget: 320
    property bool active: false

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property bool available: service ? service.available : false
    readonly property bool probed: service ? service.probed : false
    readonly property int percent: service ? service.percent : 0
    readonly property int step: service ? service.step : 10

    implicitWidth: root.widthBudget
    implicitHeight: col.implicitHeight

    function set(p) { if (root.service) root.service.setPercent(p); }

    Column {
        id: col
        width: root.width
        spacing: 10 * root.s

        // eyebrow: title left, level right
        Item {
            width: parent.width
            height: 22 * root.s
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "KEYBOARD LIGHT"
                color: Theme.bright
                font.family: Theme.mono
                font.pixelSize: 13 * root.s
                font.letterSpacing: 2
                font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.available
                text: root.percent === 0 ? "OFF" : root.percent + "%"
                color: root.percent === 0 ? Theme.dim : Theme.accent
                font.family: Theme.mono
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        Text {
            visible: root.probed && !root.available
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No keyboard backlight found (no *kbd_backlight* LED), or brightnessctl is missing."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
        }

        // track: click or drag anywhere on it
        Item {
            visible: root.available
            width: parent.width
            height: 20 * root.s

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 8 * root.s
                radius: 4 * root.s
                color: Theme.tileBg
                border.color: Theme.hair
                border.width: 1

                Rectangle {
                    width: track.width * root.percent / 100
                    height: track.height
                    radius: track.radius
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function fromX(x) { root.set(100 * Math.max(0, Math.min(1, x / width))); }
                onPressed: (e) => fromX(e.x)
                onPositionChanged: (e) => { if (pressed) fromX(e.x); }
            }
        }

        // step and preset buttons
        Row {
            visible: root.available
            spacing: 6 * root.s

            Repeater {
                model: [
                    { label: "−", act: "down" },
                    { label: "OFF",    act: 0 },
                    { label: "50%",    act: 50 },
                    { label: "MAX",    act: 100 },
                    { label: "+",      act: "up" }
                ]
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    readonly property bool current: typeof modelData.act === "number" && modelData.act === root.percent
                    width: Math.max(34 * root.s, lbl.implicitWidth + 16 * root.s)
                    height: 26 * root.s
                    radius: Theme.radius
                    color: area.pressed ? Theme.vermDeep : (current ? Theme.threadBg : Theme.tileBg)
                    border.color: current ? Theme.accent : Theme.hair
                    border.width: 1

                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        text: btn.modelData.label
                        color: btn.current ? Theme.accent : Theme.bright
                        font.family: Theme.mono
                        font.pixelSize: 11 * root.s
                    }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const a = btn.modelData.act;
                            if (a === "down") root.service.stepBy(-root.step);
                            else if (a === "up") root.service.stepBy(root.step);
                            else root.set(a);
                        }
                    }
                }
            }
        }
    }
}
