// sandbox-resume-benchmark measures same-host, local-SSD restoration on a
// separately reserved Mac. It never joins the production sandbox control plane.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

type options struct {
	home, binary, source, mode       string
	prepare, build, between, acquire string
	beforeSuspend                    string
	betweenLabel                     string
	readAhead                        bool
	gateProbe                        bool
	residentIdle                     time.Duration
	residentEvict                    bool
	memory, cpus, cycles             int
	timeout                          time.Duration
}

// Each sample is a real observation, not a latency assertion. CapacityWaitMS is
// the admission hook alone; FirstCommandMS starts only after it has succeeded.
type sample struct {
	Phase                  string          `json:"phase"`
	VM                     string          `json:"vm"`
	MemoryMB               int             `json:"memory_mb"`
	Cycle                  int             `json:"cycle,omitempty"`
	CacheCondition         string          `json:"cache_condition,omitempty"`
	CapacityWaitMS         int64           `json:"capacity_wait_ms"`
	LaunchMS               int64           `json:"launch_ms"`
	FirstCommandMS         int64           `json:"first_command_ms"`
	WarmCommandMS          int64           `json:"warm_command_ms"`
	StateConsumedMS        *int64          `json:"state_consumed_ms,omitempty"`
	BuildMS                int64           `json:"build_ms"`
	SuspendMS              int64           `json:"suspend_ms"`
	BetweenMS              int64           `json:"between_ms"`
	SnapshotBytes          int64           `json:"snapshot_bytes"`
	SnapshotAllocatedBytes int64           `json:"snapshot_allocated_bytes"`
	MemoryPreserved        bool            `json:"memory_preserved"`
	PreSuspendMS           int64           `json:"pre_suspend_ms"`
	ReadAheadMS            *int64          `json:"read_ahead_ms,omitempty"`
	RuntimeProfile         *runtimeProfile `json:"runtime_profile,omitempty"`
	ReadinessAttempts      []probeAttempt  `json:"readiness_attempts,omitempty"`
	ReadinessStrategy      string          `json:"readiness_strategy,omitempty"`
}

