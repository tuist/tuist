// Package tart wraps the `tart` CLI as the runtime backend for tart-cri.
//
// The mapping is one-to-one: each method here corresponds to a single
// `tart <subcommand>` invocation. We don't try to be clever about
// caching state — Tart itself is the source of truth for VM lifecycle.
//
// Concurrency: callers can invoke methods concurrently. Tart's CLI is
// safe for parallel use against different VM names; we don't currently
// guard against the same name being created twice in parallel because
// CRI's contract guarantees the kubelet won't do that.
package tart

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Runtime is a thin wrapper around the `tart` CLI. Use NewRuntime in
// production; in tests, swap the Exec field for a fake.
type Runtime struct {
	// Binary is the path to the `tart` binary. Defaults to looking it
	// up on PATH at construction time.
	Binary string

	// Exec runs a command and returns its stdout. Overridable in tests.
	Exec func(ctx context.Context, name string, args ...string) ([]byte, error)
}

// NewRuntime returns a Runtime backed by the real `tart` binary on
// PATH. Returns an error if `tart` isn't found.
func NewRuntime() (*Runtime, error) {
	bin, err := exec.LookPath("tart")
	if err != nil {
		return nil, fmt.Errorf("tart binary not on PATH: %w", err)
	}
	return &Runtime{
		Binary: bin,
		Exec: func(ctx context.Context, name string, args ...string) ([]byte, error) {
			cmd := exec.CommandContext(ctx, name, args...)
			var stdout, stderr bytes.Buffer
			cmd.Stdout = &stdout
			cmd.Stderr = &stderr
			if err := cmd.Run(); err != nil {
				return nil, fmt.Errorf("tart %s: %w (stderr: %s)",
					strings.Join(args, " "), err, stderr.String())
			}
			return stdout.Bytes(), nil
		},
	}, nil
}

// Pull invokes `tart pull <image>`. Idempotent: Tart skips the pull
// when the image is already present locally.
func (r *Runtime) Pull(ctx context.Context, image string) error {
	_, err := r.run(ctx, "pull", image)
	return err
}

// Clone invokes `tart clone <image> <name>`. Used by CreateContainer
// to materialize a per-VM filesystem from the OCI image.
func (r *Runtime) Clone(ctx context.Context, image, name string) error {
	_, err := r.run(ctx, "clone", image, name)
	return err
}

// SetParameters configures cpu/memory/disk for a created VM. Called
// after Clone, before Run.
func (r *Runtime) SetParameters(ctx context.Context, name string, cpu, memoryMB int) error {
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
	_, err := r.run(ctx, args...)
	return err
}

// Run starts a VM in the background. Returns when the VM is in the
// "running" state or the context is cancelled. The returned function
// stops the VM gracefully; callers typically defer it.
func (r *Runtime) Run(ctx context.Context, name string, opts RunOptions) error {
	args := []string{"run", name, "--no-graphics"}

	if opts.UserData != "" {
		args = append(args, "--user-data", opts.UserData)
	}
	for _, dir := range opts.SharedDirs {
		args = append(args, "--dir", dir)
	}

	// `tart run` blocks until the VM exits. We background it via the
	// shell so this method returns once the VM is *started*.
	bg := exec.CommandContext(ctx, r.Binary, args...)
	if err := bg.Start(); err != nil {
		return fmt.Errorf("tart run %s: %w", name, err)
	}

	// Poll until the VM is reported running, or the context cancels.
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
		vm, err := r.Get(ctx, name)
		if err == nil && vm.State == "running" {
			return nil
		}
	}
	return fmt.Errorf("tart run %s: did not reach running state in 60s", name)
}

// RunOptions are the optional knobs for Run. Most VMs use the
// zero-value.
type RunOptions struct {
	// UserData is a path to a file containing per-VM data the VM
	// surfaces to the guest via /private/var/db/vmctl/user-data.
	// Used to inject env vars into the guest at first boot.
	UserData string

	// SharedDirs is `name:path` pairs to bind-mount into the VM at
	// /Volumes/My Shared Files/<name>.
	SharedDirs []string
}

// Stop sends a graceful shutdown to the VM and waits for it to exit.
func (r *Runtime) Stop(ctx context.Context, name string, gracePeriod time.Duration) error {
	args := []string{"stop", name}
	if gracePeriod > 0 {
		args = append(args, "--timeout", fmt.Sprintf("%d", int(gracePeriod.Seconds())))
	}
	_, err := r.run(ctx, args...)
	return err
}

// Delete removes a VM's filesystem.
func (r *Runtime) Delete(ctx context.Context, name string) error {
	_, err := r.run(ctx, "delete", name)
	return err
}

// Get returns the current state of a single VM.
func (r *Runtime) Get(ctx context.Context, name string) (*VM, error) {
	out, err := r.run(ctx, "get", name, "--format", "json")
	if err != nil {
		return nil, err
	}
	var vm VM
	if err := json.Unmarshal(out, &vm); err != nil {
		return nil, fmt.Errorf("parse tart get %s: %w", name, err)
	}
	vm.Name = name
	return &vm, nil
}

// List returns all VMs known to Tart.
func (r *Runtime) List(ctx context.Context) ([]VM, error) {
	out, err := r.run(ctx, "list", "--format", "json")
	if err != nil {
		return nil, err
	}
	var vms []VM
	if err := json.Unmarshal(out, &vms); err != nil {
		return nil, fmt.Errorf("parse tart list: %w", err)
	}
	return vms, nil
}

// IP returns the VM's primary IPv4 address, blocking until one is
// assigned (or ctx cancels).
func (r *Runtime) IP(ctx context.Context, name string) (string, error) {
	out, err := r.run(ctx, "ip", name, "--wait", "30")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// VM is the subset of `tart get` output tart-cri reads.
type VM struct {
	Name   string `json:"-"`
	Source string `json:"Source"`
	State  string `json:"State"`
	CPU    int    `json:"CPU"`
	Memory int    `json:"Memory"`
	Size   int64  `json:"Size"`
}

func (r *Runtime) run(ctx context.Context, args ...string) ([]byte, error) {
	return r.Exec(ctx, r.Binary, args...)
}
