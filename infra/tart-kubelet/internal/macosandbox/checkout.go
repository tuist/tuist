package macosandbox

import (
	"context"
	"log/slog"
	"maps"
	"regexp"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// Checkouts is the host's checkout masters, the ones CI VMs start from
// (podagent.CustomVolumes). A sandbox VM boots with a share of its own on the
// cache volume, fixed for its life like every share: a restore needs the same
// set. Before a session's worker starts, the master's clone goes in it; the
// guest copies the tree to the session's repository directory. After the
// session, the guest leaves an export there, which the host takes only once
// the VM no longer runs (an eviction's save or a delete), so nothing in the
// guest writes what the host reads.
type Checkouts interface {
	SandboxShare(vm string) (string, error)
	RemoveSandboxShare(vm string) error
	SeedSandbox(ctx context.Context, grant protocol.CheckoutGrant, share string) bool
	CollectSandbox(grant protocol.CheckoutGrant, share string)
}

// The share's name; the guest sees it under /Volumes/My Shared Files.
const checkoutShareName = "sandbox-checkout"
const guestCheckoutShare = "/Volumes/My Shared Files/" + checkoutShareName

var (
	checkoutScope  = regexp.MustCompile(`^[a-f0-9]{64}$`)
	checkoutCommit = regexp.MustCompile(`^[a-f0-9]{40}$`)
	checkoutUse    = regexp.MustCompile(`^[a-f0-9-]{36}$`)
	checkoutPath   = regexp.MustCompile(`^/Users/runner/work/claude-code/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
)

func validCheckoutGrant(g *protocol.CheckoutGrant) bool {
	return g != nil && checkoutUse.MatchString(g.ID) && checkoutScope.MatchString(g.Scope) && checkoutScope.MatchString(g.VolumeKey) &&
		checkoutCommit.MatchString(g.Commit) && checkoutPath.MatchString(g.Path) && g.Generation >= 0 && g.BaseGeneration >= 0
}

// checkoutEnv seeds the share for a worker start and returns its environment
// with the checkout variables, or env unchanged when the VM cannot take the
// grant. Called under the gate with the VM running.
func (m *Manager) checkoutEnv(ctx context.Context, r *Record, env map[string]string, grant *protocol.CheckoutGrant) map[string]string {
	if grant == nil {
		return env
	}
	if m.Checkouts == nil || r.CheckoutShare == "" || !validCheckoutGrant(grant) {
		slog.Info("macOS sandbox starts without its checkout", "sandbox", r.SandboxID, "share", r.CheckoutShare != "")
		return env
	}
	warm := m.Checkouts.SeedSandbox(ctx, *grant, r.CheckoutShare)
	slog.Info("macOS sandbox checkout", "sandbox", r.SandboxID, "scope", grant.Scope, "warm", warm)
	// The export is taken at the next fence even when this start was cold.
	r.Checkout = grant
	env = maps.Clone(env)
	env[protocol.CheckoutPathEnv] = grant.Path
	env[protocol.CheckoutCommitEnv] = grant.Commit
	env[protocol.CheckoutShareEnv] = guestCheckoutShare
	return env
}

// collectCheckout takes the session's export once its VM is fenced.
func (m *Manager) collectCheckout(r *Record) {
	if r.Checkout == nil {
		return
	}
	if m.Checkouts != nil && r.CheckoutShare != "" {
		m.Checkouts.CollectSandbox(*r.Checkout, r.CheckoutShare)
	}
	r.Checkout = nil
}
