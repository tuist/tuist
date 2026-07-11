// Package tart drives the local `tart` CLI on the Mac mini this
// tart-kubelet instance is running on.
//
// The kubelet runs as root via launchd and shells out directly. No SSH:
// the agent owns the host. Pods scheduled to this Node become VMs
// managed here.
package tart

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Client wraps the local `tart` binary.
type Client struct {
	// Binary is the path to the `tart` CLI on this Mac mini.
	// Defaults to /usr/local/bin/tart, the wrapper script the
	// CAPI provider's bootstrap step writes around the pinned
	// tart.app bundle at /usr/local/lib/tart.app.
	Binary string

	// UserDataDir is the host directory where per-VM env files live.
	// Defaults to /var/lib/tart-userdata. The kubelet stages
	// /var/lib/tart-userdata/<vm>/tuist.env before `tart run` and
	// shares the directory into the guest as `env`.
	UserDataDir string

	// LogDir is where per-VM `tart run` stdout/stderr is redirected.
	// Defaults to /var/log/tart-vms.
	LogDir string

	// EnsureGUISession runs before each `tart run` to verify the
	// calling user holds a live Aqua launchd session — required
	// for VZ HostKey creation on macOS guests. `New()` wires this
	// to EnsureRealGUISession; tests construct Client directly and
	// leave it nil to skip the check.
	EnsureGUISession func(ctx context.Context) error
}

// New returns a Client with sensible defaults.
func New() *Client {
	return &Client{
		Binary:           "/usr/local/bin/tart",
		UserDataDir:      "/var/lib/tart-userdata",
		LogDir:           "/var/log/tart-vms",
		EnsureGUISession: EnsureRealGUISession,
	}
}

// VM is the subset of `tart get` / `tart list` JSON we care about.
//
// `tart list` returns Name in the JSON; `tart get` doesn't (it's
// implicit in the path argument). Get() therefore stamps Name from
// the caller after Unmarshal.
type VM struct {
	Name   string `json:"Name,omitempty"`
	Source string `json:"Source"`
	State  string `json:"State"`
	CPU    int    `json:"CPU"`
	Memory int    `json:"Memory"`
	Size   vmSize `json:"Size"`
}

// vmSize tolerates Tart's inconsistent Size encoding across subcommands:
// `tart list --format json` emits an integer (72), while `tart get
// --format json` emits a quoted decimal string ("72.660"). A plain int64
// field unmarshals the former but errors on the latter — and because Get()
// surfaces that error, ensureGolden's warm-path probe (`tart get <golden>`)
// failed on EVERY call, fell through to the cold path, and re-pulled the
// golden each recycle instead of cloning from it. The GC/label path was
// unaffected because it reads `tart list`. Size isn't load-bearing; this
// type just keeps VM unmarshal from failing on either form.
type vmSize int64

func (s *vmSize) UnmarshalJSON(b []byte) error {
	str := strings.Trim(string(b), `"`)
	if str == "" || str == "null" {
		return nil
	}
	f, err := strconv.ParseFloat(str, 64)
	if err != nil {
		return nil
	}
	*s = vmSize(f)
	return nil
}

// Per-operation timeouts bound how long a single `tart` invocation may
// run before exec.CommandContext kills it. A hung `tart` call (observed
// in prod stalling a node's VM provisioning for minutes — pod stuck
// Pending, zero events) would otherwise block the single-concurrency
// reconcile worker indefinitely; with a deadline the caller gets an
// error and retries on its normal cadence, so a wedged op self-heals
// instead of stranding the Pod. Package-level vars (not consts) so
// tests can shrink them.
var (
	pullTimeout   = 20 * time.Minute
	cloneTimeout  = 5 * time.Minute
	setTimeout    = 1 * time.Minute
	deleteTimeout = 5 * time.Minute
	queryTimeout  = 30 * time.Second
	// runWaitDelay bounds how long Wait blocks for the I/O pipes to
	// close after the timeout context kills the process (see run).
	runWaitDelay = 2 * time.Second
)

