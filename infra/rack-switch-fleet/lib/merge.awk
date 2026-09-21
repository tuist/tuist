# Build the file that would be pushed to a switch, from the render plus the
# lines the render does not own.
#
# The render deliberately omits the local admin login and `system-time ntp`.
# That is right for something committed to git and fatal for something written
# over the switch's startup config: pushing the render as it stands removes the
# account used to log in, leaving the console as the only way back. So each
# unmanaged line is carried across from the switch's current configuration.
#
# Position is derived rather than hard-coded: an unmanaged line is re-inserted
# in front of whichever configuration line followed it on the device, so the
# ordering survives a firmware that cares about it without this file knowing
# which lines those are.
#
#   awk -f merge.awk <current-export> <rendered-config>

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function is_structural(t) { return t == "" || t == "#" || t == "end" || t ~ /^!/ }
function is_unmanaged(t) { return t ~ /^user name / || t ~ /^system-time ntp / }

NR == FNR {
    line = $0
    sub(/\r$/, "", line)
    t = trim(line)
    if (is_structural(t)) next
    if (is_unmanaged(t)) { pending[++waiting] = line; next }
    if (waiting > 0) {
        for (i = 1; i <= waiting; i++) carried[t] = carried[t] pending[i] "\n"
        waiting = 0
    }
    next
}

# Anything still waiting when the current config ran out had no line after it
# to anchor to, so it goes in before the render's `end` rather than nowhere.
FNR == 1 && NR != FNR {
    for (i = 1; i <= waiting; i++) trailing = trailing pending[i] "\n"
    waiting = 0
}

{
    t = trim($0)
    if (t in carried) { printf "%s", carried[t]; delete carried[t] }
    if (t == "end") {
        for (key in carried) { printf "%s", carried[key]; delete carried[key] }
        printf "%s", trailing
        trailing = ""
    }
    print
}
