package shipper

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// readMetrics parses the textfile the way node_exporter's textfile collector
// does: every non-comment line is `<name>{<labels>} <value>`. The returned map
// is keyed by the whole series identifier so a test can assert on one label set.
func readMetrics(t *testing.T, path string) map[string]float64 {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return parseMetrics(t, string(raw))
}

func parseMetrics(t *testing.T, raw string) map[string]float64 {
	t.Helper()
	out := map[string]float64{}
	for _, line := range strings.Split(raw, "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		series, value, ok := strings.Cut(line, " ")
		if !ok {
			t.Fatalf("line %q is not <series> <value>", line)
		}
		parsed, err := strconv.ParseFloat(value, 64)
		if err != nil {
			t.Fatalf("line %q has an unparseable value: %v", line, err)
		}
		if _, dup := out[series]; dup {
			t.Fatalf("series %q appears twice; node_exporter rejects a duplicate", series)
		}
		out[series] = parsed
	}
	return out
}

func newTestHealth(t *testing.T) *Health {
	t.Helper()
	return NewHealth(filepath.Join(t.TempDir(), "tuist-log-shipper.prom"), func(string, ...any) {})
}

func TestHealthRecordsLastSuccessAndResetsConsecutiveFailures(t *testing.T) {
	health := newTestHealth(t)

	health.Failure("tuist-macos-tart-kubelet")
	health.Failure("tuist-macos-tart-kubelet")
	metrics := readMetrics(t, health.path)
	if got := metrics[`tuist_log_shipper_consecutive_failures{source_job="tuist-macos-tart-kubelet"}`]; got != 2 {
		t.Fatalf("consecutive_failures = %v, want 2", got)
	}
	// A stale last_success next to a growing failure count is the whole signal:
	// an agent that has never delivered a line reports 0 here, and "installed
	// but failing" stops looking like "not installed".
	if got := metrics[`tuist_log_shipper_last_success_timestamp_seconds{source_job="tuist-macos-tart-kubelet"}`]; got != 0 {
		t.Fatalf("last_success_timestamp_seconds = %v, want 0 before any push landed", got)
	}

	health.Success("tuist-macos-tart-kubelet", time.Unix(1_770_000_000, 0))
	metrics = readMetrics(t, health.path)
	if got := metrics[`tuist_log_shipper_consecutive_failures{source_job="tuist-macos-tart-kubelet"}`]; got != 0 {
		t.Fatalf("consecutive_failures = %v, want 0 after a success", got)
	}
	if got := metrics[`tuist_log_shipper_last_success_timestamp_seconds{source_job="tuist-macos-tart-kubelet"}`]; got != 1_770_000_000 {
		t.Fatalf("last_success_timestamp_seconds = %v, want 1770000000", got)
	}
}

// Lag is the difference between the two, so both have to be published, and the
// offset has to be the one that was persisted rather than the one the tail is
// about to attempt — during a receiver outage the offset stays put while the
// file grows, and that gap is the lag.
func TestHealthPublishesOffsetAndSourceSize(t *testing.T) {
	health := newTestHealth(t)
	health.Progress("job", 4096, 65536)

	metrics := readMetrics(t, health.path)
	if got := metrics[`tuist_log_shipper_position_offset_bytes{source_job="job"}`]; got != 4096 {
		t.Fatalf("position_offset_bytes = %v, want 4096", got)
	}
	if got := metrics[`tuist_log_shipper_source_size_bytes{source_job="job"}`]; got != 65536 {
		t.Fatalf("source_size_bytes = %v, want 65536", got)
	}
}