// Pull invokes `tart pull <image>`. Idempotent — Tart skips re-download
// when the image is already cached.
func (c *Client) Pull(ctx context.Context, image string) error {
	ctx, cancel := context.WithTimeout(ctx, pullTimeout)
	defer cancel()
	_, err := c.run(ctx, c.Binary, "pull", image)
	return err
}

// Clone invokes `tart clone <source> <name>`.
func (c *Client) Clone(ctx context.Context, source, name string) error {
	ctx, cancel := context.WithTimeout(ctx, cloneTimeout)
	defer cancel()
	_, err := c.run(ctx, c.Binary, "clone", source, name)
	return err
}

// Set configures cpu/memory for a cloned VM. Pass 0 to leave a
// parameter at the image default.
func (c *Client) Set(ctx context.Context, name string, cpu, memoryMB int) error {
	args := []string{"set", name}
	if cpu > 0 {
		args = append(args, "--cpu", fmt.Sprintf("%d", cpu))
	}
	if memoryMB > 0 {
		args = append(args, "--memory", fmt.Sprintf("%d", memoryMB))
	}
	if len(args) == 2 {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, setTimeout)
	defer cancel()
	_, err := c.run(ctx, c.Binary, args...)
	return err
}

// RunHandle exposes the lifecycle of a backgrounded `tart run`
// process. The reconciler stashes one in its Store entry alongside
// the VM name so subsequent reconciles can detect a process that
// exited *after* the launch sanity check window without depending
// on the IP poll alone.
type RunHandle struct {
	// Name is the Tart VM name the process was started for.
	Name string

	// LogPath is where the process's stdout/stderr was redirected.
	// Surfaced in error messages so operators can `tail` it.
	LogPath string

	done         chan struct{}
	exitErr      error
	vncReady     chan struct{}
	vncReadyOnce sync.Once
	vncMu        sync.RWMutex
	vncInfo      *VNCInfo
}

// Done returns a channel that is closed once the process exits.
// Useful for callers that want to block; Exited() is the
// non-blocking variant.
func (h *RunHandle) Done() <-chan struct{} { return h.done }

// Exited reports whether the `tart run` process has terminated. The
// returned error is whatever cmd.Wait observed — a nil err with
// ok=true means a clean exit (rare for a long-lived VM process,
// usually a sign of an internal Tart shutdown). Safe for concurrent
// use: writes to exitErr happen-before close(done) in the launcher
// goroutine, and reads happen after the receive on done returns.
func (h *RunHandle) Exited() (err error, ok bool) {
	select {
	case <-h.done:
		return h.exitErr, true
	default:
		return nil, false
	}
}

// VNCInfo is Tart's generated host-local VNC endpoint. The password is
// sensitive host/control-plane data; do not publish it to Pod annotations,
// guest env, or normal logs.
type VNCInfo struct {
	Host     string
	Port     int
	Password string
}

// URL returns a VNC URL containing Tart's generated password.
func (i VNCInfo) URL() string {
	return vncURL(i.Host, i.Port, i.Password)
}

// RedactedURL returns a VNC URL safe for logs.
func (i VNCInfo) RedactedURL() string {
	return vncURL(i.Host, i.Port, "REDACTED")
}

// VNCInfo returns the parsed VNC endpoint when Tart has printed it.
func (h *RunHandle) VNCInfo() (VNCInfo, bool) {
	h.vncMu.RLock()
	defer h.vncMu.RUnlock()
	if h.vncInfo == nil {
		return VNCInfo{}, false
	}
	return *h.vncInfo, true
}

// WaitVNCInfo blocks until Tart prints the generated VNC endpoint, the run
// process exits, or ctx is cancelled.
func (h *RunHandle) WaitVNCInfo(ctx context.Context) (VNCInfo, error) {
	select {
	case <-h.vncReady:
		if info, ok := h.VNCInfo(); ok {
			return info, nil
		}
		return VNCInfo{}, fmt.Errorf("tart run exited before VNC endpoint was observed")
	case <-ctx.Done():
		return VNCInfo{}, ctx.Err()
	}
}

