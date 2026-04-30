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
	"time"
)

// Client wraps the local `tart` binary.
type Client struct {
	// Binary is the path to the `tart` CLI on this Mac mini.
	// Defaults to /opt/homebrew/bin/tart (Homebrew on Apple Silicon).
	Binary string

	// UserDataDir is the host directory where per-VM env files live.
	// Defaults to /var/lib/tart-userdata. The kubelet stages
	// /var/lib/tart-userdata/<vm>/tuist.env before `tart run` and
	// shares the directory into the guest as `env`.
	UserDataDir string

	// LogDir is where per-VM `tart run` stdout/stderr is redirected.
	// Defaults to /var/log/tart-vms.
	LogDir string
}

// New returns a Client with sensible defaults.
func New() *Client {
	return &Client{
		Binary:      "/opt/homebrew/bin/tart",
		UserDataDir: "/var/lib/tart-userdata",
		LogDir:      "/var/log/tart-vms",
	}
}

// VM is the subset of `tart get`/`tart list` JSON we care about.
type VM struct {
	Name   string `json:"-"`
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

// Run starts a VM in the background and returns once it has obtained
// an IP (proxy for "booted enough to talk to"). The VM keeps running
// until Stop or Delete.
//
// Tart 2.32 quirks accommodated here:
//   - `tart run` is foreground-only: we wrap it with `nohup`+stdio
//     redirection so the parent can return.
//   - `tart get` doesn't update on-disk state for backgrounded VMs, so
//     we poll `tart ip --wait` instead of state.
func (c *Client) Run(ctx context.Context, name string, sharedDirs []string) error {
	if err := os.MkdirAll(c.LogDir, 0o755); err != nil {
		return fmt.Errorf("mkdir log dir: %w", err)
	}

	args := []string{c.Binary, "run", name, "--no-graphics"}
	for _, dir := range sharedDirs {
		args = append(args, "--dir", dir)
	}

	logPath := filepath.Join(c.LogDir, name+".log")
	cmdline := shellJoin(args)

	// Re-exec via /bin/sh so we can use `nohup … &` to detach. The
	// kubelet process should not hold the VM as a child — VMs outlive
	// individual reconciles.
	bg := fmt.Sprintf("nohup %s >%s 2>&1 &", cmdline, shellEscape(logPath))
	if _, err := c.run(ctx, "/bin/sh", "-c", bg); err != nil {
		return err
	}

	deadline := time.Now().Add(2 * time.Minute)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(3 * time.Second):
		}
		if ip, err := c.IP(ctx, name); err == nil && ip != "" {
			return nil
		}
	}
	return fmt.Errorf("tart run %s: VM did not obtain an IP in 2m", name)
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

