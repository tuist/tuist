#!/usr/bin/env bash
set -euo pipefail

fail() { echo "check-widget: $*" >&2; exit 1; }
[[ $# = 1 ]] || fail "Usage: $0 /path/to/AtlasLiveActivity.appex/AtlasLiveActivity"
binary=$1
[[ -f "$binary" ]] || fail "Executable not found: $binary"

symbols=$(xcrun nm -U "$binary")
awk '$2 ~ /^[Tt]$/ && $3 == "_main" { found = 1 } END { exit !found }' <<< "$symbols" ||
    fail "Swift _main must be defined: $binary"
metadata=$(xcrun otool -l "$binary")
indirect=$(xcrun otool -Iv "$binary")

# LC_MAIN is a file offset; indirect symbols are virtual addresses. Only the
# __TEXT stub counts, not the second _NSExtensionMain entry in a pointer section.
awk '
    function number(value, result, i) {
        if (value !~ /^0[xX]/) return value + 0
        result = 0
        for (i = 3; i <= length(value); i++)
            result = result * 16 + index("0123456789abcdef", tolower(substr(value, i, 1))) - 1
        return result
    }
    function fail(message) {
        print "check-widget: " message > "/dev/stderr"
        exit 1
    }
    $1 == "cmd" { command = $2; section = ""; segment = "" }
    command == "LC_SEGMENT_64" {
        if ($1 == "sectname") section = $2
        if ($1 == "segname") segment = $2
        if (segment == "__TEXT" && section == "") {
            if ($1 == "vmaddr") text_base = $2
            if ($1 == "fileoff") text_offset = $2
            if ($1 == "filesize") text_size = $2
        }
        if (segment == "__TEXT" && section == "__swift5_entry" && $1 == "size")
            swift_size = number($2)
    }
    command == "LC_MAIN" && $1 == "entryoff" { entry_offset = $2 }
    $1 == "Indirect" { stubs = ($4 == "(__TEXT,__stubs)") }
    stubs && $1 ~ /^0[xX]/ && $3 == "_NSExtensionMain" {
        extension_stub = number($1)
        found_stub = 1
    }
    END {
        if (swift_size <= 0) fail("Missing nonempty __TEXT,__swift5_entry")
        if (text_base == "" || text_offset == "" || text_size == "" || entry_offset == "")
            fail("Missing __TEXT mapping or LC_MAIN entryoff")
        offset = number(entry_offset) - number(text_offset)
        if (offset < 0 || offset >= number(text_size)) fail("LC_MAIN is outside __TEXT")
        if (!found_stub || number(text_base) + offset != extension_stub)
            fail("LC_MAIN must enter the _NSExtensionMain stub, not Swift _main")
    }
' <<< "$metadata
$indirect"

echo "Widget startup contract verified: $binary"