func (h *RunHandle) setVNCInfo(info VNCInfo) {
	h.vncMu.Lock()
	if h.vncInfo == nil {
		h.vncInfo = &info
	}
	h.vncMu.Unlock()
	h.vncReadyOnce.Do(func() { close(h.vncReady) })
}

func (h *RunHandle) closeVNCInfo() {
	h.vncReadyOnce.Do(func() { close(h.vncReady) })
}

// RunOptions controls how Tart boots a VM.
type RunOptions struct {
	// SharedDirs are Tart --dir mounts, for example env:/path:ro.
	SharedDirs []string

	// Disks are additional block devices attached via `tart run --disk
	// <path>`, on top of the VM's root disk. The per-account cache volume
	// (spec #76) attaches its per-VM branch image here. The list is plural
	// from day one so generic user-declared volumes (spec #69) compose
	// without a wrapper change; v1 passes at most one.
	Disks []string

	// VNC enables Tart's host-owned experimental VNC server while keeping
	// the VM headless. Tart prints a one-time password; Run captures it
	// into RunHandle and redacts it from the VM log.
	VNC bool
}

// Run launches a VM in the background and returns a handle as soon
// as the `tart run` process is alive. It does NOT wait for the
// guest to obtain an IP — that's the reconciler's job (via Tart.IP,
// polled from podStatus). Decoupling makes the VM lifecycle bound
// by the Pod lifecycle rather than by an arbitrary in-process
// timeout: a slow-but-still-booting guest stays alive across
// reconcile passes and the Pod transitions to Running the moment
// configd hands out a DHCP lease, however many minutes that takes.
// Helm's own `--wait --timeout` is the right place for a top-level
// deadline; an inner one that destroyed the VM on expiry just
// forced re-clones and re-boots that hit the same wall.
//
// The returned RunHandle reports later exits (after the 5s sanity
// window). Callers MUST poll handle.Exited() each reconcile so a
// process that drops, say, 30s in surfaces as a Pod failure rather
// than stranding helm on an IP poll that will never succeed.
//
// Tart 2.32 quirks accommodated here:
//   - `tart run` is foreground-only. We start it directly from Go with
//     `Setsid: true` so it gets its own session and process group.
//     Earlier we wrapped it in `sh -c 'tart … &'` — that left tart
//     in the same pgid as tart-kubelet, so `launchctl bootout`
//     during a kubelet upgrade signalled the whole group and killed
//     the running VM. Setsid puts the VM out of reach of those
//     signals; the tart-kubelet's startup state-recovery pass then
//     re-binds it on the next reconcile.
//   - We deliberately do NOT use `nohup` — it requires a controlling
//     TTY to detach from, and launchd-spawned processes don't have
//     one. With Setsid we don't need it.
func (c *Client) Run(ctx context.Context, name string, sharedDirs []string) (*RunHandle, error) {
	return c.RunWithOptions(ctx, name, RunOptions{SharedDirs: sharedDirs})
}

