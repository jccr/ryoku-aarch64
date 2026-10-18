pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".." as Menus

// ryoku-aarch64: a keyboard-backlight row for Ryoku's quick settings
// ("Sound & display"), built from Ryoku's own QsSlider so it matches the volume
// and brightness rows. Dropped next to QuickSettingsHome.qml by `ryoku-arm`
// after each deploy; hidden when the machine has no *kbd_backlight* LED.
//
// Drag sets the level; tapping the icon toggles off <-> the last level, like
// the volume row's mute. brightnessctl sets the LED through systemd-logind for
// the active session: no root.
Item {
    id: kb

    property bool open: false

    property bool available: false
    property int percent: 0
    property int lastOn: 50
    property int queued: -1
    readonly property string deviceGlob: "*kbd_backlight*"

    visible: available
    implicitHeight: available ? row.implicitHeight : 0

    Menus.QsSlider {
        id: row
        width: parent.width
        icon: "keyboard"
        lit: kb.open
        value: kb.percent / 100
        muted: kb.available && kb.percent === 0
        valueLabel: kb.percent === 0 ? "off" : kb.percent + "%"
        onMoved: v => kb.set(v * 100)
        onIconTapped: kb.set(kb.percent > 0 ? 0 : kb.lastOn)
    }

    function clamp(p) { return Math.max(0, Math.min(100, Math.round(p))); }

    function set(p) {
        if (!kb.available) return;
        kb.queued = clamp(p);
        if (kb.queued > 0) kb.lastOn = kb.queued;
        kb.percent = kb.queued;
        debounce.restart();
    }

    function refresh() {
        if (!reader.running && !writer.running && kb.queued < 0)
            reader.running = true;
    }

    function drain() {
        if (writer.running || kb.queued < 0) return;
        writer.command = ["brightnessctl", "-m", "-d", kb.deviceGlob, "set", kb.queued + "%"];
        kb.queued = -1;
        writer.running = true;
    }

    // brightnessctl -m: device,class,current,percent%,max
    function parse(text) {
        const f = (text || "").trim().split("\n")[0].split(",");
        if (f.length >= 4 && f[1] === "leds") {
            kb.available = true;
            if (kb.queued < 0) {
                kb.percent = clamp(parseInt(f[3]));
                if (kb.percent > 0) kb.lastOn = kb.percent;
            }
        } else {
            kb.available = false;
        }
    }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-d", kb.deviceGlob, "info"]
        stdout: StdioCollector { onStreamFinished: kb.parse(this.text) }
        onExited: (exitCode, exitStatus) => { if (exitCode !== 0) kb.available = false; }
    }

    Process {
        id: writer
        stdout: StdioCollector { onStreamFinished: kb.parse(this.text) }
        onExited: (exitCode, exitStatus) => kb.drain()
    }

    Timer { id: debounce; interval: 60; onTriggered: kb.drain() }

    // follow keybinds and the bar plugin while the sidebar is open
    Timer {
        interval: 1500
        running: kb.open
        repeat: true
        onTriggered: kb.refresh()
    }

    onOpenChanged: if (open) refresh()
    Component.onCompleted: refresh()
}