func main() {
	var o options
	flag.StringVar(&o.home, "home", "", "isolated TART_HOME containing the local source image (required)")
	flag.StringVar(&o.source, "source", "", "stopped local base VM in the isolated store (required; never modified)")
	flag.StringVar(&o.binary, "tart", "/usr/local/bin/tart", "Tart binary")
	flag.StringVar(&o.mode, "mode", "resume", "resume, resident (opt-in patched runtime), or workload")
	flag.DurationVar(&o.residentIdle, "resident-idle", time.Second, "time to retain each resident pause; all capacity remains charged")
	flag.BoolVar(&o.residentEvict, "resident-evict", false, "after resident cycles, save the paused VM, stop it, and measure a full restore")
	flag.IntVar(&o.memory, "memory-mb", 8192, "guest memory in MiB; test 8192, 16384 and 24576 separately")
	flag.IntVar(&o.cpus, "cpus", 8, "guest vCPUs")
	flag.IntVar(&o.cycles, "cycles", 10, "suspend/resume cycles")
	flag.DurationVar(&o.timeout, "timeout", 30*time.Minute, "whole experiment timeout, excluding cleanup")
	flag.StringVar(&o.prepare, "prepare-script", "", "host file containing guest setup, run once before measurement")
	flag.StringVar(&o.build, "build-script", "", "host file containing a guest build/test command, required")
	flag.StringVar(&o.between, "between-script", "", "host script run after suspension; run and await CI here")
	flag.StringVar(&o.betweenLabel, "between-label", "after_workload", "cache-condition label for the between-suspension hook")
	flag.StringVar(&o.acquire, "acquire-script", "", "host script that waits for an exclusive CI-safe reservation before every launch")
	flag.StringVar(&o.beforeSuspend, "before-suspend-script", "", "optional guest diagnostic/preparation script before each suspension; its cost is reported separately")
	flag.BoolVar(&o.readAhead, "snapshot-read-ahead", false, "read saved state before restore; read cost remains inside first_command_ms")
	flag.BoolVar(&o.gateProbe, "gate-command-probe", false, "wait for the host control socket before starting a guest command probe; a successful command is still required")
	flag.Parse()
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err := run(ctx, o, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func (o options) validate() error {
	if !filepath.IsAbs(o.home) || o.home == "/" || o.source == "" || strings.ContainsAny(o.source, "/\\") || o.source == "." || o.source == ".." {
		return errors.New("provide an absolute isolated --home and a local --source VM name")
	}
	userHome, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	resolved, err := filepath.EvalSymlinks(o.home)
	if err != nil {
		return fmt.Errorf("isolated home: %w", err)
	}
	regular, _ := filepath.EvalSymlinks(filepath.Join(userHome, ".tart"))
	if resolved == regular {
		return errors.New("refusing the user's default Tart store; use an isolated store")
	}
	if o.mode != "resume" && o.mode != "workload" && o.mode != "resident" {
		return errors.New("mode must be resume, resident or workload")
	}
	if o.mode == "resident" && (o.residentIdle < 0 || o.between != "" || o.readAhead || os.Getenv("TUIST_RESIDENT_BENCHMARK") != "1") {
		return errors.New("resident mode requires TUIST_RESIDENT_BENCHMARK=1 and nonnegative idle time; between-workload and read-ahead hooks are inapplicable")
	}
	if o.memory < 4096 || o.cpus < 2 || o.cycles < 1 || o.timeout <= 0 {
		return errors.New("invalid memory, CPU, cycle count or timeout")
	}
	if o.build == "" || o.acquire == "" {
		return errors.New("--build-script and --acquire-script are required")
	}
	return nil
}

func run(parent context.Context, o options, out, progress io.Writer) (resultErr error) {
	if err := o.validate(); err != nil {
		return err
	}
	if runtime.GOOS != "darwin" || runtime.GOARCH != "arm64" {
		return errors.New("requires an Apple silicon Mac")
	}
	ctx, cancel := context.WithTimeout(parent, o.timeout)
	defer cancel()
	prepare, err := readScript(o.prepare)
	if err != nil {
		return err
	}
	build, err := readScript(o.build)
	if err != nil {
		return err
	}
	// Read all hooks before allocating anything. They are operator-supplied
	// host scripts, not guest commands or session input.
	between, err := readScript(o.between)
	if err != nil {
		return err
	}
	acquire, err := readScript(o.acquire)
	if err != nil {
		return err
	}
	beforeSuspend, err := readScript(o.beforeSuspend)
	if err != nil {
		return err
	}
	c := tart.New()
	c.Binary, c.HomeDir, c.LogDir = o.binary, o.home, filepath.Join(o.home, "benchmark-logs")
	source, err := c.Get(ctx, o.source)
	if err != nil {
		return err
	}
	if source == nil || source.State != "stopped" {
		return errors.New("source must be a stopped local base VM")
	}
	version, err := c.Version(ctx)
	if err != nil {
		return err
	}
	enc := json.NewEncoder(out)
	if err := enc.Encode(map[string]any{"phase": "configuration", "tart_version": version, "memory_mb": o.memory, "cpus": o.cpus, "cycles": o.cycles, "mode": o.mode}); err != nil {
		return err
	}
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return err
	}
	name := "sbx-bench-" + hex.EncodeToString(random[:])
	// Never reuse or overwrite a caller's VM. A fresh name also isolates the
	// per-invocation log and any old snapshot from previous experiments.
	if existing, err := c.Get(ctx, name); err != nil {
		return err
	} else if existing != nil {
		return errors.New("benchmark VM already exists")
	}
	if err := c.Clone(ctx, o.source, name); err != nil {
		return err
	}
	defer func() {
		cleanupCtx, stop := context.WithTimeout(context.Background(), 2*time.Minute)
		defer stop()
		if err := cleanup(cleanupCtx, c, name); err != nil {
			resultErr = errors.Join(resultErr, fmt.Errorf("cleanup %s (retained for inspection): %w", name, err))
		}
	}()
	if err := c.Set(ctx, name, o.cpus, o.memory); err != nil {
		return err
	}
	if err := c.RegenerateIdentity(ctx, name); err != nil {
		return err
	}
	wait, err := hostScript(ctx, acquire, c, name, progress)
	if err != nil {
		return fmt.Errorf("acquire host: %w", err)
	}
	started := time.Now()
	if err := noRunningVMs(ctx, c); err != nil {
		return err
	}
	fmt.Fprintf(progress, "cold boot %s (%d MiB)\n", name, o.memory)
	h, err := c.StartWithOptions(ctx, name, tart.RunOptions{Suspendable: o.mode != "workload"})
	if err != nil {
		return err
	}
	launchMS := time.Since(started).Milliseconds()
	if err := ready(ctx, c, h); err != nil {
		return err
	}
	s := sample{Phase: "cold_boot", VM: name, MemoryMB: o.memory, CapacityWaitMS: wait.Milliseconds(), LaunchMS: launchMS, FirstCommandMS: time.Since(started).Milliseconds()}
	if _, err := guestScript(ctx, c, name, prepare, progress); err != nil {
		return fmt.Errorf("prepare guest: %w", err)
	}
	buildTime, err := guestScript(ctx, c, name, build, progress)
	if err != nil {
		return fmt.Errorf("initial build: %w", err)
	}
	s.BuildMS = buildTime.Milliseconds()
	if err := enc.Encode(s); err != nil {
		return err
	}
	if o.mode == "workload" {
		return nil
	}
	identity, err := startSentinel(ctx, c, name)
	if err != nil {
		return err
	}
	if o.mode == "resident" {
		return runResidentCycles(ctx, o, c, h, identity, build, acquire, enc, progress)
	}
	for cycle := 1; cycle <= o.cycles; cycle++ {
		s := sample{Phase: "resume", VM: name, MemoryMB: o.memory, Cycle: cycle, CacheCondition: "immediate"}
		preparation, err := guestScript(ctx, c, name, beforeSuspend, progress)
		if err != nil {
			return fmt.Errorf("before suspend: %w", err)
		}
		s.PreSuspendMS = preparation.Milliseconds()
		started := time.Now()
		if err := ready(ctx, c, h); err != nil {
			return fmt.Errorf("warm command: %w", err)
		}
		s.WarmCommandMS = time.Since(started).Milliseconds()
		started = time.Now()
		if err := c.Suspend(ctx, h); err != nil {
			return fmt.Errorf("cycle %d suspend: %w", cycle, err)
		}
		s.SuspendMS = time.Since(started).Milliseconds()
		info, err := os.Stat(filepath.Join(o.home, "vms", name, "state.vzvmsave"))
		if err != nil {
			return fmt.Errorf("measure saved state: %w", err)
		}
		s.SnapshotBytes = info.Size()
		if stat, ok := info.Sys().(*syscall.Stat_t); ok {
			s.SnapshotAllocatedBytes = stat.Blocks * 512
		}
		fmt.Fprintf(progress, "cycle %d: suspended; guest slot is free\n", cycle)
		if between != "" {
			s.CacheCondition = o.betweenLabel
			d, err := hostScript(ctx, between, c, name, progress)
			if err != nil {
				return fmt.Errorf("between workload: %w", err)
			}
			s.BetweenMS = d.Milliseconds()
		}
		wait, err := hostScript(ctx, acquire, c, name, progress)
		if err != nil {
			return fmt.Errorf("reacquire host: %w", err)
		}
		s.CapacityWaitMS = wait.Milliseconds()
		started = time.Now()
		if err := noRunningVMs(ctx, c); err != nil {
			return err
		}
		if o.readAhead {
			readStarted := time.Now()
			if err := readSnapshot(ctx, filepath.Join(o.home, "vms", name, "state.vzvmsave")); err != nil {
				return fmt.Errorf("read ahead: %w", err)
			}
			ms := time.Since(readStarted).Milliseconds()
			s.ReadAheadMS = &ms
			s.CacheCondition += "+read_ahead"
		}
		logOffset, err := logSize(h.LogPath)
		if err != nil {
			return err
		}
		previousSocket, err := os.Stat(filepath.Join(o.home, "vms", name, "control.sock"))
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		observeCtx, stopObserving := context.WithCancel(ctx)
		consumed := observeConsumption(observeCtx, filepath.Join(o.home, "vms", name, "state.vzvmsave"))
		h, err = c.Resume(ctx, name, tart.RunOptions{})
		if err != nil {
			stopObserving()
			<-consumed
			return fmt.Errorf("cycle %d resume: %w", cycle, err)
		}
		s.LaunchMS = time.Since(started).Milliseconds()
		s.ReadinessStrategy = "command"
		if o.gateProbe {
			s.ReadinessStrategy = "socket_generation_then_command"
		}
		if err := h.WaitReady(ctx, func(probe context.Context) error {
			attempt := probeAttempt{StartMS: time.Since(started).Milliseconds()}
			probeStarted := time.Now()
			err := probeGuest(probe, c, h.Name, o.gateProbe, previousSocket)
			attempt.DurationMS, attempt.Success = time.Since(probeStarted).Milliseconds(), err == nil
			s.ReadinessAttempts = append(s.ReadinessAttempts, attempt)
			return err
		}); err != nil {
			stopObserving()
			<-consumed
			return fmt.Errorf("cycle %d readiness: %w", cycle, err)
		}
		s.FirstCommandMS = time.Since(started).Milliseconds()
		s.RuntimeProfile, err = readRuntimeProfile(h.LogPath, logOffset)
		if err != nil {
			stopObserving()
			<-consumed
			return fmt.Errorf("runtime profile: %w", err)
		}
		stopObserving()
		if at := <-consumed; !at.IsZero() {
			ms := at.Sub(started).Milliseconds()
			s.StateConsumedMS = &ms
		}
		if err := checkSentinel(ctx, c, name, identity); err != nil {
			return err
		}
		s.MemoryPreserved = true
		buildTime, err := guestScript(ctx, c, name, build, progress)
		if err != nil {
			return fmt.Errorf("incremental build: %w", err)
		}
		s.BuildMS = buildTime.Milliseconds()
		if err := enc.Encode(s); err != nil {
			return err
		}
	}
	return nil
}

// Tart 2.41.1 unlinks saved state after restoreMachineStateFrom returns and
// before resuming. Polling that boundary avoids interpreting buffered log
// timestamps as framework timings. It includes Tart startup/configuration and
// polling delay; it is not a measurement of the Apple API call alone.
func observeConsumption(ctx context.Context, path string) <-chan time.Time {
	done := make(chan time.Time, 1)
	go func() {
		ticker := time.NewTicker(10 * time.Millisecond)
		defer ticker.Stop()
		for {
			if _, err := os.Stat(path); os.IsNotExist(err) {
				done <- time.Now()
				return
			} else if err != nil {
				done <- time.Time{}
				return
			}
			select {
			case <-ctx.Done():
				done <- time.Time{}
				return
			case <-ticker.C:
			}
		}
	}()
	return done
}

func readScript(path string) (string, error) {
	if path == "" {
		return "", nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(string(b)) == "" {
		return "", fmt.Errorf("empty script: %s", path)
	}
	return string(b), nil
}

func guestScript(ctx context.Context, c *tart.Client, name, script string, log io.Writer) (time.Duration, error) {
	if script == "" {
		return 0, nil
	}
	start := time.Now()
	out, err := c.Exec(ctx, name, "/bin/sh", "-eu", "-c", script)
	_, _ = log.Write(out)
	return time.Since(start), err
}

func hostScript(ctx context.Context, script string, c *tart.Client, name string, log io.Writer) (time.Duration, error) {
	start := time.Now()
	cmd := exec.CommandContext(ctx, "/bin/sh", "-eu", "-c", script)
	cmd.Env = append(os.Environ(), "TART_HOME="+c.HomeDir, "SANDBOX_VM="+name, "TART_BINARY="+c.Binary)
	cmd.Stdout, cmd.Stderr = log, log
	cmd.WaitDelay = 2 * time.Second
	err := cmd.Run()
	return time.Since(start), err
}

func ready(ctx context.Context, c *tart.Client, h *tart.RunHandle) error {
	return h.WaitReady(ctx, func(probe context.Context) error {
		_, err := c.Exec(probe, h.Name, "/usr/bin/true")
		return err
	})
}

// Tart replaces the old control socket after the VM resumes. Observing the
// replacement avoids reconnect backoff without opening extra guest connections.
// This transport gate never substitutes for a successful command in the guest.
func probeGuest(ctx context.Context, c *tart.Client, name string, gate bool, previous os.FileInfo) error {
	if gate {
		current, err := os.Stat(filepath.Join(c.HomeDir, "vms", name, "control.sock"))
		if err != nil {
			return err
		}
		if current.Mode()&os.ModeSocket == 0 || (previous != nil && os.SameFile(previous, current) && previous.ModTime().Equal(current.ModTime())) {
			return errors.New("waiting for a new control socket")
		}
	}
	_, err := c.Exec(ctx, name, "/usr/bin/true")
	return err
}

// A live shell retains a randomly generated variable in RAM and answers a
// challenge through a FIFO. Neither the variable nor the PID's existence on
// disk can cause a cold-booted guest to pass the check. No launchd job restarts it.
func startSentinel(ctx context.Context, c *tart.Client, name string) (string, error) {
	script := `d=/tmp/tuist-resume-sentinel
mkdir "$d"
mkfifo "$d/request"
nohup /bin/sh -c 'token=$(uuidgen); while :; do read -r challenge < /tmp/tuist-resume-sentinel/request; printf "%s:%s\n" "$token" "$challenge" > /tmp/tuist-resume-sentinel/reply; done' </dev/null >/dev/null 2>&1 &
echo $! > "$d/pid"
`
	if _, err := c.Exec(ctx, name, "/bin/sh", "-eu", "-c", script); err != nil {
		return "", err
	}
	return sentinelToken(ctx, c, name)
}

func sentinelToken(ctx context.Context, c *tart.Client, name string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := c.Exec(ctx, name, "/bin/sh", "-eu", "-c", `d=/tmp/tuist-resume-sentinel
challenge=$(uuidgen)
rm -f "$d/reply"
kill -0 "$(cat "$d/pid")"
printf '%s\n' "$challenge" > "$d/request"
while [ ! -s "$d/reply" ]; do sleep 0.01; done
reply=$(cat "$d/reply")
test "${reply#*:}" = "$challenge"
printf '%s\n' "${reply%%:*}"
`)
	if err != nil {
		return "", fmt.Errorf("RAM sentinel failed: %w", err)
	}
	token := strings.TrimSpace(string(out))
	if token == "" {
		return "", errors.New("RAM sentinel returned an empty token")
	}
	return token, nil
}

func checkSentinel(ctx context.Context, c *tart.Client, name, expected string) error {
	token, err := sentinelToken(ctx, c, name)
	if err != nil {
		return err
	}
	if token != expected {
		return errors.New("guest process identity changed; this was not memory-preserving resume")
	}
	return nil
}

func noRunningVMs(ctx context.Context, c *tart.Client) error {
	vms, err := c.List(ctx)
	if err != nil {
		return err
	}
	for _, vm := range vms {
		if vm.State == "running" {
			return fmt.Errorf("VM %s still occupies the benchmark store", vm.Name)
		}
	}
	// Other TART_HOME stores share the same two guest slots. Admission is the
	// acquire hook's job; this is a last check, not a reservation mechanism.
	cmd := exec.CommandContext(ctx, "pgrep", "-f", `tart run `)
	if err := cmd.Run(); err == nil {
		return errors.New("another Tart VM is running on this host")
	} else {
		var exit *exec.ExitError
		if !errors.As(err, &exit) || exit.ExitCode() != 1 {
			return fmt.Errorf("check host VM processes: %w", err)
		}
	}
	return nil
}

func cleanup(ctx context.Context, c *tart.Client, name string) error {
	vm, err := c.Get(ctx, name)
	if err != nil || vm == nil {
		return err
	}
	if vm.State == "running" {
		if err := c.Stop(ctx, name, 0); err != nil {
			return err
		}
	}
	for {
		running, err := c.IsRunning(ctx, name)
		if err != nil {
			return err
		}
		vm, err = c.Get(ctx, name)
		if err != nil {
			return err
		}
		if !running && (vm == nil || vm.State != "running") {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
	return c.Delete(ctx, name)
}
