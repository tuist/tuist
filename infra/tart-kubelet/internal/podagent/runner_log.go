package podagent

import (
	"bytes"
	"fmt"
	"strings"
)

// runnerLogScanBytes / runnerLogScanLines bound the window that is read
// and collapsed down to runnerLogTailLines / runnerLogTailBytes. Both
// caps are needed: the guest picks the file's size and its line count
// independently, and a line costs a slice header whether or not it
// holds anything. The line cap binds only below ~16 bytes per line,
// which no runner log reaches.
const (
	runnerLogScanBytes  = 16 << 20
	runnerLogScanLines  = 1 << 20
	runnerLogMaxPeriod  = 8
	runnerLogMinRepeats = 3
)

// runnerLogTail reduces a scanned window to the published tail.
// partialFirstLine reports that the window began mid-file, so its first
// line is a fragment.
func runnerLogTail(window []byte, partialFirstLine bool) string {
	window = bytes.TrimRight(window, "\n")
	if start := scanLinesStart(window); start > 0 {
		window = window[start:]
		partialFirstLine = false
	}
	lines := strings.Split(string(window), "\n")
	if partialFirstLine && len(lines) > 1 {
		lines = lines[1:]
	}
	lines = collapseRepeatedBlocks(lines)
	if len(lines) > runnerLogTailLines {
		lines = lines[len(lines)-runnerLogTailLines:]
	}
	return strings.Join(boundToTailBytes(lines), "\n")
}

// scanLinesStart returns where the last runnerLogScanLines records of
// window begin, or 0 when window holds no more than that many. Selected
// before the split, so a file the guest filled with newlines costs one
// backward pass rather than a slice header per line.
func scanLinesStart(window []byte) int {
	end := len(window)
	for range runnerLogScanLines {
		i := bytes.LastIndexByte(window[:end], '\n')
		if i < 0 {
			return 0
		}
		end = i
	}
	return end + 1
}

// collapseRepeatedBlocks rewrites each consecutively repeating block of
// lines as one copy followed by a count. Blocks rather than single
// lines: the supervisor loop that floods these logs cycles three
// distinct lines, so no line there ever follows itself.
//
// Keeps only the most recent runnerLogTailLines it has produced, since
// that is all the caller can publish; a window that collapses to
// nothing would otherwise cost a header per line of it.
func collapseRepeatedBlocks(lines []string) []string {
	var out []string
	for i := 0; i < len(lines); {
		period, repeats := repeatedBlockAt(lines, i)
		if period == 0 {
			out = append(out, lines[i])
			i++
		} else {
			out = append(out, lines[i:i+period]...)
			out = append(out, repeatMarker(period, repeats))
			i += period * repeats
		}
		if len(out) > 2*runnerLogTailLines {
			out = append(out[:0], out[len(out)-runnerLogTailLines:]...)
		}
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
