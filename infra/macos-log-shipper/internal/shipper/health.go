package shipper

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// DefaultHealthPath is where the agent publishes its own health for
// node_exporter's textfile collector to pick up.
//
// This is the whole point of the file: the agent is the thing that reports, so
// when it breaks nothing reports, and "installed but failing" is
// indistinguishable from "not installed" from off-host. Twice that produced a
// multi-day outage while `launchctl print` cheerfully reported the job
// `running` with correct arguments. Through both investigations SSH to the minis
// hung and production kubectl never returned, while node_exporter's :9100
// answered instantly every time — so :9100 is the channel this signal rides.
//
// The directory is mirrored in macos-host-bootstrap's nodeExporterTextfileDir,
// which creates it and passes it to node_exporter as
// --collector.textfile.directory. They are separate Go modules, so the two
// sides agree by convention; changing one without the other publishes a file
// nothing reads.
const DefaultHealthPath = "/var/lib/node_exporter/textfile/tuist-log-shipper.prom"

// sourceHealth is one tailed source's health as the agent last observed it.
type sourceHealth struct {
	// lastSuccess is when a push last returned 2xx. Zero means never, which is
	// the state a freshly installed agent that has never delivered a line stays
	// in — the distinction the whole file exists to expose.
	lastSuccess int64
	failures    int64
	offset      int64
	size        int64
}

// Health publishes the agent's own health as a Prometheus textfile.
//
// A nil *Health is valid and does nothing, so a construction path that wants no
// health signal needs no branch on the hot path.
type Health struct {
	mu       sync.Mutex
	path     string
	build    string
	bySource map[string]*sourceHealth
	logf     func(format string, args ...any)
	// Only the first write failure is logged, for the same reason tail logs only
	// the first of a run of identical failures: a line per poll is tens of
	// thousands a day onto a disk whose free space already warrants a golden-image
	// GC.
	logged bool
}

// tempPattern is the name os.CreateTemp gives the pre-rename file.
//
// The suffix is NOT .prom, and that is the whole point: node_exporter selects
// the files it parses by that suffix, so a .prom temp is parsed too and the
// rename stops being atomic from the collector's point of view. Both outcomes
// were measured against node_exporter 1.8.2 on a production mini:
//
//   - Read mid-write, the partial file fails to parse. Only that file is lost
//     (node_textfile_scrape_error goes to 1 and no mtime series is emitted for
//     it); other files and other collectors are unaffected.
//   - Left behind by a crash between create and rename, it parses fine and
//     holds a COMPLETE copy of every series, with stale values. The collector
//     then serves whichever file the directory walk reaches first and silently
//     drops the duplicate from the other, with node_textfile_scrape_error
//     staying 0. A leftover sorting before the real file therefore pins this
//     agent's health at whatever it said — including a healthy-looking zero —
//     for as long as it exists, with no error metric anywhere.
//
// The second case is why the suffix matters more than the atomicity: a lost
// scrape is a gap, while a leftover is a lie that defeats the whole signal.
const tempPattern = ".tuist-log-shipper-*.tmp"

// NewHealth returns a writer publishing to path.
func NewHealth(path string, logf func(format string, args ...any)) *Health {
	h := &Health{
		path:     path,
		build:    buildInfoLine(),
		bySource: map[string]*sourceHealth{},
		logf:     logf,
	}
	h.removeStaleTemps()
	return h
}

// removeStaleTemps clears temp files an earlier run died holding.
//
// They are invisible to the collector, so this is about the disk rather than
// correctness: a launchd job with KeepAlive that crashes in that window on every
// start would otherwise accumulate them on hosts whose free space already
// warrants a golden-image GC. Construction is the safe moment for it, because
// this process has not opened one yet, and only one agent ever owns a given
// path.
func (h *Health) removeStaleTemps() {
	matches, err := filepath.Glob(filepath.Join(filepath.Dir(h.path), tempPattern))
	if err != nil {
		return
	}
	for _, match := range matches {
		_ = os.Remove(match)
	}
}

// Success records a push the receiver accepted.
func (h *Health) Success(job string, at time.Time) {
	h.record(job, func(state *sourceHealth) {
		state.lastSuccess = at.Unix()
		state.failures = 0
	})
}

// Failure records one failed attempt: a poll that could not read the file, or a
// single push attempt that did not land.
//
// Counting individual push attempts rather than poll outcomes is deliberate.
// push retries a retryable failure forever, so during a receiver outage poll
// never returns and a poll-boundary-only counter would publish nothing for the
// whole outage — the metric would freeze at whatever it read before the failure
// started, which is the same silence this file is meant to break. Counted per
// attempt, the number climbs and matches the `attempt N` the agent's own log
// carries.
func (h *Health) Failure(job string) {
	h.record(job, func(state *sourceHealth) { state.failures++ })
}

// Progress records how far the persisted position has got relative to the
// file's current size. Both are needed: the difference is the lag, and during an
// outage the offset stays put while the file grows.
func (h *Health) Progress(job string, offset, size int64) {
	h.record(job, func(state *sourceHealth) {
		state.offset = offset
		state.size = size
	})
}

// record mutates one source's state and republishes the whole document.
//
// Republishing on every outcome rather than on change is what makes the file's
// own mtime a liveness signal: node_exporter exposes it as
// node_textfile_mtime_seconds, so an agent that has died stops advancing it
// without needing a heartbeat metric of its own.
func (h *Health) record(job string, mutate func(*sourceHealth)) {
	if h == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	state, ok := h.bySource[job]
	if !ok {
		state = &sourceHealth{}
		h.bySource[job] = state
	}
	mutate(state)
	if err := h.write(); err != nil && !h.logged {
		h.logged = true
		h.logf("publish health metrics to %s: %v", h.path, err)
	}
}

