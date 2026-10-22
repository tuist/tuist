package podagent

import (
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
	corev1 "k8s.io/api/core/v1"
)

const runnerPodLabel = "tuist.dev/runner"

// StatusDirForPod is the guest-writable status share of a runner Pod's VM, or "" for any other Pod.
func StatusDirForPod(t *tart.Client, pod *corev1.Pod, vm string) string {
	if t == nil || pod == nil || pod.Labels[runnerPodLabel] != "true" {
		return ""
	}
	dir, err := t.StatusDir(vm)
	if err != nil {
		return ""
	}
	return dir
}

// runnerExitFile is the file the guest writes into the writable status
// share from its EXIT trap, carrying dispatch-poll.sh's exit code. It is
// the only way that code reaches the host: the trap halts the VM on every
// path, so `tart run` exits zero whether the job finished or the runner
// died, and its status cannot distinguish the two.
//
// Absent for a guest killed without running its trap, and for any Pod
// without a status share. Absence therefore means "unknown", never "clean" —
// see runnerTermination.
const runnerExitFile = "runner-rc"

// runnerLogFile is dispatch-poll.sh's own output, mirrored into the
// writable status share by the guest so it outlives the VM. The copy
// inside the guest (/var/log/tuist-runner/poll.log) dies with the VM at
// teardown, and Tart cannot capture a macOS guest's console, so without
// this the host has an exit code and nothing that explains it.
//
// That gap is not academic: the trap reports 0 both for a finished job
// and for a runner that halted without ever taking one, so the exit code
// alone cannot tell those apart. This file is what does.
//
// Absent for the same two reasons as runnerExitFile — a guest killed
// before its trap ran, and Pods without a status share.
const runnerLogFile = "runner.log"

// runnerLogTailLines / runnerLogTailBytes bound what publishRunnerLog
// re-emits. dispatch-poll.sh is quiet by design — the job's own output
// goes to GitHub server-side, so this log is warm-standby ticks plus the
// cache teardown trail — but the file is guest-writable, so it is bounded
// rather than trusted.
const (
	runnerLogTailLines = 200
	runnerLogTailBytes = 64 << 10
)

// openGuestFile opens a file the guest wrote into the status share and requires
// it to be a plain file. Both the path and its contents are attacker-chosen: the
// share is writable by the guest, and the guest runs untrusted customer CI.
// O_NOFOLLOW stops a guest-planted symlink from making the host resolve and read
// some other file on its behalf. O_NONBLOCK stops a FIFO from parking the caller
// inside the open until something writes to the other end, which nothing ever
// does: one job could otherwise wedge a reconcile for as long as it liked. The
// regular-file check cannot stand in for O_NONBLOCK there, because it never runs
// if the open never returns.
//
// Returns the handle and its stat together, so a reader that wants metadata
// rather than bytes fstats what it already opened instead of racing a second
// path lookup against the guest.
func openGuestFile(statusDir, name string) (*os.File, os.FileInfo, bool) {
	if statusDir == "" {
		return nil, nil, false
	}
	f, err := os.OpenFile(
		filepath.Join(statusDir, name),
		os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK,
		0,
	)
	if err != nil {
		return nil, nil, false
	}
	fi, err := f.Stat()
	if err != nil || !fi.Mode().IsRegular() {
		f.Close()
		return nil, nil, false
	}
	return f, fi, true
}

// guestMarkerMaxBytes bounds the scalar markers: an exit code, a heartbeat
// state. Set orders of magnitude above anything
// the guest legitimately writes, so it binds only on a file the host has no
// reason to be holding in memory in the first place.
const guestMarkerMaxBytes = 4 << 10

// readGuestFile returns the bytes of a guest-written status file, or false when
// the guest left something other than a plain file. Oversize reads as absent
// rather than truncated: every caller parses a whole value, and half of one is
// not a value.
func readGuestFile(statusDir, name string, maxBytes int64) ([]byte, bool) {
	f, _, ok := openGuestFile(statusDir, name)
	if !ok {
		return nil, false
	}
	defer f.Close()

	b, err := io.ReadAll(io.LimitReader(f, maxBytes+1))
	if err != nil || int64(len(b)) > maxBytes {
		return nil, false
	}
	return b, true
}