// RunWithOptions is Run with explicit boot options.
func (c *Client) RunWithOptions(ctx context.Context, name string, opts RunOptions) (*RunHandle, error) {
	if err := os.MkdirAll(c.LogDir, 0o755); err != nil {
		return nil, fmt.Errorf("mkdir log dir: %w", err)
	}

	// VZ HostKey creation needs a live Aqua session; without it
	// `tart run` exits in <1s with `VZErrorDomain Code=-9 / Failed
	// to create new HostKey` and the Pod stalls in
	// TartCreateFailed. Verify (and reanimate) the session here
	// rather than after the fact — the 5s sanity window below
	// would otherwise just observe the immediate exit on every
	// retry forever.
	if c.EnsureGUISession != nil {
		if err := c.EnsureGUISession(ctx); err != nil {
			return nil, fmt.Errorf("ensure gui session: %w", err)
		}
	}

	// Host-cache the VM's disk-image reads. Tart's default (caching=automatic)
	// leaves read throughput on the table for our read/page-in-heavy build
	// workload (compilers + dylibs paged in per task). An on-host A/B on a
	// runner Mac mini measured ~1.8x faster warm reads with caching=cached
	// (7.7 vs 4.2 GB/s) and no durability tradeoff — these VMs are ephemeral
	// (cloned per Pod, discarded on exit), so host caching is pure upside.
	args := []string{"run", name, "--no-graphics"}
	if opts.VNC {
		args = append(args, "--vnc-experimental")
	}
	args = append(args, "--root-disk-opts", "caching=cached")
	for _, dir := range opts.SharedDirs {
		args = append(args, "--dir", dir)
	}
	// Additional block devices (the per-account cache volume branch).
	// Attached plainly: unlike the root disk (whose caching is set via the
	// dedicated --root-disk-opts flag), tart 2.32's `--disk` takes a bare
	// path (with only `:ro`-style flags), so a `:caching=cached` suffix here
	// is parsed as part of the path and fails the attach. The branch is a
	// CoW clone, as ephemeral as the VM, so default caching is fine.
	for _, disk := range opts.Disks {
		args = append(args, "--disk", disk)
	}

	logPath := filepath.Join(c.LogDir, name+".log")
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, fmt.Errorf("open vm log: %w", err)
	}

	// Bare exec.Command (NOT CommandContext) so the parent ctx
	// cancelling — kubelet shutdown, reconcile timeout — doesn't
	// SIGKILL the VM. Setsid + cmd.Start (no Wait) leaves tart
	// running independently.
	cmd := exec.Command(c.Binary, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		_ = logFile.Close()
		return nil, fmt.Errorf("open tart stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		_ = logFile.Close()
		return nil, fmt.Errorf("open tart stderr pipe: %w", err)
	}

	handle := &RunHandle{
		Name:     name,
		LogPath:  logPath,
		done:     make(chan struct{}),
		vncReady: make(chan struct{}),
	}

	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		return nil, fmt.Errorf("start tart run: %w", err)
	}

	var outputWG sync.WaitGroup
	var logMu sync.Mutex
	outputWG.Add(2)
	go copyTartOutput(stdout, logFile, &logMu, handle, &outputWG)
	go copyTartOutput(stderr, logFile, &logMu, handle, &outputWG)

	// Single launcher goroutine owns cmd.Wait for the lifetime of
	// the process. Writing exitErr before close(done) gives readers
	// of Exited() a happens-before relationship on the field — no
	// extra mutex needed.
	go func() {
		handle.exitErr = cmd.Wait()
		outputWG.Wait()
		_ = logFile.Close()
		handle.closeVNCInfo()
		close(handle.done)
	}()

	// Watch the process briefly so an immediate failure (missing
	// image, malformed --dir, Tart admission error) surfaces here
	// instead of stranding the Pod in Pending while podStatus polls
	// an IP that will never come. 5s is long enough to catch the
	// fast-fail cases (<1s in practice) without delaying the happy
	// path meaningfully — the guest will be cold-booting for minutes
	// either way. Slower exits are caught by the reconciler via
	// handle.Exited() on subsequent passes.
	select {
	case <-handle.done:
		// Fold the tail of the tart log into the error so the actual tart
		// failure (unknown --disk option, admission refusal, bad image)
		// reaches `kubectl describe` / the Pod event instead of only
		// "exit status 1" with a host-local logpath we can't read remotely.
		return nil, fmt.Errorf("tart run %s exited immediately: %w (see %s)\n--- tart log tail ---\n%s", name, handle.exitErr, logPath, tailFile(logPath, 20))
	case <-ctx.Done():
		// Parent ctx cancelled. The Setsid-detached process keeps
		// running; recoverState rebinds it after a kubelet restart.
		return nil, ctx.Err()
	case <-time.After(5 * time.Second):
		return handle, nil
	}
}

