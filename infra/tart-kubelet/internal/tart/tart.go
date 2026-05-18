// Package tart drives the local `tart` CLI on the Mac mini this
// tart-kubelet instance is running on.
//
// The kubelet runs as root via launchd and shells out directly. No SSH:
// the agent owns the host. Pods scheduled to this Node become VMs
// managed here.
package tart

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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
	Size   int64  `json:"Size"`
}

// Pull invokes `tart pull <image>`. Idempotent — Tart skips re-download
// when the image is already cached.
func (c *Client) Pull(ctx context.Context, image string) error {
	_, err := c.run(ctx, c.Binary, "pull", image)
	return err
}

// Clone invokes `tart clone <source> <name>`.
func (c *Client) Clone(ctx context.Context, source, name string) error {
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

	done    chan struct{}
	exitErr error
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

	args := []string{"run", name, "--no-graphics"}
	for _, dir := range sharedDirs {
		args = append(args, "--dir", dir)
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
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		return nil, fmt.Errorf("start tart run: %w", err)
	}
	// Close our own fd; the child holds its own dup. The launcher
	// goroutine reaps the process via cmd.Wait so it doesn't go
	// zombie if it exits before we Stop it.
	_ = logFile.Close()

	handle := &RunHandle{
		Name:    name,
		LogPath: logPath,
		done:    make(chan struct{}),
	}
	// Single launcher goroutine owns cmd.Wait for the lifetime of
	// the process. Writing exitErr before close(done) gives readers
	// of Exited() a happens-before relationship on the field — no
	// extra mutex needed.
	go func() {
		handle.exitErr = cmd.Wait()
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
		return nil, fmt.Errorf("tart run %s exited immediately: %w (see %s)", name, handle.exitErr, logPath)
	case <-ctx.Done():
		// Parent ctx cancelled. The Setsid-detached process keeps
		// running; recoverState rebinds it after a kubelet restart.
		return nil, ctx.Err()
	case <-time.After(5 * time.Second):
		return handle, nil
	}
}

// Stop gracefully halts a VM.
func (c *Client) Stop(ctx context.Context, name string, gracePeriod time.Duration) error {
	args := []string{"stop", name}
	if gracePeriod > 0 {
		args = append(args, "--timeout", fmt.Sprintf("%d", int(gracePeriod.Seconds())))
	}
	_, err := c.run(ctx, c.Binary, args...)
	return err
}

// Delete removes a VM's filesystem.
func (c *Client) Delete(ctx context.Context, name string) error {
	_, err := c.run(ctx, c.Binary, "delete", name)
	return err
}

// Get returns one VM's metadata, or (nil, nil) if it doesn't exist.
func (c *Client) Get(ctx context.Context, name string) (*VM, error) {
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

// CleanupVMUserData removes <UserDataDir>/<vm>. Best-effort.
func (c *Client) CleanupVMUserData(name string) error {
	return os.RemoveAll(filepath.Join(c.UserDataDir, name))
}

// === helpers ================================================================

func (c *Client) run(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
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
