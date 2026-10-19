package podagent

import (
	"fmt"
	"strconv"
	"strings"
)

// parseImageCurrentSectors reads an image's current size, in 512-byte sectors,
// from `hdiutil resize -limits` output: a line of minimum, current and maximum.
// hdiutil can print warnings around that line, such as the deprecation notice
// macOS 27 emits for `hdiutil resize`, so it takes the last line made of exactly
// three unsigned integers.
func parseImageCurrentSectors(out string) (uint64, error) {
	lines := strings.Split(out, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		fields := strings.Fields(lines[i])
		if len(fields) != 3 {
			continue
		}
		var limits [3]uint64
		ok := true
		for j, field := range fields {
			n, err := strconv.ParseUint(field, 10, 64)
			if err != nil {
				ok = false
				break
			}
			limits[j] = n
		}
		if ok {
			return limits[1], nil
		}
	}
	return 0, fmt.Errorf("want a line of minimum, current and maximum sectors, got %q", strings.TrimSpace(out))
}