// Which binary a host is carrying was itself a question during the outage, and
// kubectl (where HostConfigHash is stamped) was the channel that did not answer.
func TestHealthPublishesBuildInfo(t *testing.T) {
	health := newTestHealth(t)
	health.Failure("job")

	raw, err := os.ReadFile(health.path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !strings.Contains(string(raw), "tuist_log_shipper_build_info{") {
		t.Fatalf("no build_info series\n%s", raw)
	}
	for series, value := range parseMetrics(t, string(raw)) {
		if strings.HasPrefix(series, "tuist_log_shipper_build_info{") && value != 1 {
			t.Fatalf("%s = %v, want 1", series, value)
		}
	}
}

// One file carries every source, so a per-source update has to republish the
// whole set. Dropping the other sources' series would make a second tailed file
// read as "never succeeded" every time the first one polled.
func TestHealthKeepsEverySourceOnAPerSourceUpdate(t *testing.T) {
	health := newTestHealth(t)
	health.Success("first", time.Unix(1_770_000_000, 0))
	health.Success("second", time.Unix(1_770_000_001, 0))
	health.Failure("first")

	metrics := readMetrics(t, health.path)
	if got := metrics[`tuist_log_shipper_last_success_timestamp_seconds{source_job="second"}`]; got != 1_770_000_001 {
		t.Fatalf("second source's last success = %v, want 1770000001", got)
	}
	if got := metrics[`tuist_log_shipper_consecutive_failures{source_job="first"}`]; got != 1 {
		t.Fatalf("first source's failures = %v, want 1", got)
	}
}

// node_exporter reads the directory on every scrape, so a reader can land
// mid-write. A partial document fails to parse, and node_exporter isolates that
// to the file it happened in: the cost is this agent's own health vanishing from
// the scrape exactly while something is wrong with it.
func TestHealthWritesAtomically(t *testing.T) {
	health := newTestHealth(t)
	health.Success("job", time.Unix(1_770_000_000, 0))

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < 300; i++ {
			health.Progress("job", int64(i), int64(i)*4096)
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 300; i++ {
			raw, err := os.ReadFile(health.path)
			if err != nil {
				t.Errorf("read during write: %v", err)
				return
			}
			// Every rename publishes a complete document, so the last byte is
			// always the newline that ends the last sample.
			if !strings.HasSuffix(string(raw), "\n") {
				t.Errorf("read a partially written document (%d bytes, no trailing newline)", len(raw))
				return
			}
			if strings.Count(string(raw), "tuist_log_shipper_source_size_bytes{source_job=\"job\"}") != 1 {
				t.Errorf("read an incomplete document:\n%s", raw)
				return
			}
		}
	}()
	wg.Wait()

	// The temp file has to be created in the target's own directory, or the
	// rename crosses devices and stops being atomic. Nothing may be left behind.
	entries, err := os.ReadDir(filepath.Dir(health.path))
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != filepath.Base(health.path) {
		names := make([]string, 0, len(entries))
		for _, entry := range entries {
			names = append(names, entry.Name())
		}
		t.Fatalf("expected only %s in the collector directory, got %v", filepath.Base(health.path), names)
	}
}

// node_exporter selects the files it parses by their .prom suffix, so a temp
// file carrying that suffix is read too and the rename stops being atomic from
// the collector's point of view.
//
// The dangerous half is not the mid-write read (a parse failure, isolated to that
// file) but the crash leftover: it is a COMPLETE document with stale values, and
// two files holding the same series with different values make node_exporter
// serve whichever the directory walk reaches first and silently drop the other,
// with node_textfile_scrape_error staying 0. Both measured against 1.8.2 on a
// production mini.
func TestHealthTempFileIsInvisibleToTheCollector(t *testing.T) {
	health := newTestHealth(t)
	dir := filepath.Dir(health.path)
	// filepath.Glob matches leading dots, exactly as node_exporter's suffix
	// selection does, so a dot prefix alone hides nothing.
	collectorGlob := filepath.Join(dir, "*.prom")
	// Publish once up front so the target exists: the assertion below is about
	// what the collector sees ALONGSIDE it, not about the moment before the
	// agent's first write.
	health.Progress("tuist-macos-tart-kubelet", 0, 0)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < 400; i++ {
			health.Progress("tuist-macos-tart-kubelet", int64(i), int64(i)*4096)
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 400; i++ {
			matches, err := filepath.Glob(collectorGlob)
			if err != nil {
				t.Errorf("glob: %v", err)
				return
			}
			if len(matches) != 1 || matches[0] != health.path {
				t.Errorf("node_exporter would parse %d files, want only %s: %v", len(matches), health.path, matches)
				return
			}
		}
	}()
	wg.Wait()
}

// A crash in the window between create and rename leaves a temp file behind.
// It is invisible to the collector once it is not a .prom, but a launchd job
// with KeepAlive that crashes there on every start would still accumulate them
// on a disk these hosts already watch closely enough to run a golden-image GC.
func TestHealthRemovesTempFilesLeftBehindByAnEarlierCrash(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tuist-log-shipper.prom")
	stale := filepath.Join(dir, ".tuist-log-shipper-123456.tmp")
	if err := os.WriteFile(stale, []byte("half a document"), 0o600); err != nil {
		t.Fatalf("write stale temp: %v", err)
	}
	// A file that is not ours must survive: the directory is shared with any
	// other host agent that publishes through the same collector.
	foreign := filepath.Join(dir, "someone-else.prom")
	if err := os.WriteFile(foreign, []byte("# HELP other_metric x\n"), 0o644); err != nil {
		t.Fatalf("write foreign file: %v", err)
	}

	NewHealth(path, func(string, ...any) {}).Failure("job")

	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Fatalf("expected the stale temp to be removed, stat returned %v", err)
	}
	if _, err := os.Stat(foreign); err != nil {
		t.Fatalf("another agent's file was removed: %v", err)
	}
}

