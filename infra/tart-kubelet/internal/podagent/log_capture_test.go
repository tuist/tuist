package podagent

import (
	"fmt"
	"sync"
	"testing"

	"github.com/go-logr/logr"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// capturingSink records log messages so a test can assert a code path said something.
type capturingSink struct{}

func (capturingSink) Init(logr.RuntimeInfo)            {}
func (capturingSink) Enabled(int) bool                 { return true }
func (s capturingSink) WithValues(...any) logr.LogSink { return s }
func (s capturingSink) WithName(string) logr.LogSink   { return s }

func (capturingSink) Error(_ error, msg string, kv ...any) { recordLogMessage(withValues(msg, kv)) }
func (capturingSink) Info(_ int, msg string, kv ...any)    { recordLogMessage(withValues(msg, kv)) }

// withValues appends the call's key/value pairs so a test can assert on them;
// tests matching a message by substring are unaffected.
func withValues(msg string, kv []any) string {
	for i := 0; i+1 < len(kv); i += 2 {
		msg += fmt.Sprintf(" %v=%v", kv[i], kv[i+1])
	}
	return msg
}

// controller-runtime's delegating logger can only be fulfilled ONCE, and it
// falls back to a null logger 30s after start if nothing has fulfilled it, so
// the sink is installed at init rather than on first use, and the buffer is
// reset per test rather than swapping loggers.
func init() { log.SetLogger(logr.New(capturingSink{})) }

var (
	logCaptureMu sync.Mutex
	logCaptured  []string
)

func recordLogMessage(msg string) {
	logCaptureMu.Lock()
	defer logCaptureMu.Unlock()
	logCaptured = append(logCaptured, msg)
}

// captureLogs resets the capture buffer and returns a reader for it.
func captureLogs(t *testing.T) func() []string {
	t.Helper()
	logCaptureMu.Lock()
	logCaptured = nil
	logCaptureMu.Unlock()
	return func() []string {
		logCaptureMu.Lock()
		defer logCaptureMu.Unlock()
		return append([]string(nil), logCaptured...)
	}
}
