package podagent

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// capturingSink records log messages so a test can assert a code path said
// something. These assertions exist because every one of the paths below used to
// be a bare `return`: convergence is the only way a host with no master can get
// one, and a fleet converging once a day was indistinguishable from one
// converging constantly. A refactor that drops these lines puts us back there,
// so the lines are behaviour, not decoration.
type capturingSink struct{}

func (capturingSink) Init(logr.RuntimeInfo)            {}
func (capturingSink) Enabled(int) bool                 { return true }
func (s capturingSink) WithValues(...any) logr.LogSink { return s }
func (s capturingSink) WithName(string) logr.LogSink   { return s }

func (capturingSink) Error(_ error, msg string, _ ...any) { recordLogMessage(msg) }
func (capturingSink) Info(_ int, msg string, _ ...any)    { recordLogMessage(msg) }

// controller-runtime's delegating logger can only be fulfilled ONCE, so the sink
// is installed a single time for the package and the buffer is reset per test
// rather than swapping loggers.
var (
	logCaptureOnce sync.Once
	logCaptureMu   sync.Mutex
	logCaptured    []string
)

func recordLogMessage(msg string) {
	logCaptureMu.Lock()
	defer logCaptureMu.Unlock()
	logCaptured = append(logCaptured, msg)
}

// captureLogs resets the capture buffer and returns a reader for it.
func captureLogs(t *testing.T) func() []string {
	t.Helper()
	logCaptureOnce.Do(func() { log.SetLogger(logr.New(capturingSink{})) })
	logCaptureMu.Lock()
	logCaptured = nil
	logCaptureMu.Unlock()
	return func() []string {
		logCaptureMu.Lock()
		defer logCaptureMu.Unlock()
		return append([]string(nil), logCaptured...)
	}
}

func stageHead(t *testing.T, statusDir string, head volumeHead) {
	t.Helper()
	b, err := json.Marshal(head)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(statusDir, volumeHeadFile), b, 0o644); err != nil {
		t.Fatal(err)
	}
}

// A HEAD whose stored object does not reproduce its advertised digest cannot be
// adopted by anyone, and a cold promote's base generation 0 is rejected while a
// HEAD exists — so declining is correct but, on its own, permanent. The host is
// the only party that has the evidence (it downloaded the object and measured
// it), and it has no server credentials, so it stages the disproved digest for
// the guest to report. Production ran one account cold on all nine hosts for days
// with nothing but a log line, which is what this staging is for.
func TestConvergeMasterReportsAHeadItCannotVerify(t *testing.T) {
	served := []byte("bytes-that-are-not-the-advertised-head")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(served)
	}))
	defer srv.Close()

	for _, tc := range []struct {
		name       string
		digestErr  error
		wantStaged bool
	}{
		{
			// Measured, and it is a different image: reproducible on every host
			// that fetches it, so it is worth reporting.
			name:       "measured a different image",
			wantStaged: true,
		},
		{
			// Could not measure it at all — a local fault (the read-only attach
			// failed, the disk is unhappy). That says nothing about the object, and
			// reporting it would retire a HEAD the rest of the fleet may be using
			// perfectly well.
			name:       "could not measure the image",
			digestErr:  errors.New("attach image read-only: resource busy"),
			wantStaged: false,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m, be := newTestManager(t, 100)
			be.digestErr = tc.digestErr
			statusDir := t.TempDir()
			stageHead(t, statusDir, volumeHead{
				Generation:  4,
				Digest:      "0000000000000000000000000000000000000000",
				DownloadURL: srv.URL,
			})
			r := &Reconciler{
				Volumes:                  m,
				ConvergeHeadWaitInterval: time.Millisecond,
				ConvergeHeadWaitAttempts: 2,
			}

			r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")

			// Either way the local master is untouched: the digest check is the guard
			// that stops a corrupt master propagating fleet-wide, and reporting does
			// not soften it.
			if masterExists(m, "42") {
				t.Fatal("adopted a master whose digest did not match the HEAD")
			}

			staged, err := os.ReadFile(filepath.Join(statusDir, unverifiableHeadFile))
			switch {
			case tc.wantStaged && err != nil:
				t.Fatalf("no unverifiable-HEAD report staged for the guest: %v", err)
			case tc.wantStaged && string(staged) != "0000000000000000000000000000000000000000":
				t.Fatalf("staged the wrong digest: %q", staged)
			case !tc.wantStaged && err == nil:
				t.Fatalf("staged %q from a local measurement failure", staged)
			}
		})
	}
}

func TestConvergeMasterExplainsWhyItSkipped(t *testing.T) {
	for _, tc := range []struct {
		name  string
		head  *volumeHead
		want  string
		setup func(t *testing.T, m *VolumeManager)
	}{
		{
			// The guest never staged the file within the wait. Points at the
			// guest or at the wait being too short, not at the server.
			name: "guest never staged the HEAD",
			head: nil,
			want: "guest never staged the volume HEAD",
		},
		{
			// Nothing published for the account yet, so there is nothing to
			// converge toward. Not a fault.
			name: "account has no published HEAD",
			head: &volumeHead{Generation: 0, DownloadURL: "https://example.invalid/x"},
			want: "account has no published HEAD yet",
		},
		{
			// A HEAD exists but arrived without a URL, which is what the server
			// withholding it from an untrusted (fork) dispatch looks like.
			name: "HEAD arrived without a download URL",
			head: &volumeHead{Generation: 7},
			want: "HEAD carries no download URL",
		},
		{
			// The healthy no-op, and the one that must be distinguishable from a
			// failure when asking why a fleet is not converging.
			name: "host already at the HEAD generation",
			head: &volumeHead{Generation: 3, DownloadURL: "https://example.invalid/x"},
			want: "host already at or past the HEAD",
			setup: func(t *testing.T, m *VolumeManager) {
				seedMasterGen(t, m, "42", masterImageContent("42"), 3)
			},
		},
		{
			// Object storage, as distinct from every skip above.
			name: "HEAD cannot be downloaded",
			head: &volumeHead{Generation: 9, DownloadURL: "http://127.0.0.1:1/missing"},
			want: "download master image",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			messages := captureLogs(t)
			m, _ := newTestManager(t, 100)
			if tc.setup != nil {
				tc.setup(t, m)
			}
			statusDir := t.TempDir()
			if tc.head != nil {
				stageHead(t, statusDir, *tc.head)
			}
			r := &Reconciler{
				Volumes:                  m,
				ConvergeHeadWaitInterval: time.Millisecond,
				ConvergeHeadWaitAttempts: 2,
			}

			r.convergeMaster("vm1", statusDir, ReservedTuistCacheVolume, "42")

			got := messages()
			for _, msg := range got {
				if strings.Contains(msg, tc.want) {
					return
				}
			}
			t.Fatalf("no log line mentioning %q; got %v", tc.want, got)
		})
	}
}
