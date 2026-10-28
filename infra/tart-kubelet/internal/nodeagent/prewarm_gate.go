package nodeagent

import (
	"context"
	"sync"

	corev1 "k8s.io/api/core/v1"
)

// PrewarmTaintKey is the NoSchedule taint a freshly registered Node carries
// while it pulls the runner images its fleet's pools need. Runner Pods do not
// tolerate it, so none is placed on a host that would make it wait on a
// multi-GB download.
//
// CONTRACT: the runners-controller's allocator leaves a Node with this taint
// out of its fleet capacity (`nodeFilterReason`), so it agrees with the
// scheduler. The two live in separate Go modules, coupled by convention.
const PrewarmTaintKey = "tuist.dev/prewarming"

// PrewarmGate holds a Node out of scheduling while its runner images are
// pulled. A Node this process had to create is held: a host joining (or
// rejoining) the cluster. So is a registered Node whose host disk has never
// held a runner image, such as a host reinstalled in place, which keeps its
// Node but comes back erased. A tart-kubelet restart on any other host is not
// held, even one holding no image right now, because that host is already
// serving, and a deploy that rolls both the runner images and tart-kubelet
// would otherwise take every host out at once.
type PrewarmGate struct {
	// FreshDisk, when set, reports whether the host disk has never held a
	// runner image. An error counts as not fresh, so a failed probe never takes
	// a serving host out of scheduling.
	FreshDisk func(context.Context) (bool, error)

	decided     chan struct{}
	decidedOnce sync.Once

	mu       sync.Mutex
	held     bool
	released bool
}

func NewPrewarmGate() *PrewarmGate {
	return &PrewarmGate{decided: make(chan struct{})}
}

// decide records whether the Node was just created, or else whether the host
// disk has never held a runner image. Only the first call counts, and a gate already
// released is never held.
func (g *PrewarmGate) decide(ctx context.Context, created bool) {
	g.decidedOnce.Do(func() {
		hold := created || g.freshDisk(ctx)
		g.mu.Lock()
		g.held = hold && !g.released
		g.mu.Unlock()
		close(g.decided)
	})
}

// Wait blocks until the Maintainer has registered the Node and reports
// whether the gate holds it.
func (g *PrewarmGate) Wait(ctx context.Context) (bool, error) {
	select {
	case <-ctx.Done():
		return false, ctx.Err()
	case <-g.decided:
		return g.Held(), nil
	}
}

func (g *PrewarmGate) Held() bool {
	if g == nil {
		return false
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.held
}

// Release lets the Node take Pods. The taint goes on the next heartbeat.
func (g *PrewarmGate) Release() {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.held = false
	g.released = true
}

// applyPrewarmTaint adds the taint while the gate holds the Node and removes
// it otherwise, including one a previous process left behind when it stopped
// mid-pull.
func applyPrewarmTaint(node *corev1.Node, held bool) {
	if held {
		if !hasTaint(node.Spec.Taints, PrewarmTaintKey) {
			node.Spec.Taints = append(node.Spec.Taints, corev1.Taint{
				Key:    PrewarmTaintKey,
				Value:  "true",
				Effect: corev1.TaintEffectNoSchedule,
			})
		}
		return
	}
	kept := node.Spec.Taints[:0]
	for _, taint := range node.Spec.Taints {
		if taint.Key != PrewarmTaintKey {
			kept = append(kept, taint)
		}
	}
	node.Spec.Taints = kept
}

func (g *PrewarmGate) freshDisk(ctx context.Context) bool {
	if g.FreshDisk == nil {
		return false
	}
	fresh, err := g.FreshDisk(ctx)
	return err == nil && fresh
}
