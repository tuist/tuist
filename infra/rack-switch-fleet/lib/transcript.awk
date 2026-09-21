# The configuration body out of a session transcript: everything the switch
# printed for `command`, without the echoed command itself and without the
# prompt that follows. -v command=<the command that was sent>

function strip_cr(s) { gsub(/\r/, "", s); return s }

!started {
    if (strip_cr($0) ~ ("(^|[#>])" command "[ \t]*$")) started = 1
    next
}

{
    line = strip_cr($0)
    if (body > 0 && line ~ /^[A-Za-z0-9._-]+[#>][ \t]*$/) exit
    print $0
    body++
}

END { if (!started) { print "transcript never echoed " command > "/dev/stderr"; exit 3 } }
