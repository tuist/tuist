package tart

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"time"
)

// EnsureRealGUISession is the default `Client.EnsureGUISession` hook.
// It verifies the calling user has a live Aqua (loginwindow/GUI)
// launchd session and, if not, kicks loginwindow to bring one up.
//
// Apple's Virtualization framework refuses to generate a fresh
// HostKey for a macOS guest unless the calling user holds a console
// session at the moment of `tart run` — otherwise the VM exits
// immediately with `VZErrorDomain Code=-9 / Failed to create new
// HostKey` and the Pod stalls in TartCreateFailed forever. The
// bootstrap pass at provisioning time configures /etc/kcpassword +
// autoLoginUser and SIGHUPs loginwindow once, but the Aqua session
// can be torn down later (idle auto-logout, WindowServer crash,
// manual logout) and we hit the same wall on every subsequent VM
// start. Re-establishing the session before each Run makes the
// kubelet self-healing on this exact failure.
//
// Idempotent: when Aqua is already up the call is a single
// `launchctl print` and returns immediately. Otherwise it sudos a
// SIGHUP at loginwindow and polls for up to 30s — loginwindow
// usually respawns and creates the Aqua session in <2s. Loginwindow
// is the only process restarted; running Tart VMs are unaffected
// (they live in their own pgid and were detached via Setsid in
// `Run`).
//
// Requires NOPASSWD sudo for the calling user, set up by the
// bootstrap's `enablePasswordlessSudo`. Without that the sudo
// invocations would block on a password prompt and this would hang
// for the full 30s before timing out.
func EnsureRealGUISession(ctx context.Context) error {
	uid := os.Getuid()
	if hasAquaSession(ctx, uid) {
		return nil
	}
	if err := kickLoginwindow(ctx); err != nil {
		return fmt.Errorf("kick loginwindow: %w", err)
	}
	deadline := time.Now().Add(30 * time.Second)
	for {
		if hasAquaSession(ctx, uid) {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("Aqua session for uid %d did not come up within 30s after SIGHUP loginwindow", uid)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(1 * time.Second):
		}
	}
}

// hasAquaSession reports whether `gui/<uid>` exists with `session =
// Aqua`. Both the missing-domain case (`Could not print domain: 125`)
// and a Background-only session return false.
//
// `launchctl print gui/<uid>` is gated on root, so we sudo. `-n`
// (non-interactive) makes the call fail fast if NOPASSWD isn't set
// rather than blocking.
func hasAquaSession(ctx context.Context, uid int) bool {
	cmd := exec.CommandContext(ctx, "sudo", "-n", "launchctl", "print", fmt.Sprintf("gui/%d", uid))
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return bytes.Contains(out, []byte("session = Aqua"))
}

// kickLoginwindow SIGHUPs loginwindow so it respawns. The respawned
// process — unlike the boot-time one on a headless host — honors
// `autoLoginUser` and brings up the Aqua session for that user.
// Same trick the bootstrap uses; see
// `bootstrap.enableAutoLogin` for the longer-form rationale.
func kickLoginwindow(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, "sudo", "-n", "killall", "-HUP", "loginwindow")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w (output: %s)", err, bytes.TrimSpace(out))
	}
	return nil
}
