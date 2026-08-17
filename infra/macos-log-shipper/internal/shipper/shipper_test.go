package shipper

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type capturedPush struct {
	Streams []struct {
		Stream map[string]string `json:"stream"`
		Values [][2]string       `json:"values"`
	} `json:"streams"`
}

// recorder is a stand-in Loki that records what it was sent and can be told to
// fail a given number of times first.
type recorder struct {
	mu       sync.Mutex
	pushes   []capturedPush
	failWith []int
}

func (r *recorder) handler() http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		r.mu.Lock()
		defer r.mu.Unlock()
		if len(r.failWith) > 0 {
			status := r.failWith[0]
			r.failWith = r.failWith[1:]
			w.WriteHeader(status)
			return
		}
		var push capturedPush
		if err := json.NewDecoder(req.Body).Decode(&push); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		r.pushes = append(r.pushes, push)
		w.WriteHeader(http.StatusNoContent)
	}
}

func (r *recorder) all() []capturedPush {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]capturedPush(nil), r.pushes...)
}

func newTestShipper(t *testing.T, path, url string) (*Shipper, *Positions) {
	t.Helper()
	positions := LoadPositions(filepath.Join(t.TempDir(), "positions.json"))
	agent, err := New(Options{
		Sources:      []Source{{Job: "tuist-macos-tart-kubelet", Path: path}},
		BaseLabels:   map[string]string{"instance": "tuist-runners-fleet-abc", "env": "staging"},
		Positions:    positions,
		Client:       &Client{URL: url},
		Health:       NewHealth(filepath.Join(t.TempDir(), "tuist-log-shipper.prom"), func(string, ...any) {}),
		PollInterval: time.Millisecond,
		Backoff:      Backoff{Initial: time.Millisecond, Max: 2 * time.Millisecond},
		Now:          func() time.Time { return time.Unix(1_770_000_000, 0) },
		Logf:         func(string, ...any) {},
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return agent, positions
}

func TestPollShipsWithJobInstanceAndLevelLabels(t *testing.T) {
	loki := &recorder{}
	server := httptest.NewServer(loki.handler())
	defer server.Close()

	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "")
	agent, _ := newTestShipper(t, path, server.URL)
	labels := map[string]string{"instance": "tuist-runners-fleet-abc", "env": "staging", "job": "tuist-macos-tart-kubelet"}

	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("initial poll: %v", err)
	}
	appendFile(t, path, `{"level":"info","ts":1770000000,"msg":"converged master to HEAD"}`+"\n"+
		`{"level":"error","ts":1770000001,"msg":"converge: download master image"}`+"\n")
	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("poll: %v", err)
	}

	pushes := loki.all()
	if len(pushes) != 1 {
		t.Fatalf("expected one push, got %d", len(pushes))
	}
	if len(pushes[0].Streams) != 2 {
		t.Fatalf("expected one stream per level, got %d", len(pushes[0].Streams))
	}
	for _, stream := range pushes[0].Streams {
		if stream.Stream["job"] != "tuist-macos-tart-kubelet" {
			t.Fatalf("job label = %q", stream.Stream["job"])
		}
		if stream.Stream["instance"] != "tuist-runners-fleet-abc" {
			t.Fatalf("instance label = %q", stream.Stream["instance"])
		}
		if stream.Stream["env"] != "staging" {
			t.Fatalf("env label = %q", stream.Stream["env"])
		}
	}
	if got := pushes[0].Streams[1].Stream["level"]; got != "info" {
		t.Fatalf("second stream level = %q, want info (levels are sorted)", got)
	}
}