// `job` is a reserved target label. Prometheus scrapes with honor_labels=false
// (the Alloy default, and the macOS fleet's scrape does not set it), so a `job`
// in the exposition collides with the scrape's own job_name: the series arrives
// carrying job="tuist-macos-node-exporter" with our value moved to
// `exported_job`. Every query grouping by `job` would then collapse all sources
// into one and label them with the scrape job.
func TestHealthDoesNotEmitTheReservedJobLabel(t *testing.T) {
	health := newTestHealth(t)
	health.Success("tuist-macos-tart-kubelet", time.Unix(1_770_000_000, 0))

	raw, err := os.ReadFile(health.path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if strings.Contains(string(raw), `{job=`) || strings.Contains(string(raw), `,job=`) {
		t.Fatalf("exposition carries the reserved `job` label; it would be renamed to exported_job at scrape time\n%s", raw)
	}
	if got := readMetrics(t, health.path)[`tuist_log_shipper_last_success_timestamp_seconds{source_job="tuist-macos-tart-kubelet"}`]; got != 1_770_000_000 {
		t.Fatalf("expected the source to be labelled source_job, got:\n%s", raw)
	}
}

// node_exporter may not be running as the same user as the shipper (which is
// root under launchd). A file only the writer can read is a file the collector
// silently skips.
func TestHealthFileIsReadableByTheCollector(t *testing.T) {
	health := newTestHealth(t)
	health.Failure("job")

	info, err := os.Stat(health.path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o644 {
		t.Fatalf("mode = %v, want 0644 so node_exporter can read it", perm)
	}
	dir, err := os.Stat(filepath.Dir(health.path))
	if err != nil {
		t.Fatalf("stat dir: %v", err)
	}
	if perm := dir.Mode().Perm(); perm&0o055 != 0o055 {
		t.Fatalf("directory mode = %v, want it traversable and readable by the collector", perm)
	}
}

// The directory is created by the node_exporter install step, which runs before
// the shipper's — but the agent must not depend on that ordering, or a host
// carrying the shipper without node_exporter publishes nothing.
func TestHealthCreatesTheCollectorDirectory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "node_exporter", "textfile", "tuist-log-shipper.prom")
	health := NewHealth(path, func(string, ...any) {})
	health.Failure("job")

	if _, err := os.Stat(path); err != nil {
		t.Fatalf("expected the collector directory to be created: %v", err)
	}
}

// A textfile that cannot be written is a lost health signal, not a reason to
// stop shipping logs. It is logged once, for the same reason tail logs a
// repeating failure once: a line per poll fills a disk that is already watched.
func TestHealthLogsAWriteFailureOnce(t *testing.T) {
	dir := t.TempDir()
	blocker := filepath.Join(dir, "textfile")
	if err := os.WriteFile(blocker, []byte("not a directory"), 0o644); err != nil {
		t.Fatalf("write blocker: %v", err)
	}

	var logged []string
	health := NewHealth(filepath.Join(blocker, "tuist-log-shipper.prom"), func(format string, _ ...any) {
		logged = append(logged, format)
	})
	for i := 0; i < 5; i++ {
		health.Failure("job")
	}
	if len(logged) != 1 {
		t.Fatalf("expected one log line for a repeating write failure, got %d: %v", len(logged), logged)
	}
}

// A job label with a quote in it would close the label value early and make the
// whole directory unparseable — the failure mode this file exists to avoid.
func TestHealthEscapesLabelValues(t *testing.T) {
	health := newTestHealth(t)
	health.Failure(`job"\` + "\n")

	raw, err := os.ReadFile(health.path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !strings.Contains(string(raw), `{source_job="job\"\\\n"}`) {
		t.Fatalf("label value is not escaped\n%s", raw)
	}
	parseMetrics(t, string(raw))
}

// A nil writer is how every construction path that does not want a health
// signal (tests, a run with the textfile disabled) stays valid. It must not
// panic on the hot path.
func TestHealthIsNilSafe(t *testing.T) {
	var health *Health
	health.Failure("job")
	health.Success("job", time.Unix(1, 0))
	health.Progress("job", 1, 2)
}