// readRunnerExit reads the guest-reported exit code from the status share.
// The bool is false when the guest reported nothing usable.
//
// A wait status is a byte, and the shell reports 128+signal for a
// signalled child, so anything outside 0-255 did not come from `$?` and
// is a torn or truncated read of a file the guest was still writing.
// Rejecting it matters more than it looks: the value decides clean
// versus abnormal downstream, so a garbage read that happened to land on
// 0 would report a dead runner as a successful job, which is the bug
// this file exists to close. Out of range therefore reads as unreported,
// the same as no file at all.
func readRunnerExit(statusDir string) (int32, bool) {
	b, ok := readGuestFile(statusDir, runnerExitFile, guestMarkerMaxBytes)
	if !ok {
		return 0, false
	}
	// ParseInt over Atoi so an oversized value fails here rather than
	// silently wrapping on the conversion to int32.
	code, err := strconv.ParseInt(strings.TrimSpace(string(b)), 10, 32)
	if err != nil || code < 0 || code > 255 {
		return 0, false
	}
	return int32(code), true
}

// readRunnerLog returns a bounded tail of the guest's mirrored log, or
// "" when there is nothing usable. Callers re-emit it to tart-kubelet's
// own stdout before teardown deletes the share.
//
// Tail rather than head: the interesting part of a runner that gave up
// is what it said last. Bounded twice because the file is guest-written
// — by bytes first so a single pathological line cannot blow up the log
// record, then by lines.
//
// Read through openGuestFile, which is what keeps a guest-planted
// symlink or FIFO at this path from being followed. The stake is highest
// here of all the status-share readers: this one's output goes to Loki,
// so a followed symlink publishes up to runnerLogTailBytes of a
// host-readable file the guest chose.
func readRunnerLog(statusDir string) string {
	f, fi, ok := openGuestFile(statusDir, runnerLogFile)
	if !ok {
		return ""
	}
	defer f.Close()

	offset := int64(0)
	if fi.Size() > runnerLogTailBytes {
		offset = fi.Size() - runnerLogTailBytes
	}
	b := make([]byte, fi.Size()-offset)
	if _, err := f.ReadAt(b, offset); err != nil {
		return ""
	}

	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	// A byte-bounded read almost certainly starts mid-line; drop that
	// fragment so the tail begins on a real record.
	if offset > 0 && len(lines) > 1 {
		lines = lines[1:]
	}
	if len(lines) > runnerLogTailLines {
		lines = lines[len(lines)-runnerLogTailLines:]
	}
	return strings.Join(lines, "\n")
}

// readRunnerExitTime returns when the guest wrote its exit report, which
// is the moment it halted. Used to date a stop on the recovered path,
// where no `tart run` handle survived to have observed the exit itself.
func readRunnerExitTime(statusDir string) (time.Time, bool) {
	f, fi, ok := openGuestFile(statusDir, runnerExitFile)
	if !ok {
		return time.Time{}, false
	}
	defer f.Close()
	return fi.ModTime(), true
}

// runnerHeartbeatFile is the guest's liveness beat: dispatch-poll.sh
// rewrites it once per poll while it is warm, and once more when it takes
// a job. The contents are the state it is in; the mtime is the beat.
//
// It exists because a macOS Pod's Ready condition says only that the VM
// process is up and has an IP. tart-kubelet runs no container probes, so
// a guest whose poller died still reads 1/1 Running indefinitely and the
// runners-controller goes on counting it as warm capacity that can never
// take a job. Linux needs none of this: its poller is an init container,
// so the container runtime already reports whether it is running.
//
// Absent for Pods without a status share, and on runner images from before
// the guest wrote it. Both must read as "no signal" rather than "dead" —
// see publishRunnerHeartbeat.
const runnerHeartbeatFile = "runner-heartbeat"

// Heartbeat states dispatch-poll.sh writes. Anything else is a guest
// writing something we do not model, which reads as no signal at all
// rather than as a state to act on.
const (
	heartbeatStatePolling = "polling"
	heartbeatStateClaimed = "claimed"
)

// readRunnerHeartbeat returns the guest's last beat: the state it reported
// and the mtime of the report.
//
// The mtime is the host's, not the guest's — the write lands on the host
// filesystem through virtio-fs, so the host kernel stamps it, which is
// what makes it comparable to the host clock here. readRunnerExitTime
// dates a runner's halt off the same property.
//
// An unrecognized state reads as no beat. The file is guest-written and
// the states drive whether the controller counts this Pod as capacity, so
// the set is closed rather than passed through.
func readRunnerHeartbeat(statusDir string) (string, time.Time, bool) {
	f, fi, ok := openGuestFile(statusDir, runnerHeartbeatFile)
	if !ok {
		return "", time.Time{}, false
	}
	defer f.Close()

	b, err := io.ReadAll(io.LimitReader(f, guestMarkerMaxBytes+1))
	if err != nil || int64(len(b)) > guestMarkerMaxBytes {
		return "", time.Time{}, false
	}
	switch state := strings.TrimSpace(string(b)); state {
	case heartbeatStatePolling, heartbeatStateClaimed:
		return state, fi.ModTime(), true
	default:
		return "", time.Time{}, false
	}
}