// The first sight of a file takes its end as the start position and returns
// WITHOUT pushing anything, so an offset that equals the file size proves only
// that the agent saw the file — no network call happened. Reading it as proof of
// a successful push is what shipped a broken fix once.
//
// The health signal has to draw the same distinction: after first sight
// last_success is still 0, and only an append that actually lands moves it.
func TestFirstSightTakesAPositionWithoutPushingAndOnlyAnAppendReportsSuccess(t *testing.T) {
	loki := &recorder{}
	server := httptest.NewServer(loki.handler())
	defer server.Close()

	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	// A long-lived host's log is not empty when the agent is installed.
	writeFile(t, path, "months of history nobody asked for\n")
	agent, positions := newTestShipper(t, path, server.URL)
	labels := map[string]string{"job": "tuist-macos-tart-kubelet"}

	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("first-sight poll: %v", err)
	}
	firstSight, ok := positions.Get(path)
	if !ok {
		t.Fatal("expected first sight to persist a position")
	}
	if len(loki.all()) != 0 {
		t.Fatal("first sight must not push; an offset that equals the file size is not evidence of a push")
	}
	metrics := readMetrics(t, agent.opts.Health.path)
	if got := metrics[`tuist_log_shipper_last_success_timestamp_seconds{job="tuist-macos-tart-kubelet"}`]; got != 0 {
		t.Fatalf("last_success_timestamp_seconds = %v after first sight, want 0 — nothing was pushed", got)
	}
	if got := metrics[`tuist_log_shipper_position_offset_bytes{job="tuist-macos-tart-kubelet"}`]; got != float64(firstSight.Offset) {
		t.Fatalf("position_offset_bytes = %v, want the persisted first-sight offset %d", got, firstSight.Offset)
	}

	appendFile(t, path, `{"level":"info","ts":1770000000,"msg":"the line that proves the network works"}`+"\n")
	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("poll after append: %v", err)
	}

	after, _ := positions.Get(path)
	if after.Offset <= firstSight.Offset {
		t.Fatalf("offset did not advance past the first-sight mark: %d -> %d", firstSight.Offset, after.Offset)
	}
	if len(loki.all()) != 1 {
		t.Fatalf("expected exactly one push, got %d", len(loki.all()))
	}
	metrics = readMetrics(t, agent.opts.Health.path)
	if got := metrics[`tuist_log_shipper_last_success_timestamp_seconds{job="tuist-macos-tart-kubelet"}`]; got != 1_770_000_000 {
		t.Fatalf("last_success_timestamp_seconds = %v, want the push time 1770000000", got)
	}
	if got := metrics[`tuist_log_shipper_consecutive_failures{job="tuist-macos-tart-kubelet"}`]; got != 0 {
		t.Fatalf("consecutive_failures = %v after a successful push, want 0", got)
	}
	if got := metrics[`tuist_log_shipper_position_offset_bytes{job="tuist-macos-tart-kubelet"}`]; got != float64(after.Offset) {
		t.Fatalf("position_offset_bytes = %v, want %d", got, after.Offset)
	}
}

// The failure mode that was invisible for days: the job is `running`, its
// arguments are correct, and every push fails. push() retries a retryable
// failure forever, so poll() never returns and a poll-boundary-only writer would
// publish nothing at all for the duration. The count has to come from inside the
// retry loop.
func TestHealthCountsPushAttemptsWhileTheOffsetStaysPut(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "")
	health := NewHealth(filepath.Join(t.TempDir(), "tuist-log-shipper.prom"), func(string, ...any) {})
	positions := LoadPositions(filepath.Join(t.TempDir(), "positions.json"))
	agent, err := New(Options{
		Sources:      []Source{{Job: "job", Path: path}},
		Positions:    positions,
		Client:       &Client{URL: "http://127.0.0.1:1/loki/api/v1/push"},
		Health:       health,
		PollInterval: time.Millisecond,
		Backoff:      Backoff{Initial: time.Millisecond, Max: time.Millisecond},
		Now:          func() time.Time { return time.Unix(1_770_000_000, 0) },
		Logf:         func(string, ...any) {},
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], map[string]string{"job": "job"}); err != nil {
		t.Fatalf("first-sight poll: %v", err)
	}
	firstSight, _ := positions.Get(path)
	appendFile(t, path, "a line that can never land\n")

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); agent.tail(ctx, agent.opts.Sources[0]) }()
	time.Sleep(150 * time.Millisecond)
	cancel()
	<-done

	metrics := readMetrics(t, health.path)
	if got := metrics[`tuist_log_shipper_consecutive_failures{job="job"}`]; got < 3 {
		t.Fatalf("consecutive_failures = %v, want the retry loop's attempts to be visible", got)
	}
	if got := metrics[`tuist_log_shipper_last_success_timestamp_seconds{job="job"}`]; got != 0 {
		t.Fatalf("last_success_timestamp_seconds = %v, want 0 — nothing ever landed", got)
	}
	// Lag is visible because the offset is frozen at first sight while the file
	// grew past it.
	offset := metrics[`tuist_log_shipper_position_offset_bytes{job="job"}`]
	size := metrics[`tuist_log_shipper_source_size_bytes{job="job"}`]
	if offset != float64(firstSight.Offset) || size <= offset {
		t.Fatalf("offset = %v, size = %v; want the offset frozen at %d with the file grown past it", offset, size, firstSight.Offset)
	}
}