// write renders every source and publishes the document atomically.
//
// The temp file goes in the target's own directory and is renamed into place, so
// a scrape landing mid-write reads the previous complete document rather than a
// half-written one. node_exporter isolates a parse failure to the file it
// happened in (measured, 1.8.2), so the cost of getting this wrong is not the
// host's other metrics: it is this agent's own health disappearing from the
// scrape exactly while something is wrong with it. Callers hold h.mu.
func (h *Health) write() error {
	dir := filepath.Dir(h.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("mkdir textfile dir: %w", err)
	}
	tmp, err := os.CreateTemp(dir, tempPattern)
	if err != nil {
		return fmt.Errorf("create textfile temp: %w", err)
	}
	tmpName := tmp.Name()
	cleanup := func(err error) error {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if _, err := tmp.WriteString(h.render()); err != nil {
		return cleanup(fmt.Errorf("write textfile temp: %w", err))
	}
	// CreateTemp makes the file 0600. The agent runs as root under launchd and
	// node_exporter runs from its own job, so a file only the writer can read is
	// a file the collector skips — which reads exactly like an agent that is not
	// running.
	if err := tmp.Chmod(0o644); err != nil {
		return cleanup(fmt.Errorf("chmod textfile temp: %w", err))
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("close textfile temp: %w", err)
	}
	if err := os.Rename(tmpName, h.path); err != nil {
		_ = os.Remove(tmpName)
		return fmt.Errorf("rename textfile: %w", err)
	}
	return nil
}

// sourceLabel names the tailed source a sample belongs to.
//
// Deliberately NOT `job`, even though the value IS the Loki `job` label the
// source's lines carry. `job` is a reserved target label: Prometheus scrapes
// with honor_labels=false (the default, and the macOS fleet's scrape does not
// override it), so a `job` in the exposition collides with the scrape's own
// job_name. The sample would arrive carrying job="tuist-macos-node-exporter"
// with our value silently moved to `exported_job`, and every query grouping by
// `job` would collapse all sources into one and label them with the scrape job.
const sourceLabel = "source_job"

// render builds the exposition document. Callers hold h.mu.
func (h *Health) render() string {
	sources := make([]string, 0, len(h.bySource))
	for source := range h.bySource {
		sources = append(sources, source)
	}
	sort.Strings(sources)

	var b strings.Builder
	if h.build != "" {
		b.WriteString("# HELP tuist_log_shipper_build_info Which log shipper binary this host is carrying.\n")
		b.WriteString("# TYPE tuist_log_shipper_build_info gauge\n")
		b.WriteString(h.build)
	}
	// Samples of one metric family have to be contiguous, so this writes family
	// by family rather than source by source.
	for _, family := range []struct {
		name, help string
		value      func(*sourceHealth) int64
	}{
		{
			"tuist_log_shipper_last_success_timestamp_seconds",
			"Unix time of the last push the receiver accepted. 0 means this source has never delivered a line.",
			func(s *sourceHealth) int64 { return s.lastSuccess },
		},
		{
			"tuist_log_shipper_consecutive_failures",
			"Failed read or push attempts since the last accepted push.",
			func(s *sourceHealth) int64 { return s.failures },
		},
		{
			"tuist_log_shipper_position_offset_bytes",
			"How far into the source file the agent has read AND successfully pushed.",
			func(s *sourceHealth) int64 { return s.offset },
		},
		{
			"tuist_log_shipper_source_size_bytes",
			"Current size of the source file. The gap to the offset is the shipping lag.",
			func(s *sourceHealth) int64 { return s.size },
		},
	} {
		fmt.Fprintf(&b, "# HELP %s %s\n# TYPE %s gauge\n", family.name, family.help, family.name)
		for _, source := range sources {
			fmt.Fprintf(&b, "%s{%s=\"%s\"} %s\n",
				family.name, sourceLabel, escapeLabelValue(source),
				strconv.FormatInt(family.value(h.bySource[source]), 10))
		}
	}
	return b.String()
}

// escapeLabelValue applies the exposition format's escaping. Job names come from
// the operator's --file flags, so this is not defence against a hostile value;
// it is defence against publishing a document node_exporter cannot parse, which
// is the one failure this file must never cause.
func escapeLabelValue(value string) string {
	return strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`).Replace(value)
}

// buildInfoLine identifies the binary that is running.
//
// Which binary a host was carrying was itself an open question during the last
// incident, and the place that answers it — HostConfigHash on the Machine — sits
// behind the kubectl gateway that never returned. binary_sha256 hashes the
// executable on disk, so it is the on-host bytes AFTER the bootstrap's ad-hoc
// re-sign rather than the operator's embedded SHA: it does not join against the
// image, but two hosts running the same build report the same value, which is
// what "did this roll actually reach this host?" needs.
//
// Returning "" is fine: an unhashable executable costs one series, not the file.
func buildInfoLine() string {
	fingerprint := executableSHA256()
	if fingerprint == "" {
		return ""
	}
	return fmt.Sprintf("tuist_log_shipper_build_info{binary_sha256=\"%s\",go_version=\"%s\"} 1\n",
		fingerprint, escapeLabelValue(runtime.Version()))
}

func executableSHA256() string {
	path, err := os.Executable()
	if err != nil {
		return ""
	}
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, f); err != nil {
		return ""
	}
	// Twelve hex characters, the same length git and container tooling use for a
	// human-comparable digest, because the value is read by eye across a fleet
	// table rather than joined against anything.
	return hex.EncodeToString(sum.Sum(nil))[:12]
}
