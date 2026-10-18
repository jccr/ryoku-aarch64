pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// service/Main.qml: the keyboard backlight's state and the only code that
// touches it. Reads and writes go through brightnessctl (argv arrays, no shell),
// which sets an LED through systemd-logind for the active seat session: no root,
// no pkexec. The widget and the panel both read this one instance.
Item {
    id: svc

    property var pluginApi
    readonly property var settings: pluginApi ? pluginApi.pluginSettings : null
    readonly property bool panelOpen: pluginApi ? !!pluginApi.panelOpen : false

    // Step for the panel's - / + buttons, read behind a default (R5).
    readonly property int step: {
        const v = settings ? settings.step : undefined;
        return (typeof v === "number" && v >= 1 && v <= 50) ? v : 10;
    }

    // brightnessctl matches -d against LED names with fnmatch; Asahi names the
    // MacBook keyboard LED "kbd_backlight", other laptops "<vendor>::kbd_backlight".
    readonly property string deviceGlob: "*kbd_backlight*"

    property bool probed: false      // a read has completed at least once
    property bool available: false   // a keyboard backlight LED exists
    property string device: ""
    property int percent: 0
    property int queued: -1          // pending target while dragging

    function clamp(p) { return Math.max(0, Math.min(100, Math.round(p))); }

    function refresh() {
        if (!reader.running && !writer.running && svc.queued < 0)
            reader.running = true;
    }

    // Optimistic: the slider moves at once; writes coalesce through the debounce
    // so a drag sends one brightnessctl at a time, ending on the last value.
    function setPercent(p) {
        if (!svc.available) return;
        svc.queued = clamp(p);
        svc.percent = svc.queued;
        debounce.restart();
    }

    function stepBy(delta) { setPercent(svc.percent + delta); }

    function drain() {
        if (writer.running || svc.queued < 0) return;
        writer.command = ["brightnessctl", "-m", "-d", svc.deviceGlob, "set", svc.queued + "%"];
        svc.queued = -1;
        writer.running = true;
    }

    // brightnessctl -m prints: device,class,current,percent%,max
    function parse(text) {
        const line = (text || "").trim().split("\n")[0];
        const f = line.split(",");
        if (f.length >= 4 && f[1] === "leds") {
            svc.device = f[0];
            if (svc.queued < 0) svc.percent = clamp(parseInt(f[3]));
            svc.available = true;
        } else {
            svc.available = false;
        }
        svc.probed = true;
    }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-d", svc.deviceGlob, "info"]
        stdout: StdioCollector { onStreamFinished: svc.parse(this.text) }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) { svc.available = false; svc.probed = true; }
        }
    }

    Process {
        id: writer
        stdout: StdioCollector { onStreamFinished: svc.parse(this.text) }
        onExited: (exitCode, exitStatus) => svc.drain()
    }

    Timer { id: debounce; interval: 60; onTriggered: svc.drain() }

    // Keybinds and other tools change the LED too: follow them closely while the
    // panel is open, lazily otherwise (the glyph only shows on/off).
    Timer {
        interval: svc.panelOpen ? 1500 : 15000
        running: true
        repeat: true
        onTriggered: svc.refresh()
    }

    onPanelOpenChanged: if (panelOpen) refresh()
    Component.onCompleted: refresh()
}