// tailFile returns the last n non-empty lines of a file, best-effort.
// Used to surface the tail of a VM's tart log in an error when the VM
// exits immediately, since the log path itself is host-local and not
// reachable from wherever the Pod status is read.
func tailFile(path string, n int) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Sprintf("(could not read %s: %v)", path, err)
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

var vncURLPattern = regexp.MustCompile(`vnc://\S+`)

func copyTartOutput(r io.Reader, logFile *os.File, logMu *sync.Mutex, handle *RunHandle, wg *sync.WaitGroup) {
	defer wg.Done()

	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := scanner.Text()
		redacted := vncURLPattern.ReplaceAllStringFunc(line, func(raw string) string {
			suffix := ""
			trimmed := strings.TrimRight(raw, ".,)")
			suffix = strings.TrimPrefix(raw, trimmed)
			info, err := parseTartVNCURL(trimmed)
			if err != nil {
				return raw
			}
			handle.setVNCInfo(info)
			return info.RedactedURL() + suffix
		})
		logMu.Lock()
		_, _ = fmt.Fprintln(logFile, redacted)
		logMu.Unlock()
	}
}

func parseTartVNCURL(raw string) (VNCInfo, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return VNCInfo{}, err
	}
	if u.Scheme != "vnc" {
		return VNCInfo{}, fmt.Errorf("not a VNC URL: %s", raw)
	}
	host := u.Hostname()
	if host == "" {
		return VNCInfo{}, fmt.Errorf("VNC URL missing host: %s", raw)
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil || port <= 0 || port > 65535 {
		return VNCInfo{}, fmt.Errorf("VNC URL missing valid port: %s", raw)
	}
	password, ok := u.User.Password()
	if !ok || password == "" {
		return VNCInfo{}, fmt.Errorf("VNC URL missing generated password: %s", raw)
	}
	return VNCInfo{Host: host, Port: port, Password: password}, nil
}

func vncURL(host string, port int, password string) string {
	return (&url.URL{
		Scheme: "vnc",
		User:   url.UserPassword("", password),
		Host:   net.JoinHostPort(host, strconv.Itoa(port)),
	}).String()
}

// Stop gracefully halts a VM.
func (c *Client) Stop(ctx context.Context, name string, gracePeriod time.Duration) error {
	args := []string{"stop", name}
	if gracePeriod > 0 {
		args = append(args, "--timeout", fmt.Sprintf("%d", int(gracePeriod.Seconds())))
	}
	to := 2 * time.Minute
	if gracePeriod > 0 && gracePeriod+30*time.Second > to {
		to = gracePeriod + 30*time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, to)
	defer cancel()
	_, err := c.run(ctx, c.Binary, args...)
	return err
}

// Delete removes a VM's filesystem.
func (c *Client) Delete(ctx context.Context, name string) error {
	ctx, cancel := context.WithTimeout(ctx, deleteTimeout)
	defer cancel()
	_, err := c.run(ctx, c.Binary, "delete", name)
	return err
}

