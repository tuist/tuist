package podagent

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func writeRunnerLog(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, runnerLogFile), []byte(body), 0o644); err != nil {
		t.Fatalf("write runner log: %v", err)
	}
	return dir
}

func TestReadRunnerLogAbsent(t *testing.T) {
	// No status share at all is the pools-without-cache-volumes case,
	// and it must degrade to "nothing to say" rather than an error.
	if got := readRunnerLog(""); got != "" {
		t.Errorf("empty statusDir = %q, want \"\"", got)
	}
	if got := readRunnerLog(t.TempDir()); got != "" {
		t.Errorf("missing file = %q, want \"\"", got)
	}
}

func TestReadRunnerLogShortFileReturnedWhole(t *testing.T) {
	dir := writeRunnerLog(t, "first\nsecond\nthird\n")

	got := readRunnerLog(dir)

	if got != "first\nsecond\nthird" {
		t.Errorf("got %q, want the whole file without its trailing newline", got)
	}
}

func TestReadRunnerLogKeepsTailNotHead(t *testing.T) {
	// The whole point is the last thing a runner said before it gave up,
	// so an over-long log must lose its beginning, never its end.
	var b strings.Builder
	for i := range runnerLogTailLines * 2 {
		fmt.Fprintf(&b, "line-%d\n", i)
	}
	dir := writeRunnerLog(t, b.String())

	lines := strings.Split(readRunnerLog(dir), "\n")

	if len(lines) > runnerLogTailLines {
		t.Fatalf("got %d lines, want at most %d", len(lines), runnerLogTailLines)
	}
	want := fmt.Sprintf("line-%d", runnerLogTailLines*2-1)
	if lines[len(lines)-1] != want {
		t.Errorf("last line = %q, want %q", lines[len(lines)-1], want)
	}
}

func TestReadRunnerLogDropsPartialFirstLine(t *testing.T) {
	// A byte-bounded read lands mid-line; emitting that fragment would
	// put a corrupt-looking record at the top of every large capture.
	head := strings.Repeat("x", runnerLogTailBytes)
	dir := writeRunnerLog(t, head+"\ncomplete-line\n")

	got := readRunnerLog(dir)

	if strings.Contains(got, "x") {
		t.Errorf("got %q, want the truncated first line dropped", got)
	}
	if got != "complete-line" {
		t.Errorf("got %q, want %q", got, "complete-line")
	}
}

func TestReadRunnerLogBoundsBytes(t *testing.T) {
	// One pathological line must not blow up the log record it lands in.
	dir := writeRunnerLog(t, strings.Repeat("y", runnerLogTailBytes*3)+"\n")

	if got := len(readRunnerLog(dir)); got > runnerLogTailBytes {
		t.Errorf("got %d bytes, want at most %d", got, runnerLogTailBytes)
	}
}

// The status share is written by the guest, which runs untrusted customer
// CI. Anything it leaves at runner.log that is not a plain file is an
// attempt to make the host read something else on its behalf, and the
// host publishes what it reads straight to Loki.
func TestReadRunnerLogRejectsGuestSymlink(t *testing.T) {
	dir := t.TempDir()
	secret := filepath.Join(t.TempDir(), "host-secret")
	if err := os.WriteFile(secret, []byte("host-only-content\n"), 0o600); err != nil {
		t.Fatalf("write secret: %v", err)
	}
	if err := os.Symlink(secret, filepath.Join(dir, runnerLogFile)); err != nil {
		t.Fatalf("symlink: %v", err)
	}

	if got := readRunnerLog(dir); got != "" {
		t.Errorf("got %q, want \"\" — a guest symlink must not be followed", got)
	}
}

