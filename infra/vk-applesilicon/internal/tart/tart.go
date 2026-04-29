// Package tart drives the `tart` CLI on a remote Mac mini over SSH.
//
// The VK provider has a fleet of Mac minis; for each Pod it schedules,
// it picks one host and invokes Tart commands there. This package
// owns the SSH+CLI mechanics so the VK provider only deals with
// "this VM, please" semantics.
package tart

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

// Client drives Tart on one Mac mini over a persistent SSH connection.
// Safe for concurrent use from multiple goroutines (each method opens
// its own SSH session).
type Client struct {
	conn *ssh.Client

	// Binary is the path to the `tart` CLI on the Mac mini.
	// Defaults to /opt/homebrew/bin/tart (Homebrew's Apple Silicon
	// install path).
	Binary string
}

// Dial opens an SSH connection to `addr` (host:port form) using the
// supplied key. Caller closes the returned Client when done.
func Dial(ctx context.Context, addr, user string, privateKey []byte) (*Client, error) {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return nil, fmt.Errorf("parse ssh key: %w", err)
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         15 * time.Second,
	}
	conn, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return nil, fmt.Errorf("ssh dial %s: %w", addr, err)
	}
	return &Client{conn: conn, Binary: "/opt/homebrew/bin/tart"}, nil
}

// Close releases the SSH connection.
func (c *Client) Close() error {
	if c.conn == nil {
		return nil
	}
	return c.conn.Close()
}

// Pull invokes `tart pull <image>`. Idempotent: Tart skips re-download
// when the image is already cached.
func (c *Client) Pull(ctx context.Context, image string) error {
	_, err := c.run(ctx, "pull", image)
	return err
}

// Clone invokes `tart clone <source> <name>`. Used to materialize a
// per-VM filesystem from a base image.
func (c *Client) Clone(ctx context.Context, source, name string) error {
	_, err := c.run(ctx, "clone", source, name)
	return err
}

// Set configures cpu/memory for a cloned VM. Call before Run.
// Pass 0 to skip a parameter.
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
	_, err := c.run(ctx, args...)
	return err
}