// Get returns one VM's metadata, or (nil, nil) if it doesn't exist.
func (c *Client) Get(ctx context.Context, name string) (*VM, error) {
	ctx, cancel := context.WithTimeout(ctx, queryTimeout)
	defer cancel()
	out, err := c.run(ctx, c.Binary, "get", name, "--format", "json")
	if err != nil {
		if isNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	var vm VM
	if err := json.Unmarshal(out, &vm); err != nil {
		return nil, fmt.Errorf("parse tart get %s: %w", name, err)
	}
	vm.Name = name
	return &vm, nil
}

// List returns every VM Tart knows about on this host.
func (c *Client) List(ctx context.Context) ([]VM, error) {
	ctx, cancel := context.WithTimeout(ctx, queryTimeout)
	defer cancel()
	out, err := c.run(ctx, c.Binary, "list", "--format", "json")
	if err != nil {
		return nil, err
	}
	var vms []VM
	if err := json.Unmarshal(out, &vms); err != nil {
		return nil, fmt.Errorf("parse tart list: %w", err)
	}
	return vms, nil
}

// IP blocks up to 30s for the VM to obtain a primary IPv4 address.
func (c *Client) IP(ctx context.Context, name string) (string, error) {
	out, err := c.run(ctx, c.Binary, "ip", name, "--wait", "30")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// GuestDiskUsagePercent runs `df` inside the guest VM and returns the
// percent-used (0-100) of its root filesystem. Requires the Tart guest
// agent, which the Cirrus Labs base images ship — the same agent
// `tart exec` relies on. The root volume is the one a workload's scratch
// data fills (e.g. the xcresult processor's attachment exports), so its
// capacity is the DiskPressure signal that matters; the host's own disk
// stays near-empty even when a guest is full.
func (c *Client) GuestDiskUsagePercent(ctx context.Context, name string) (int, error) {
	out, err := c.run(ctx, c.Binary, "exec", name, "/bin/df", "-k", "/")
	if err != nil {
		return 0, err
	}
	return parseDFCapacityPercent(out)
}

// parseDFCapacityPercent reads the block Capacity column from a
// single-filesystem `df` report. macOS df columns are:
//
//	Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted-on
//
// The first field ending in '%' on the data line is the block Capacity
// (the later '%iused' is inode usage, which we don't want), so we return
// on the first match.
func parseDFCapacityPercent(out []byte) (int, error) {
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) < 2 {
		return 0, fmt.Errorf("unexpected df output: %q", string(out))
	}
	fields := strings.Fields(lines[len(lines)-1])
	for _, f := range fields {
		if !strings.HasSuffix(f, "%") {
			continue
		}
		n, err := strconv.Atoi(strings.TrimSuffix(f, "%"))
		if err != nil {
			return 0, fmt.Errorf("parse df capacity %q: %w", f, err)
		}
		return n, nil
	}
	return 0, fmt.Errorf("no capacity column in df output: %q", string(out))
}

// IsRunning checks whether a `tart run <name>` process is currently
// executing on this host. Used as the canonical liveness signal —
// `tart ip` keeps returning the last-leased address even after the
// VM halts, and `tart list`'s State field is unreliable for
// backgrounded VMs (the on-disk state file isn't updated on exit).
// pgrep against the actual command line is the only reading that
// flips the moment the VM exits.
//
// Returns false (no error) when no matching process exists; returns
// an error only on unexpected pgrep failures.
func (c *Client) IsRunning(ctx context.Context, name string) (bool, error) {
	cmd := exec.CommandContext(ctx, "pgrep", "-f", fmt.Sprintf("tart run %s", name))
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return false, nil
		}
		return false, fmt.Errorf("pgrep tart run %s: %w", name, err)
	}
	return true, nil
}

// StageEnvFile writes a Pod's resolved env into
// <UserDataDir>/<vm>/tuist.env, ready to be shared into the guest as
// the `env` directory. The directory is created with 0o700; the file
// 0o600.
func (c *Client) StageEnvFile(name string, env map[string]string) (string, error) {
	dir := filepath.Join(c.UserDataDir, name)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("mkdir userdata: %w", err)
	}
	var b strings.Builder
	for k, v := range env {
		// Resolved values may contain newlines; escape them so the env
		// file stays parseable by the launchd shim that consumes it.
		fmt.Fprintf(&b, "%s=%s\n", k, escapeEnvValue(v))
	}
	path := filepath.Join(dir, "tuist.env")
	if err := os.WriteFile(path, []byte(b.String()), 0o600); err != nil {
		return "", fmt.Errorf("write env: %w", err)
	}
	return dir, nil
}