// A textfile the agent cannot write is a lost health signal. Losing the logs too
// would make the observability change strictly worse than not having it.
func TestAFailingHealthWriteDoesNotStopShipping(t *testing.T) {
	loki := &recorder{}
	server := httptest.NewServer(loki.handler())
	defer server.Close()

	dir := t.TempDir()
	blocker := filepath.Join(dir, "textfile")
	if err := os.WriteFile(blocker, []byte("not a directory"), 0o644); err != nil {
		t.Fatalf("write blocker: %v", err)
	}

	path := filepath.Join(dir, "tart-kubelet.log")
	writeFile(t, path, "")
	var logged []string
	agent, positions := newTestShipper(t, path, server.URL)
	agent.opts.Health = NewHealth(filepath.Join(blocker, "tuist-log-shipper.prom"), func(format string, _ ...any) {
		logged = append(logged, format)
	})
	labels := map[string]string{"job": "tuist-macos-tart-kubelet"}

	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("first-sight poll: %v", err)
	}
	appendFile(t, path, "a line\n")
	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("poll: %v", err)
	}

	if len(loki.all()) != 1 {
		t.Fatalf("expected the line to ship despite the unwritable textfile, got %d pushes", len(loki.all()))
	}
	if _, ok := positions.Get(path); !ok {
		t.Fatal("expected the position to advance despite the unwritable textfile")
	}
	if len(logged) != 1 {
		t.Fatalf("expected the write failure to be logged once, got %d: %v", len(logged), logged)
	}
}

func TestPollDoesNotAdvanceWhenThePushFails(t *testing.T) {
	loki := &recorder{failWith: []int{http.StatusServiceUnavailable}}
	server := httptest.NewServer(loki.handler())
	defer server.Close()

	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "")
	agent, positions := newTestShipper(t, path, server.URL)
	labels := map[string]string{"job": "tuist-macos-tart-kubelet"}

	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("initial poll: %v", err)
	}
	before, _ := positions.Get(path)

	appendFile(t, path, `{"level":"info","ts":1770000000,"msg":"first"}`+"\n")
	// The 503 is retried; the retry succeeds, and only then does the offset move.
	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("poll: %v", err)
	}
	after, _ := positions.Get(path)
	if after.Offset <= before.Offset {
		t.Fatalf("offset did not advance after the retry succeeded: %d -> %d", before.Offset, after.Offset)
	}
	if len(loki.all()) != 1 {
		t.Fatalf("expected the batch to land exactly once, got %d pushes", len(loki.all()))
	}
}

func TestPollDropsAndAdvancesPastAPermanentRejection(t *testing.T) {
	// Loki answering 400 (entry too old, bad label) is not survivable by
	// retrying. Blocking on it would stall every later line behind lines that
	// can never be accepted.
	loki := &recorder{failWith: []int{http.StatusBadRequest}}
	server := httptest.NewServer(loki.handler())
	defer server.Close()

	path := filepath.Join(t.TempDir(), "tart-kubelet.log")
	writeFile(t, path, "")
	agent, positions := newTestShipper(t, path, server.URL)
	labels := map[string]string{"job": "tuist-macos-tart-kubelet"}

	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("initial poll: %v", err)
	}
	appendFile(t, path, `{"level":"info","ts":1770000000,"msg":"rejected"}`+"\n")
	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("poll: %v", err)
	}

	appendFile(t, path, `{"level":"info","ts":1770000001,"msg":"accepted"}`+"\n")
	if _, err := agent.poll(context.Background(), agent.opts.Sources[0], labels); err != nil {
		t.Fatalf("poll: %v", err)
	}
	pushes := loki.all()
	if len(pushes) != 1 {
		t.Fatalf("expected the second batch to land, got %d pushes", len(pushes))
	}
	if pushes[0].Streams[0].Values[0][1] != `{"level":"info","ts":1770000001,"msg":"accepted"}` {
		t.Fatalf("expected the shipper to have moved past the rejected batch, got %q", pushes[0].Streams[0].Values[0][1])
	}
	if _, ok := positions.Get(path); !ok {
		t.Fatal("expected a persisted position")
	}
}

func TestPositionsSurviveARestart(t *testing.T) {
	loki := &recorder{}
	server := httptest.NewServer(loki.handler())
	defer server.Close()

	dir := t.TempDir()
	path := filepath.Join(dir, "tart-kubelet.log")
	positionsPath := filepath.Join(dir, "positions.json")
	writeFile(t, path, "")

	run := func() {
		agent, err := New(Options{
			Sources:      []Source{{Job: "job", Path: path}},
			Positions:    LoadPositions(positionsPath),
			Client:       &Client{URL: server.URL},
			PollInterval: time.Millisecond,
			Now:          time.Now,
			Logf:         func(string, ...any) {},
		})
		if err != nil {
			t.Fatalf("New: %v", err)
		}
		if _, err := agent.poll(context.Background(), agent.opts.Sources[0], map[string]string{"job": "job"}); err != nil {
			t.Fatalf("poll: %v", err)
		}
	}

	run()
	appendFile(t, path, "first\n")
	run()
	// A restart between polls must not re-ship what already landed, and must
	// not skip to the new end either.
	appendFile(t, path, "second\n")
	run()

	pushes := loki.all()
	if len(pushes) != 2 {
		t.Fatalf("expected two pushes, got %d", len(pushes))
	}
	if got := pushes[1].Streams[0].Values[0][1]; got != "second" {
		t.Fatalf("second push carried %q, want the line written after the restart", got)
	}
}

func TestLoadPositionsToleratesACorruptFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "positions.json")
	if err := os.WriteFile(path, []byte(`{"/var/log/tart-kubelet.log":{"inode":1,`), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	if _, ok := LoadPositions(path).Get("/var/log/tart-kubelet.log"); ok {
		t.Fatal("expected a truncated positions file to read as empty")
	}
}

func TestBackoffCapsAtMax(t *testing.T) {
	b := Backoff{Initial: time.Second, Max: 8 * time.Second}
	for attempt, want := range map[int]time.Duration{0: time.Second, 1: 2 * time.Second, 3: 8 * time.Second, 20: 8 * time.Second} {
		if got := b.Next(attempt); got != want {
			t.Fatalf("Next(%d) = %v, want %v", attempt, got, want)
		}
	}
}

func TestTailLogsARepeatingFailureOnce(t *testing.T) {
	// The agent is installed before tart-kubelet's launchd job creates its log
	// sink, so "file does not exist" is the normal startup state, not an
	// anomaly. Logging it every poll would fill the host's disk with the
	// agent's own complaints about not having anything to ship.
	var mu sync.Mutex
	var logged []string
	positions := LoadPositions(filepath.Join(t.TempDir(), "positions.json"))
	agent, err := New(Options{
		Sources:      []Source{{Job: "job", Path: filepath.Join(t.TempDir(), "absent.log")}},
		Positions:    positions,
		Client:       &Client{URL: "http://127.0.0.1:1/loki/api/v1/push"},
		PollInterval: time.Millisecond,
		Now:          time.Now,
		Logf: func(format string, args ...any) {
			mu.Lock()
			defer mu.Unlock()
			logged = append(logged, format)
		},
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { defer close(done); agent.tail(ctx, agent.opts.Sources[0]) }()
	time.Sleep(50 * time.Millisecond)
	cancel()
	<-done

	mu.Lock()
	defer mu.Unlock()
	if len(logged) != 1 {
		t.Fatalf("expected the repeated failure to be logged once, got %d lines", len(logged))
	}
}

// Run gives every --file source its own goroutine against one shared positions
// store, so two sources persisting offsets is the normal case, not an edge one.
// Unsynchronised, this races the map and interleaves the temp-file writes, and
// the surviving rename can be missing an offset the other source already
// advanced — which silently re-ships everything after it.
func TestPositionsAreSafeForConcurrentSources(t *testing.T) {
	positions := LoadPositions(filepath.Join(t.TempDir(), "positions.json"))
	paths := []string{"/var/log/tart-kubelet.log", "/var/log/tart-vms/a.log", "/var/log/tart-vms/b.log"}

	var wg sync.WaitGroup
	for i, path := range paths {
		wg.Add(1)
		go func(i int, path string) {
			defer wg.Done()
			for offset := 1; offset <= 50; offset++ {
				if err := positions.Set(path, Position{Inode: uint64(i + 1), Offset: int64(offset)}); err != nil {
					t.Errorf("Set(%s): %v", path, err)
					return
				}
				if _, ok := positions.Get(path); !ok {
					t.Errorf("Get(%s) lost the position it just stored", path)
					return
				}
			}
		}(i, path)
	}
	wg.Wait()

	// Every source's final offset has to be in the store, and in the file: a
	// lost writer here is a source that re-ships its whole backlog on restart.
	for i, path := range paths {
		got, ok := positions.Get(path)
		if !ok {
			t.Fatalf("%s is missing from the store", path)
		}
		if got.Offset != 50 || got.Inode != uint64(i+1) {
			t.Fatalf("%s = %+v, want inode %d offset 50", path, got, i+1)
		}
	}
	reloaded := LoadPositions(positions.path)
	for i, path := range paths {
		got, ok := reloaded.Get(path)
		if !ok {
			t.Fatalf("%s did not survive the flush", path)
		}
		if got.Offset != 50 || got.Inode != uint64(i+1) {
			t.Fatalf("persisted %s = %+v, want inode %d offset 50", path, got, i+1)
		}
	}
}
