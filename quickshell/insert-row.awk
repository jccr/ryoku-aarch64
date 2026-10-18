# Insert the keyboard-backlight row after the (single) Pill.BrightnessControl
# block in Ryoku's QuickSettingsHome.qml, at the same indent. Prints the file
# unchanged when the anchor is missing; the caller checks for the marker.
{ print }
!done && /Pill\.BrightnessControl[[:space:]]*\{/ {
    inb = 1; depth = 0
    match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
}
inb {
    line = $0
    depth += gsub(/\{/, "{", line)
    depth -= gsub(/\}/, "}", line)
    if (depth <= 0) {
        print indent "KbdBacklightSlider { width: parent.width; open: root.open } // ryoku-aarch64"
        inb = 0; done = 1
    }
}