// StageServiceAccountToken writes a projected ServiceAccount token
// to <UserDataDir>/<vm>/sa_token (0o600). The same directory the
// env file lives in, so a single `tart run --dir env:<dir>:ro`
// mount makes both available to the guest at
// `/Volumes/My Shared Files/env/{tuist.env,sa_token}`.
//
// The VM's dispatch-poll script reads sa_token and uses it as the
// Bearer credential against the Tuist server's dispatch endpoint,
// which validates it via the Kubernetes TokenReview API.
func (c *Client) StageServiceAccountToken(name, token string) error {
	dir := filepath.Join(c.UserDataDir, name)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("mkdir userdata: %w", err)
	}
	path := filepath.Join(dir, "sa_token")
	if err := os.WriteFile(path, []byte(token), 0o600); err != nil {
		return fmt.Errorf("write sa_token: %w", err)
	}
	return nil
}

// StageVolumeManifest writes volumes.json into the VM's env dir so the guest
// (which reads the ro `env` share) learns which attached block device carries
// the Tuist cache and where to point the cache root. Absent file means "no
// cache volume this boot" and the guest runs the cold path unchanged.
func (c *Client) StageVolumeManifest(name, contents string) error {
	dir := filepath.Join(c.UserDataDir, name)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("mkdir userdata: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "volumes.json"), []byte(contents), 0o600); err != nil {
		return fmt.Errorf("write volumes.json: %w", err)
	}
	return nil
}

// StatusDir creates and returns the per-VM writable status directory
// (<UserDataDir>/<vm>/status), shared into the guest rw so the guest can
// report the cache dirty marker back to the host. World-writable because the
// virtiofs share is consumed by the guest's unprivileged `runner` user; it
// holds only the guest's own tiny marker file and is torn down with the VM.
func (c *Client) StatusDir(name string) (string, error) {
	dir := filepath.Join(c.UserDataDir, name, "status")
	if err := os.MkdirAll(dir, 0o777); err != nil {
		return "", fmt.Errorf("mkdir status dir: %w", err)
	}
	// MkdirAll honours umask; force the mode so the guest can write.
	if err := os.Chmod(dir, 0o777); err != nil {
		return "", fmt.Errorf("chmod status dir: %w", err)
	}
	return dir, nil
}

// CleanupVMUserData removes <UserDataDir>/<vm>. Best-effort.
func (c *Client) CleanupVMUserData(name string) error {
	return os.RemoveAll(filepath.Join(c.UserDataDir, name))
}

// === helpers ================================================================

func (c *Client) run(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	// Bound how long Wait blocks after the timeout context kills the
	// process. A hung `tart` that spawned children which inherited the
	// stdout/stderr pipe would otherwise keep Wait — and the single
	// reconcile worker — blocked until those children close it (the
	// exact wedge the per-op timeout is meant to prevent). WaitDelay
	// force-closes the pipes and returns shortly after the kill.
	cmd.WaitDelay = runWaitDelay
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%s %s: %w (stderr: %s)",
			name, strings.Join(args, " "), err, stderr.String())
	}
	return stdout.Bytes(), nil
}

// isNotFound recognizes Tart's "not found" error string. Tart returns
// non-zero exit + a stderr line matching "VM not found" when `tart get`
// is called for a VM Tart doesn't know about.
func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "VM not found") || strings.Contains(msg, "not found")
}

func shellJoin(parts []string) string {
	out := make([]string, len(parts))
	for i, p := range parts {
		out[i] = shellEscape(p)
	}
	return strings.Join(out, " ")
}

func shellEscape(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// escapeEnvValue collapses control characters that would corrupt a
// `KEY=value` env file. Resolved Secret values can in theory contain
// any bytes; in practice we expect URLs and tokens. Replace newline
// and CR with literal `\n` / `\r` so the launchd consumer sees a
// well-formed file.
func escapeEnvValue(v string) string {
	v = strings.ReplaceAll(v, "\n", `\n`)
	v = strings.ReplaceAll(v, "\r", `\r`)
	return v
}
