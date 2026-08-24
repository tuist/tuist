package podagent

import (
	"fmt"
	"strings"
)

// runnerLogScanBytes / runnerLogScanLines bound the window that is read
// and collapsed down to runnerLogTailLines / runnerLogTailBytes. The
// line cap binds only below ~16 bytes per line, which no runner log
// reaches; it is there to bound collapseRepeatedBlocks on a file the
// guest chose the shape of.
const (
	runnerLogScanBytes  = 16 << 20
	runnerLogScanLines  = 1 << 20
	runnerLogMaxPeriod  = 8
	runnerLogMinRepeats = 3
)

// runnerLogTail reduces a scanned window to the published tail.
// partialFirstLine reports that the window began mid-file, so its first
// line is a fragment.
func runnerLogTail(window string, partialFirstLine bool) string {
	lines := strings.Split(strings.TrimRight(window, "\n"), "\n")
	if partialFirstLine && len(lines) > 1 {
		lines = lines[1:]
	}
	if len(lines) > runnerLogScanLines {
		lines = lines[len(lines)-runnerLogScanLines:]
	}
	lines = collapseRepeatedBlocks(lines)
	if len(lines) > runnerLogTailLines {
		lines = lines[len(lines)-runnerLogTailLines:]
	}
	return strings.Join(boundToTailBytes(lines), "\n")
}

// collapseRepeatedBlocks rewrites each consecutively repeating block of
// lines as one copy followed by a count. Blocks rather than single
// lines: the supervisor loop that floods these logs cycles three
// distinct lines, so no line there ever follows itself.
func collapseRepeatedBlocks(lines []string) []string {
	var out []string
	for i := 0; i < len(lines); {
		period, repeats := repeatedBlockAt(lines, i)
		if period == 0 {
			out = append(out, lines[i])
			i++
			continue
		}
		out = append(out, lines[i:i+period]...)
		out = append(out, repeatMarker(period, repeats))
		i += period * repeats
	}
	return out
}

// repeatedBlockAt returns the shortest block starting at i that repeats
// consecutively at least runnerLogMinRepeats times, and how many times
// it occurs in total. period is 0 when nothing at i repeats that often.
func repeatedBlockAt(lines []string, i int) (period, repeats int) {
	for p := 1; p <= runnerLogMaxPeriod && i+p*runnerLogMinRepeats <= len(lines); p++ {
		n := 1
		for j := i + p; j+p <= len(lines) && blocksEqual(lines, i, j, p); j += p {
			n++
		}
		if n >= runnerLogMinRepeats {
			return p, n
		}
	}
	return 0, 0
}

func blocksEqual(lines []string, a, b, n int) bool {
	for k := range n {
		if lines[a+k] != lines[b+k] {
			return false
		}
	}
	return true
}

func repeatMarker(period, repeats int) string {
	if period == 1 {
		return fmt.Sprintf("... (previous line repeated %d more times)", repeats-1)
	}
	return fmt.Sprintf("... (previous %d lines repeated %d more times)", period, repeats-1)
}

// boundToTailBytes caps the published size. Applied last, because the
// rewrites above shrink guest-chosen input without bounding it. Whole
// lines go first, oldest first; a line left over the cap on its own
// keeps its end, for the same reason the tail is preferred to the head.
func boundToTailBytes(lines []string) []string {
	if len(lines) == 0 {
		return lines
	}
	total := len(lines) - 1
	for _, l := range lines {
		total += len(l)
	}
	for total > runnerLogTailBytes && len(lines) > 1 {
		total -= len(lines[0]) + 1
		lines = lines[1:]
	}
	if l := lines[0]; len(l) > runnerLogTailBytes {
		lines = []string{l[len(l)-runnerLogTailBytes:]}
	}
	return lines
}
