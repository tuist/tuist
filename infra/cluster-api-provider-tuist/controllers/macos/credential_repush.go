package macos

import (
	"context"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// credentialRepush decides when a macOS host gets its kubeconfig pushed again
// although its host config has not drifted.
//
// A host authenticates with a token it rotates itself (tart-kubelet's
// internal/nodecred), well before half its lifetime. A host that cannot reach
// the API server for longer than the rest of that lifetime (powered off,
// network cut, tart-kubelet crash-looping) comes back with an expired token
// and can never heartbeat again, and the drift loop pushes only when the
// config hash moves, which the per-host kubeconfig is not part of. So once a
// Node has been NotReady or Unknown with no heartbeat for half the token
// lifetime, its token may be gone, and the drift loop pushes a freshly minted
// one. A host whose problem is something else gets one such push per half
// lifetime, which keeps a valid token on it until it recovers.
//
// The last push per host is kept in memory: an operator restart costs at most
// one extra push per quiet host.
type credentialRepush struct {
	mu   sync.Mutex
	last map[string]time.Time
}

// due reports whether node should get a fresh credential now. ttl is the
// lifetime of the tokens the operator mints. A missing Node is not due:
// registering one is bootstrap's job.
func (c *credentialRepush) due(ctx context.Context, r client.Reader, node string, ttl time.Duration, now time.Time) (bool, error) {
	n := &corev1.Node{}
	if err := r.Get(ctx, client.ObjectKey{Name: node}, n); err != nil {
		return false, client.IgnoreNotFound(err)
	}
	quietFor := ttl / 2
	var heartbeat time.Time
	for _, cond := range n.Status.Conditions {
		if cond.Type != corev1.NodeReady {
			continue
		}
		if cond.Status == corev1.ConditionTrue {
			return false, nil
		}
		heartbeat = cond.LastHeartbeatTime.Time
	}
	if heartbeat.IsZero() {
		// Never heartbeat: fall back to when the Node was registered.
		heartbeat = n.CreationTimestamp.Time
	}
	if now.Sub(heartbeat) < quietFor {
		return false, nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	last, ok := c.last[node]
	return !ok || now.Sub(last) >= quietFor, nil
}

// pushed records a successful push of a fresh credential to node.
func (c *credentialRepush) pushed(node string, now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.last == nil {
		c.last = map[string]time.Time{}
	}
	c.last[node] = now
}
