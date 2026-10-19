# Insert the keyboard-backlight row (kbd-row.qml.frag, passed as -v frag=...)
# inline into Ryoku's QuickSettingsHome.qml, after the single
# Pill.BrightnessControl block and at its indent, and add `import Quickshell.Io`
# (for Process) after `import Quickshell` when the file lacks it. Everything
# added carries a "ryoku-aarch64" marker so it can be removed exactly. Prints the
# file unchanged when the anchor is missing; the caller checks for the marker.
BEGIN {
    n = 0
    while ((getline line < frag) > 0) fragl[++n] = line
    close(frag)
}
FNR == 1 {
    # first pass over the same file (see the caller): just learn whether
    # Quickshell.Io is already imported
}
NR == FNR {
    if ($0 ~ /^import[[:space:]]+Quickshell\.Io([[:space:]]|$)/) hasio = 1
    next
}
{ print }
!ioadded && !hasio && $0 ~ /^import[[:space:]]+Quickshell[[:space:]]*$/ {
    print "import Quickshell.Io // ryoku-aarch64"
    ioadded = 1
}
!done && /Pill\.BrightnessControl[[:space:]]*\{/ {
    inb = 1; depth = 0
    match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)
}
inb {
    l = $0
    depth += gsub(/\{/, "{", l)
    depth -= gsub(/\}/, "}", l)
    if (depth <= 0) {
        for (i = 1; i <= n; i++) print (fragl[i] == "" ? "" : indent fragl[i])
        inb = 0; done = 1
    }
}
