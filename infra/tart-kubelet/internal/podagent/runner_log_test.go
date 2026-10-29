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
