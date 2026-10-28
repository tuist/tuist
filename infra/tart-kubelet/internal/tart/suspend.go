package tart

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
)

const lifecycleTimeout = 2 * time.Minute

// Exec runs a command through Tart's per-VM host-local control socket and the
// guest agent (vsock), without relying on a cached DHCP address or a network
// listener. The caller supplies the deadline. Commands must be nonempty.
func (c *Client) Exec(ctx context.Context, name string, command ...string) ([]byte, error) {
	if len(command) == 0 {
		return nil, errors.New("guest command is required")
	}
	return c.run(ctx, c.Binary, append([]string{"exec", name}, command...)...)
}

// Suspend saves the VM on this host and waits for Tart to release it. The
// suspend CLI only delivers SIGUSR1; its exit is not proof that saving finished.
// Requires the handle of the currently owned process: a partial state file can
// survive a failed save, so Tart's "suspended" state alone is not proof of success.
// A stopped VM is an error, not a successful suspension. On any error callers
// must retain the capacity charge and reconcile the VM before releasing it.
// Serialize this with all other lifecycle operations for the same VM.
func (c *Client) Suspend(ctx context.Context, handle *RunHandle) error {
	if handle == nil {
		return errors.New("suspend requires the owned Tart process handle")
	}
	name := handle.Name
	ctx, cancel := context.WithTimeout(ctx, lifecycleTimeout)
	defer cancel()
	vm, err := c.Get(ctx, name)
	if err != nil {
		return err
	}
	if vm == nil {
		return fmt.Errorf("cannot suspend missing VM %s", name)
	}
	switch strings.ToLower(vm.State) {
	case "running":
		if _, err := c.run(ctx, c.Binary, "suspend", name); err != nil {
			return err
		}
	case "suspended": // A retry after a lost acknowledgement.
	default:
		return fmt.Errorf("cannot suspend VM %s in state %q", name, vm.State)
	}
	select {
	case <-handle.Done():
		if err, _ := handle.Exited(); err != nil {
			return fmt.Errorf("VM %s failed while suspending: %w (log: %s)", name, err, handle.LogPath)
		}
	case <-ctx.Done():
		return fmt.Errorf("waiting for VM %s to suspend: %w", name, ctx.Err())
	}
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		vm, err := c.Get(ctx, name)
		if err != nil {
			return fmt.Errorf("checking suspension: %w", err)
		}
		if vm == nil || strings.EqualFold(vm.State, "stopped") {
			return fmt.Errorf("VM %s stopped without a restorable snapshot", name)
		}
		if strings.EqualFold(vm.State, "suspended") {
			// Tart reports suspended when its lock is released and a state file
			// exists. Also fence the old process before spending its resources.
			running, err := c.IsRunning(ctx, name)
			if err != nil {
				return err
			}
			if !running {
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("waiting for VM %s to suspend: %w", name, ctx.Err())
		case <-ticker.C:
		}
	}
}

// Resume starts only a suspended VM, without a cold-boot fallback or a fixed
// startup delay. Call WaitReady to establish guest readiness. The caller must
// first reserve CI-safe capacity on this same host, serialize lifecycle calls,
// and reuse the original disks, shares and device configuration. A timeout or
// readiness failure does not stop the VM or release that reservation.
func (c *Client) Resume(ctx context.Context, name string, opts RunOptions) (*RunHandle, error) {
	vm, err := c.Get(ctx, name)
	if err != nil {
		return nil, err
	}
	if vm == nil || !strings.EqualFold(vm.State, "suspended") {
		return nil, fmt.Errorf("VM %s has no suspended state; refusing a cold boot", name)
	}
	opts.Suspendable = true
	return c.StartWithOptions(ctx, name, opts)
}

// WaitReady waits for a successful guest RPC while also watching Tart's process.
// An IP or an open TCP port alone is insufficient: the probe should authenticate
// to the guest and execute a command/ping. Probes must honor their context; each
// has a one-second budget and starts immediately (then every 100ms after failure).
// This wait belongs in a lifecycle worker, never the single Pod reconciler.
func (h *RunHandle) WaitReady(ctx context.Context, probe func(context.Context) error) error {
	if probe == nil {
		return errors.New("guest readiness probe is required")
	}
	ctx, cancel := context.WithTimeout(ctx, lifecycleTimeout)
	defer cancel()
	go func() {
		select {
		case <-h.Done():
			cancel()
		case <-ctx.Done():
		}
	}()
	var lastErr error
	for {
		if err := h.readinessError(ctx); err != nil {
			return errors.Join(err, lastErr)
		}
		probeCtx, stopProbe := context.WithTimeout(ctx, time.Second)
		lastErr = probe(probeCtx)
		stopProbe()
		if err := h.readinessError(ctx); err != nil {
			return errors.Join(err, lastErr)
		}
		if lastErr == nil {
			return nil
		}
		timer := time.NewTimer(100 * time.Millisecond)
		select {
		case <-ctx.Done():
			timer.Stop()
		case <-timer.C:
		}
	}
}

func (h *RunHandle) readinessError(ctx context.Context) error {
	if err, exited := h.Exited(); exited {
		return fmt.Errorf("VM %s exited before guest readiness (exit: %v; log: %s)", h.Name, err, h.LogPath)
	}
	return ctx.Err()
}