// Run starts a VM in the background. Returns once the VM is reported
// `running` or the context is cancelled. Doesn't block on VM
// completion — the VM lives until Stop/Delete is called.
//
// Tart's `run` is foreground-only; we wrap it with `nohup` + background
// redirection so the SSH session can return.
func (c *Client) Run(ctx context.Context, name string, opts RunOptions) error {
	args := []string{c.Binary, "run", name, "--no-graphics"}
	// Pod env is injected via a shared dir mounted into the guest at
	// /Volumes/My Shared Files/<tag>; the xcresult image's launchd
	// reads /etc/tuist.env from there at boot. Tart 2.32 dropped
	// --user-data; we use --dir with the staged userdata file's
	// parent directory and a fixed `env` tag.
	for _, dir := range opts.SharedDirs {
		args = append(args, "--dir", shellEscape(dir))
	}
	cmdline := strings.Join(args, " ")
	// Background via `nohup`; redirect stdio so SSH session exits.
	bg := fmt.Sprintf(
		"sudo mkdir -p /var/log/tart-vms && nohup %s >/var/log/tart-vms/%s.log 2>&1 &",
		cmdline, shellEscape(name),
	)
	if _, err := c.run(ctx, "/bin/sh", "-c", bg); err != nil {
		return err
	}

	// Poll until the VM has booted far enough to obtain an IP. We
	// can't poll `tart get` for State=="running" because Tart 2.32's
	// CLI doesn't update the on-disk state file for backgrounded VMs
	// — `get` reports "stopped" forever even when Apple's
	// Virtualization process is happily running the guest. `tart ip`
	// is the closest reliable probe: it returns the guest's IP only
	// once VM networking is up, which strictly implies the VM is
	// running.
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

// RunOptions are knobs for Run.
type RunOptions struct {
	// UserData paths inside the Mac mini. Each entry becomes a
	// `--user-data <path>` flag. Tart serves the file to the guest
	// via /private/var/db/vmctl/.
	UserData []string

	// SharedDirs is "name:path" pairs to bind-mount.
	SharedDirs []string
}

// Stop gracefully halts a running VM.
func (c *Client) Stop(ctx context.Context, name string, gracePeriod time.Duration) error {
	args := []string{"stop", name}
	if gracePeriod > 0 {
		args = append(args, "--timeout", fmt.Sprintf("%d", int(gracePeriod.Seconds())))
	}
	_, err := c.run(ctx, args...)
	return err
}

// Delete removes a VM's filesystem.
func (c *Client) Delete(ctx context.Context, name string) error {
	_, err := c.run(ctx, "delete", name)
	return err
}

// Get returns one VM's current state. Returns (nil, nil) if the VM
// doesn't exist.
func (c *Client) Get(ctx context.Context, name string) (*VM, error) {
	out, err := c.run(ctx, "get", name, "--format", "json")
	if err != nil {
		// Tart returns non-zero on missing VM; surface as nil/nil so
		// callers can distinguish "not found" from "Tart broken".
		if strings.Contains(err.Error(), "VM not found") || strings.Contains(err.Error(), "not found") {
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

// List returns every VM known to Tart on this host.
func (c *Client) List(ctx context.Context) ([]VM, error) {
	out, err := c.run(ctx, "list", "--format", "json")
	if err != nil {
		return nil, err
	}
	var vms []VM
	if err := json.Unmarshal(out, &vms); err != nil {
		return nil, fmt.Errorf("parse tart list: %w", err)
	}
	return vms, nil
}

// IP returns the VM's primary IPv4 address, blocking up to 30s.
func (c *Client) IP(ctx context.Context, name string) (string, error) {
	out, err := c.run(ctx, "ip", name, "--wait", "30")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// MkdirP runs `mkdir -p` for each path on the host. Used to ensure
// parent directories exist before WriteFile (tee doesn't create them).
func (c *Client) MkdirP(ctx context.Context, paths ...interface{}) error {
	// Last arg can optionally be a bool flag for sudo; keep the
	// signature flexible so callers don't have to wrap.
	useSudo := false
	stringPaths := make([]string, 0, len(paths))
	for _, p := range paths {
		switch v := p.(type) {
		case string:
			stringPaths = append(stringPaths, v)
		case bool:
			useSudo = v
		}
	}
	parts := []string{"mkdir", "-p"}
	parts = append(parts, stringPaths...)
	cmdline := ""
	for _, part := range parts {
		if cmdline != "" {
			cmdline += " "
		}
		cmdline += shellEscape(part)
	}
	if useSudo {
		cmdline = "sudo " + cmdline
	}
	r := c.runWithStdin(ctx, "", "/bin/sh", "-c", cmdline)
	return r.err
}

// WriteFile uploads `contents` to `remotePath` on the host. Uses
// `cat | sudo tee` so the path can be root-owned. Used for staging
// per-VM user-data files before `tart run`.
func (c *Client) WriteFile(ctx context.Context, remotePath, contents string, sudo bool) error {
	cmd := "tee " + shellEscape(remotePath) + " >/dev/null"
	if sudo {
		cmd = "sudo " + cmd
	}
	r := c.runWithStdin(ctx, contents, "/bin/sh", "-c", cmd)
	return r.err
}

// VM is the subset of `tart get` output we read.
type VM struct {
	Name   string `json:"-"`
	Source string `json:"Source"`
	State  string `json:"State"`
	CPU    int    `json:"CPU"`
	Memory int    `json:"Memory"`
	Size   int64  `json:"Size"`
}

// === SSH helpers ============================================================

func (c *Client) run(ctx context.Context, argv ...string) ([]byte, error) {
	return c.runWithStdin(ctx, "", argv...).bytes()
}

func (c *Client) runWithStdin(ctx context.Context, stdin string, argv ...string) execResult {
	if c.conn == nil {
		return execResult{err: fmt.Errorf("ssh client closed")}
	}
	session, err := c.conn.NewSession()
	if err != nil {
		return execResult{err: err}
	}
	defer session.Close()

	if stdin != "" {
		session.Stdin = strings.NewReader(stdin)
	}

	var stdout, stderr bytes.Buffer
	session.Stdout = &stdout
	session.Stderr = &stderr

	cmd := commandLine(argv, c.Binary)
	done := make(chan error, 1)
	go func() {
		done <- session.Run(cmd)
	}()
	select {
	case <-ctx.Done():
		_ = session.Signal(ssh.SIGTERM)
		return execResult{err: ctx.Err()}
	case err := <-done:
		if err != nil {
			return execResult{err: fmt.Errorf("ssh exec %q: %w (stderr: %s)", cmd, err, stderr.String())}
		}
		return execResult{out: stdout.Bytes()}
	}
}

type execResult struct {
	out []byte
	err error
}

func (r execResult) bytes() ([]byte, error) { return r.out, r.err }

// commandLine builds the shell command to run. If argv[0] starts with
// `/`, run it as-is. Otherwise, prefix the tart binary path so callers
// can write `c.run(ctx, "pull", image)` without remembering the full
// path each time.
func commandLine(argv []string, tartBinary string) string {
	if len(argv) == 0 {
		return ""
	}
	if strings.HasPrefix(argv[0], "/") {
		// Caller gave a full path; quote each arg.
		parts := make([]string, len(argv))
		for i, a := range argv {
			parts[i] = shellEscape(a)
		}
		return strings.Join(parts, " ")
	}
	parts := []string{tartBinary}
	for _, a := range argv {
		parts = append(parts, shellEscape(a))
	}
	return strings.Join(parts, " ")
}

func shellEscape(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
