package sandbox

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

// slowReadiness is how long a guest may take to answer before its readiness
// pings are logged at info: a healthy restore answers in milliseconds.
const slowReadiness = 2 * time.Second

// maxLoggedPings bounds the pings a readiness line lists. Fast refusals are
// counted but not listed; the slow ones are what tell a guest that answers
// late from one that never answers.
const maxLoggedPings = 16

// readinessLog collects one restore's readiness pings for a single log line.
type readinessLog struct {
	attempts int
	counts   map[string]int
	slow     []string
	dropped  int
}

func newReadinessLog() *readinessLog {
	return &readinessLog{counts: map[string]int{}}
}

func (r *readinessLog) add(a vsock.PingAttempt) {
	r.attempts++
	class := pingClass(a.Err)
	r.counts[class]++
	if a.Err != nil && a.Duration < 500*time.Millisecond {
		return
	}
	if len(r.slow) == maxLoggedPings {
		r.slow = r.slow[1:]
		r.dropped++
	}
	r.slow = append(r.slow, fmt.Sprintf("%s+%s/%s:%s", round(a.At), round(a.Duration), round(a.Budget), class))
}

// report logs the pings of a restore that answered slowly or never, and the
// rest at debug.
func (r *readinessLog) report(log *slog.Logger, id string, elapsed time.Duration, err error) {
	level := slog.LevelDebug
	if err != nil || elapsed >= slowReadiness {
		level = slog.LevelInfo
	}
	outcome := "ready"
	if err != nil {
		outcome = "not_ready"
	}
	counts := make([]string, 0, len(r.counts))
	for _, class := range []string{"answered", "timeout", "refused", "other"} {
		if n := r.counts[class]; n > 0 {
			counts = append(counts, fmt.Sprintf("%s=%d", class, n))
		}
	}
	log.Log(context.Background(), level, "guest agent readiness", "sandbox", id, "outcome", outcome,
		"elapsed", round(elapsed), "attempts", r.attempts, "counts", strings.Join(counts, " "),
		"slow_pings", strings.Join(r.slow, " "), "slow_pings_dropped", r.dropped)
}

func pingClass(err error) string {
	switch {
	case err == nil:
		return "answered"
	case errors.Is(err, context.DeadlineExceeded), errors.Is(err, os.ErrDeadlineExceeded):
		return "timeout"
	case errors.Is(err, syscall.ECONNREFUSED):
		return "refused"
	default:
		return "other"
	}
}

func round(d time.Duration) time.Duration { return d.Round(10 * time.Millisecond) }
