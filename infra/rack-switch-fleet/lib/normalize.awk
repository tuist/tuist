# Turn switch CLI output into text that can be compared with a render.
#
# The CLI is a terminal, not an API: its config dumps arrive wrapped in a pager
# that erases itself with carriage returns, padded with `#` separators, and
# bracketed by the echoed command and the next prompt. Normalising that away is
# what turns "looks the same" into a diff worth acting on.
#
# NUL is stripped by the caller with tr, because the firmware sends a bare CR as
# CR NUL and awk does not handle NUL inside a record.
#
#   -v mode=normalize   only configuration commands, comparable line by line
#   -v mode=context     the same, as "context<TAB>command" for planning
#   -v mode=clean       the file's own shape, terminal noise and secret removed

function strip_ansi(s) {
    gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/, "", s)
    gsub(/[\001-\010\013\014\016-\037\177]/, "", s)
    return s
}

# Collapse a physical line the way a terminal would: last write wins.
function cr_collapse(s,   n, part, i, segment, out) {
    if (index(s, "\r") == 0) return s
    n = split(s, part, "\r")
    out = ""
    for (i = 1; i <= n; i++) {
        segment = part[i]
        if (length(segment) >= length(out)) out = segment
        else out = segment substr(out, length(segment) + 1)
    }
    return out
}

function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}

BEGIN { if (mode == "") mode = "normalize" }

{
    line = cr_collapse(strip_ansi($0))

    if (line ~ /Press any key to continue \(Q to quit\)/) {
        sub(/Press any key to continue \(Q to quit\)/, "", line)
        sub(/^[ \t]+/, "", line)
    }
    sub(/[ \t]+$/, "", line)

    if (mode == "clean") {
        if (match(line, /^[ \t]*user name [^ ]+ privilege [^ ]+ secret [0-9]+ /))
            line = substr(line, 1, RLENGTH) "<redacted, see 1Password>"
        print line
        next
    }

    bare = trim(line)
    if (bare == "" || bare == "#" || bare == "end") next
    if (bare ~ /^!/) next

    # Lines the rendered state deliberately does not own, so a difference in
    # them is not drift. The pattern comes from lib/config.sh so the normaliser
    # and the merger cannot disagree about what is unmanaged.
    if (unmanaged != "" && bare ~ unmanaged) next

    if (mode == "context") {
        if (line !~ /^[ \t]/) {
            if (line ~ /^interface / || line ~ /^vlan /) { context = line; next }
            context = ""
        }
        print context "\t" bare
        next
    }

    print line
}
