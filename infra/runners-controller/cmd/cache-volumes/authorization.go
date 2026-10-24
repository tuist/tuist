package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// executionWait is how long a Pod waits for GitHub to report the job its runner
// executes, across its checkout and all its volumes.
const executionWait = 25 * time.Second

// executionWaits holds when each Pod stops waiting for GitHub's job report.
type executionWaits struct {
	mu    sync.Mutex
	until map[string]time.Time
}

// deadline is when the Pod stops waiting. The first request answered 425 starts
// one wait of executionWait from when it was asked, and the Pod's checkout and
// every later volume share it: GitHub can report a job minutes after it started,
// so a wait per request only delays a job that runs cold anyway.
func (w *executionWaits) deadline(podUID string, asked time.Time) time.Time {
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
	until := asked.Add(executionWait)
	w.until[podUID] = until
	return until
}

func (a *agent) authorize(ctx context.Context, podUID string, asked time.Time, body []byte) (cachevolumes.Identity, error) {
	var identity cachevolumes.Identity
	err := a.allocate(ctx, a.authorizeURL, podUID, asked, body, &identity)
	return identity, err
}

// allocate asks the server for a use and decodes it into result. A request made
// after the Pod's wait for GitHub's job report ended still asks once, so a report
// that arrived meanwhile authorizes it.
func (a *agent) allocate(ctx context.Context, url, podUID string, asked time.Time, body []byte, result any) error {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	waiting := ctx
	for {
		status, err := a.allocateOnce(waiting, url, body, result)
		if waiting != ctx && waiting.Err() != nil && status != http.StatusOK {
			return cachevolumes.ErrExecutionPending
		}
		if err != nil || status == http.StatusOK {
			return err
		}
		// The volume is larger than this host's maximum. Retrying cannot help.
		if status == http.StatusInsufficientStorage {
			return cachevolumes.ErrCapacity
		}
		if status != http.StatusTooEarly {
			return fmt.Errorf("authorization rejected: %d", status)
		}
		// GitHub may deliver its verified execution binding after the action starts.
		// Retry only that explicit pending state, never denied provider identity.
		if waiting == ctx {
			var stop context.CancelFunc
			waiting, stop = context.WithDeadline(ctx, a.executionWaits.deadline(podUID, asked))
			defer stop()
		}
		select {
		case <-waiting.Done():
			return cachevolumes.ErrExecutionPending
		case <-time.After(time.Second):
		}
	}
}

func (a *agent) allocateOnce(ctx context.Context, url string, body []byte, result any) (status int, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	token, err := os.ReadFile(a.tokenPath)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	response, err := cachevolumes.DoServer(a.http, req, a.log)
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusOK {
		err = json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(result)
	}
	return response.StatusCode, err
}
