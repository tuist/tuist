package sandbox

import (
	"context"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"strconv"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// armCheckout lets a worker's guest start from the node's master of its
// repository and export back to it, for as long as the worker runs: it
// listens on the checkout vsock port and returns the worker env that tells the
// guest so. Without a grant, an agent or the listener, the env is unchanged
// and the guest clones as it would otherwise. The returned function stops
// serving.
func (m *Manager) armCheckout(inst vm.Instance, args protocol.StartWorkerArgs, log *slog.Logger) (map[string]string, func()) {
	grant := args.Checkout
	if grant == nil {
		return args.Env, func() {}
	}
	if m.checkouts == nil {
		log.Info("checkout granted, but no checkout agent is configured on this node")
		return args.Env, func() {}
	}
	if grant.ID == "" || !filepath.IsAbs(grant.Path) || filepath.Clean(grant.Path) != grant.Path {
		log.Warn("ignoring an invalid checkout grant", "use", grant.ID, "path", grant.Path)
		return args.Env, func() {}
	}
	if inst == nil {
		return args.Env, func() {}
	}
	path := inst.VsockPath() + "_" + strconv.Itoa(checkout.GuestPort)
	listener, err := listenForVMM(path, inst.Root())
	if err != nil {
		log.Warn("serving the checkout to the guest", "use", grant.ID, "error", err)
		return args.Env, func() {}
	}
	env := maps.Clone(args.Env)
	if env == nil {
		env = map[string]string{}
	}
	env[protocol.CheckoutPathEnv] = grant.Path
	env[protocol.CheckoutCommitEnv] = grant.Commit
	env[protocol.CheckoutVsockEnv] = strconv.Itoa(checkout.GuestPort)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		checkout.Serve(ctx, listener, m.checkouts, *grant, m.checkoutLimits, log)
	}()
	return env, func() {
		cancel()
		<-done
		os.Remove(path)
	}
}
