// ryoku-aarch64 kbd-row begin (inserted by ryoku-arm; removed/re-added on every deploy)
Item {
    id: ryoArmKbd
    // A keyboard-backlight row built from Ryoku's own QsSlider. Inline rather
    // than a separate file: Quickshell does not register a new .qml file as a
    // type of this folder, so a separate component fails with "is not a type".
    property int percent: 0
    property int lastOn: 50
    property int queued: -1
    property bool available: false
    readonly property string deviceGlob: "*kbd_backlight*"
    width: parent.width
    visible: available
    implicitHeight: available ? ryoArmKbdSlider.implicitHeight : 0
    Menus.QsSlider {
        id: ryoArmKbdSlider
        width: parent.width
        icon: "keyboard"
        lit: root.open
        value: ryoArmKbd.percent / 100
        muted: ryoArmKbd.available && ryoArmKbd.percent === 0
        valueLabel: ryoArmKbd.percent === 0 ? "off" : ryoArmKbd.percent + "%"
        onMoved: v => ryoArmKbd.setLevel(v * 100)
        onIconTapped: ryoArmKbd.setLevel(ryoArmKbd.percent > 0 ? 0 : ryoArmKbd.lastOn)
    }
    function clampLevel(p) { return Math.max(0, Math.min(100, Math.round(p))); }
    function setLevel(p) {
        if (!ryoArmKbd.available) return;
        ryoArmKbd.queued = clampLevel(p);
        if (ryoArmKbd.queued > 0) ryoArmKbd.lastOn = ryoArmKbd.queued;
        ryoArmKbd.percent = ryoArmKbd.queued;
        ryoArmKbdDebounce.restart();
    }
    function refreshLevel() {
        if (!ryoArmKbdRead.running && !ryoArmKbdWrite.running && ryoArmKbd.queued < 0)
            ryoArmKbdRead.running = true;
    }
    function drainLevel() {
        if (ryoArmKbdWrite.running || ryoArmKbd.queued < 0) return;
        ryoArmKbdWrite.command = ["brightnessctl", "-m", "-d", ryoArmKbd.deviceGlob, "set", ryoArmKbd.queued + "%"];
        ryoArmKbd.queued = -1;
        ryoArmKbdWrite.running = true;
    }
    // brightnessctl -m: device,class,current,percent%,max
    function parseLevel(text) {
        const f = (text || "").trim().split("\n")[0].split(",");
        if (f.length >= 4 && f[1] === "leds") {
            ryoArmKbd.available = true;
            if (ryoArmKbd.queued < 0) {
                ryoArmKbd.percent = clampLevel(parseInt(f[3]));
                if (ryoArmKbd.percent > 0) ryoArmKbd.lastOn = ryoArmKbd.percent;
            }
        } else {
            ryoArmKbd.available = false;
        }
    }
    Process {
        id: ryoArmKbdRead
        command: ["brightnessctl", "-m", "-d", ryoArmKbd.deviceGlob, "info"]
        stdout: StdioCollector { onStreamFinished: ryoArmKbd.parseLevel(this.text) }
        onExited: (exitCode, exitStatus) => { if (exitCode !== 0) ryoArmKbd.available = false; }
    }
    Process {
        id: ryoArmKbdWrite
        stdout: StdioCollector { onStreamFinished: ryoArmKbd.parseLevel(this.text) }
        onExited: (exitCode, exitStatus) => ryoArmKbd.drainLevel()
    }
    Timer { id: ryoArmKbdDebounce; interval: 60; onTriggered: ryoArmKbd.drainLevel() }
    Timer { interval: 1500; running: root.open; repeat: true; onTriggered: ryoArmKbd.refreshLevel() }
    Connections {
        target: root
        function onOpenChanged() { if (root.open) ryoArmKbd.refreshLevel(); }
    }
    Component.onCompleted: refreshLevel()
}
// ryoku-aarch64 kbd-row end
