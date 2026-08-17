// Package hostwork answers one question about the machine
// tart-kubelet runs on: is it currently doing work that a
// host-disruptive action must not interrupt?
//
// It exists because that question has no answer in the Kubernetes API
// for every fleet. Pods cover the hosts that run Pods, but the builder
// fleet runs GitHub Actions image bakes under a launchd LaunchAgent and
// no Pod ever selects those nodes, so the apiserver sees an idle host
// whether or not a bake is halfway through `tart push`. The host itself
// is the only place both kinds of work are visible at once, so the
// probe runs here and tart-kubelet publishes the verdict onto its own
// Node object — turning a host-local fact into cluster-visible state
// that any controller can read.
//
// The consumer today is the CAPI provider's recovery reboot for a mini
// whose inbound :22 has wedged. That reboot is the only lever left when
// the SSH management path is gone, and it is safe exactly when this
// probe says the host is idle.
package hostwork

import (
	"context"
	"fmt"
	"os/exec"
)

// VMProber is the slice of the Tart client this package needs.
// Declared here so tests can answer without a Tart daemon.
type VMProber interface {
	AnyRunning(ctx context.Context) (bool, error)
}

// runnerWorkerPattern matches the per-job process the GitHub Actions
// runner spawns. The agent itself (Runner.Listener) runs continuously
// on a builder and says nothing about whether a job is in flight;
// Runner.Worker exists only while one is. It is the host-local
// equivalent of the `busy` flag GitHub's runners API reports, without
// the API call, the credentials, or the dependency on GitHub being
// reachable at the moment we need an answer.
const runnerWorkerPattern = `Runner\.Worker`

// Probe reports whether the host is busy, with a detail string for the
// Node condition message.
//
// Two independent signals, ORed, because neither covers the other's
// window:
//
//   - A running Tart VM covers pod workloads and the provisioning phase
//     of an image bake.
//   - A Runner.Worker process covers the whole bake, including the
//     `tart push` tail where the VM has already been stopped and a
//     VM-only probe would report the host idle — which is precisely the
//     window the orphan-VM GC had to be disabled to protect.
//
// An error from either signal is returned rather than folded into
// "idle": the caller leaves the previous verdict in place instead of
// asserting an idleness it could not confirm.
func Probe(ctx context.Context, vms VMProber) (bool, string, error) {
	if vms != nil {
		running, err := vms.AnyRunning(ctx)
		if err != nil {
			return false, "", fmt.Errorf("probe running tart VMs: %w", err)
		}
		if running {
			return true, "a Tart VM is running on this host", nil
		}
	}
	working, err := processMatches(ctx, runnerWorkerPattern)
	if err != nil {
		return false, "", fmt.Errorf("probe actions-runner job: %w", err)
	}
	if working {
		return true, "a GitHub Actions job is executing on this host", nil
	}
	return false, "no Tart VM or Actions job is running on this host", nil
}

// processMatches reports whether any process command line matches
// pattern. Exit code 1 is pgrep's "no match", which is an answer, not a
// failure; anything else is a real error.
func processMatches(ctx context.Context, pattern string) (bool, error) {
	cmd := exec.CommandContext(ctx, "pgrep", "-f", pattern)
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return false, nil
		}
		return false, fmt.Errorf("pgrep %q: %w", pattern, err)
	}
	return true, nil
}
