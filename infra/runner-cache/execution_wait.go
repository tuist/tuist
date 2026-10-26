package cachevolumes

import (
	"sync"
	"time"
)

// ExecutionWait is how long a runner Pod waits for GitHub to report the job its
// runner executes, across its checkout and all its volumes.
const ExecutionWait = 25 * time.Second

// ExecutionWaits holds when each Pod stops waiting for GitHub's job report. The
// zero value is ready to use.
type ExecutionWaits struct {
	mu    sync.Mutex
	until map[string]time.Time
}

// Deadline is when the Pod stops waiting. The first request the server answers
// 425 starts one wait of ExecutionWait from when it was asked, and the Pod's
// checkout and every later volume share it: GitHub can report a job minutes after
// it started, so a wait per request only delays a job that runs cold anyway. A
// request after the wait still asks the server once, so a report that arrived
// meanwhile still authorizes it.
func (w *ExecutionWaits) Deadline(podUID string, asked time.Time) time.Time {
	w.mu.Lock()
	defer w.mu.Unlock()
	if until, ok := w.until[podUID]; ok {
		return until
	}
	// A runner Pod lives for one job, which never outlasts six hours.
	for uid, until := range w.until {
		if time.Since(until) > 6*time.Hour {
			delete(w.until, uid)
		}
	}
	if w.until == nil {
		w.until = map[string]time.Time{}
	}
	until := asked.Add(ExecutionWait)
	w.until[podUID] = until
	return until
}