func TestReadRunnerLogRejectsNonRegularFile(t *testing.T) {
	// A FIFO is the other half of the same trick: without O_NONBLOCK the
	// open alone parks the reconcile until someone writes.
	dir := t.TempDir()
	if err := syscall.Mkfifo(filepath.Join(dir, runnerLogFile), 0o600); err != nil {
		t.Skipf("mkfifo unsupported: %v", err)
	}

	done := make(chan string, 1)
	go func() { done <- readRunnerLog(dir) }()

	select {
	case got := <-done:
		if got != "" {
			t.Errorf("got %q, want \"\"", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("readRunnerLog blocked on a FIFO")
	}
}

func TestReadRunnerLogRejectsDirectory(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, runnerLogFile), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	if got := readRunnerLog(dir); got != "" {
		t.Errorf("got %q, want \"\"", got)
	}
}

// hotLoopBlock is the shape that floods these logs: the supervisor
// retries a refused stale-lock removal with no backoff, many times per
// second. Three lines, and no line follows itself, so collapsing equal
// adjacent lines finds nothing here.
const hotLoopBlock = "runner-shell-agent-supervisor: removing stale lock at /tmp/tuist-runner-shell-agent.lock\n" +
	"rm: /tmp/tuist-runner-shell-agent.lock/pid: Permission denied\n" +
	"rm: /tmp/tuist-runner-shell-agent.lock: Permission denied\n"

func hotLoopLog(t *testing.T, prefix []string, bytes int) string {
	t.Helper()
	var b strings.Builder
	for _, l := range prefix {
		b.WriteString(l)
		b.WriteByte('\n')
	}
	for b.Len() < bytes {
		b.WriteString(hotLoopBlock)
	}
	return writeRunnerLog(t, b.String())
}

func TestReadRunnerLogKeepsHistoryBehindARepeatingBlock(t *testing.T) {
	// The runner's own trail sits behind more than a byte window's worth
	// of one repeating block, and that trail is what the capture exists
	// to carry.
	var prefix []string
	for i := range 20 {
		prefix = append(prefix, fmt.Sprintf("dispatch-poll: runner-said-%d", i))
	}
	dir := hotLoopLog(t, prefix, runnerLogTailBytes*4)

	published := map[string]bool{}
	for _, l := range strings.Split(readRunnerLog(dir), "\n") {
		published[l] = true
	}

	for _, want := range prefix {
		if !published[want] {
			t.Errorf("published tail lost %q", want)
		}
	}
}

func TestReadRunnerLogReportsHowOftenABlockRepeated(t *testing.T) {
	// The repetition is itself the finding, so the count survives even
	// though the instances do not.
	dir := hotLoopLog(t, nil, runnerLogTailBytes*4)

	got := readRunnerLog(dir)

	repeats := strings.Count(got, hotLoopBlock)
	if repeats != 1 {
		t.Errorf("block appears %d times, want 1 copy plus a count", repeats)
	}
	if !strings.Contains(got, "... (previous 3 lines repeated ") {
		t.Errorf("got %q, want a marker naming the repeat count", got)
	}
}

func TestReadRunnerLogBoundsARepeatingBlock(t *testing.T) {
	// Collapsing runs before the budgets are applied, so the budgets
	// still have to hold on the input that motivated it.
	dir := hotLoopLog(t, nil, runnerLogScanBytes*2)

	got := readRunnerLog(dir)

	if len(got) > runnerLogTailBytes {
		t.Errorf("got %d bytes, want at most %d", len(got), runnerLogTailBytes)
	}
	if n := len(strings.Split(got, "\n")); n > runnerLogTailLines {
		t.Errorf("got %d lines, want at most %d", n, runnerLogTailLines)
	}
}

func TestReadRunnerLogDropsPartialFirstLineAtScanBoundary(t *testing.T) {
	// The mid-line start moved with the window: it is the scan budget,
	// not the published byte budget, that the read now lands inside.
	const width = 4095
	var b strings.Builder
	for i := 0; b.Len() <= runnerLogScanBytes+width; i++ {
		fmt.Fprintf(&b, "%04d%s\n", i, strings.Repeat("z", width-4))
	}
	dir := writeRunnerLog(t, b.String())

	for _, l := range strings.Split(readRunnerLog(dir), "\n") {
		if len(l) != width {
			t.Fatalf("published a %d-byte line, want whole %d-byte lines only", len(l), width)
		}
	}
}

func TestCollapseRepeatedBlocks(t *testing.T) {
	for _, tt := range []struct {
		name string
		in   []string
		want []string
	}{
		{
			name: "a run of one line collapses",
			in:   []string{"a", "a", "a", "a", "b"},
			want: []string{"a", "... (previous line repeated 3 more times)", "b"},
		},
		{
			name: "a doubled line is left alone",
			in:   []string{"a", "a", "b"},
			want: []string{"a", "a", "b"},
		},
		{
			// Below the floor the marker costs more lines than it saves.
			name: "a doubled block is left alone",
			in:   []string{"a", "b", "a", "b", "c"},
			want: []string{"a", "b", "a", "b", "c"},
		},
		{
			name: "the shortest period wins",
			in:   []string{"a", "a", "a", "a", "a", "a"},
			want: []string{"a", "... (previous line repeated 5 more times)"},
		},
		{
			name: "lines between runs survive",
			in:   []string{"x", "a", "b", "a", "b", "a", "b", "y"},
			want: []string{"x", "a", "b", "... (previous 2 lines repeated 2 more times)", "y"},
		},
		{
			name: "nothing repeating is untouched",
			in:   []string{"a", "b", "c"},
			want: []string{"a", "b", "c"},
		},
		{
			// A block longer than the cap is not a loop worth chasing.
			name: "a period over the cap is left alone",
			in:   append(append(longBlock(), longBlock()...), longBlock()...),
			want: append(append(longBlock(), longBlock()...), longBlock()...),
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got := collapseRepeatedBlocks(tt.in)
			if strings.Join(got, "|") != strings.Join(tt.want, "|") {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func longBlock() []string {
	b := make([]string, runnerLogMaxPeriod+1)
	for i := range b {
		b[i] = fmt.Sprintf("l%d", i)
	}
	return b
}

func TestReadRunnerLogKeepsTheEndOfAFileWithoutNewlines(t *testing.T) {
	// Nothing to split on, so the fragment published is chosen by the
	// byte cap alone, and it has to be the end of the file.
	body := strings.Repeat("q", runnerLogScanBytes+1<<20) + "last-thing-it-said"
	dir := writeRunnerLog(t, body)

	got := readRunnerLog(dir)

	if len(got) > runnerLogTailBytes {
		t.Fatalf("got %d bytes, want at most %d", len(got), runnerLogTailBytes)
	}
	if !strings.HasSuffix(got, "last-thing-it-said") {
		t.Error("published a fragment from somewhere other than the end of the file")
	}
}
