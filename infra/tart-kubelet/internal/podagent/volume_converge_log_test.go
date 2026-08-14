package podagent

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-logr/logr/funcr"
	ctrllog "sigs.k8s.io/controller-runtime/pkg/log"
)

// Installed once for the whole package: controller-runtime's SetLogger fulfils
// a promise, so only the FIRST call takes effect and a per-test SetLogger would
// silently leave every later test capturing nothing. The sink stays fixed and
// captureLogs swaps what it writes into.
var (
	logSinkOnce sync.Once
	logSinkMu   sync.Mutex
	logSink     *[]string
)

// captureLogs routes the package logger into a fresh buffer for the duration of
// a test and returns an accessor for what it recorded.
//
// These assertions are about the host being able to answer "why did THIS
// account decline on THIS host", which is a question only a log line can
// answer — a counter says how often a branch fired, never for whom. The
// branches are otherwise indistinguishable from a healthy converge, which is
// how a fleet ran 286 materializes and 1 convergence in a day with nothing to
// look at.
func captureLogs(t *testing.T) func() []string {
	t.Helper()
	logSinkOnce.Do(func() {
		ctrllog.SetLogger(funcr.New(func(prefix, args string) {
			logSinkMu.Lock()
			defer logSinkMu.Unlock()
			if logSink != nil {
				*logSink = append(*logSink, prefix+" "+args)
			}
		}, funcr.Options{}))
	})

	var lines []string
	logSinkMu.Lock()
	logSink = &lines
	logSinkMu.Unlock()
	t.Cleanup(func() {
		logSinkMu.Lock()
		defer logSinkMu.Unlock()
		logSink = nil
	})

	return func() []string {
		logSinkMu.Lock()
		defer logSinkMu.Unlock()
		return append([]string(nil), lines...)
	}
}

func containsAll(lines []string, substrings ...string) bool {
	for _, line := range lines {
		matched := true
		for _, want := range substrings {
			if !strings.Contains(line, want) {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}

func writeVolumeHead(t *testing.T, statusDir string, head volumeHead) {
	t.Helper()
	if err := os.MkdirAll(statusDir, 0o755); err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(head)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(statusDir, volumeHeadFile), raw, 0o644); err != nil {
		t.Fatal(err)
	}
}

// shrinkConvergeHeadWait keeps the nil-HEAD path from burning its real 15s wait.
func shrinkConvergeHeadWait(t *testing.T) {
	t.Helper()
	interval, attempts := convergeHeadWaitInterval, convergeHeadWaitAttempts
	convergeHeadWaitInterval, convergeHeadWaitAttempts = time.Millisecond, 2
	t.Cleanup(func() { convergeHeadWaitInterval, convergeHeadWaitAttempts = interval, attempts })
}

// The `head_absent` case: the guest never staged volume-head.json. The counter
// can say this dominates; only the log says which account on which host, which
// is the next question every time.
func TestConvergeMasterLogsWhenTheGuestStagedNoHead(t *testing.T) {
	shrinkConvergeHeadWait(t)
	logs := captureLogs(t)
	m, _ := newTestManager(t, 100)
	r := &Reconciler{Volumes: m}

	r.convergeMaster("vm-1", t.TempDir(), ReservedTuistCacheVolume, "account-7")

	if !containsAll(logs(), "converge", "no HEAD", "vm-1", "account-7") {
		t.Fatalf("expected a decline line naming the vm and account, got %q", logs())
	}
}

func TestConvergeMasterLogsWhenTheHeadIsIncomplete(t *testing.T) {
	shrinkConvergeHeadWait(t)
	logs := captureLogs(t)
	m, _ := newTestManager(t, 100)
	r := &Reconciler{Volumes: m}
	statusDir := t.TempDir()
	// A HEAD generation with no download URL: the server knows of a master but
	// handed out nothing to fetch it with.
	writeVolumeHead(t, statusDir, volumeHead{Generation: 9})

	r.convergeMaster("vm-1", statusDir, ReservedTuistCacheVolume, "account-7")

	if !containsAll(logs(), "converge", "incomplete", "account-7") {
		t.Fatalf("expected a decline line for the incomplete HEAD, got %q", logs())
	}
}

func TestConvergeMasterLogsWhenAlreadyAtHead(t *testing.T) {
	shrinkConvergeHeadWait(t)
	logs := captureLogs(t)
	m, _ := newTestManager(t, 100)
	r := &Reconciler{Volumes: m}
	statusDir := t.TempDir()
	writeVolumeHead(t, statusDir, volumeHead{Generation: 3, DownloadURL: "https://example.invalid/master"})

	// A resident master already at generation 5 — ahead of the advertised HEAD.
	dir := m.volumeDir("account-7", ReservedTuistCacheVolume)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, masterImageName), []byte("image"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, masterGenerationName), []byte(strconv.Itoa(5)), 0o644); err != nil {
		t.Fatal(err)
	}

	r.convergeMaster("vm-1", statusDir, ReservedTuistCacheVolume, "account-7")

	if !containsAll(logs(), "converge", "already at or past HEAD", "account-7") {
		t.Fatalf("expected a decline line for the already-current master, got %q", logs())
	}
}

// Every line the convergence emits has to carry the literal "converge", because
// the query the fleet is meant to be diagnosed with is a substring filter:
// {job="tuist-macos-tart-kubelet"} |= "converge".
func TestConvergeDeclineLinesAreSelectableBySubstring(t *testing.T) {
	shrinkConvergeHeadWait(t)
	logs := captureLogs(t)
	m, _ := newTestManager(t, 100)
	r := &Reconciler{Volumes: m}

	r.convergeMaster("vm-1", t.TempDir(), ReservedTuistCacheVolume, "account-7")

	emitted := logs()
	if len(emitted) == 0 {
		t.Fatal("expected the decline to emit at least one line")
	}
	for _, line := range emitted {
		if !strings.Contains(line, "converge") {
			t.Fatalf("line %q is invisible to |= \"converge\"", line)
		}
	}
}
