package podagent

import (
	"context"
	"errors"
	"net/http"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
)

// The server's checkout allocation: the volume identity plus what the populator
// needs. The token stays on the host; it never enters a response or the share.
type checkoutGrant struct {
	cachevolumes.Identity
	CloneURL       string    `json:"clone_url"`
	DefaultBranch  string    `json:"default_branch"`
	Commit         string    `json:"commit"`
	Token          string    `json:"token"`
	TokenExpiresAt time.Time `json:"token_expires_at"`
}

// checkout answers a guest's request for its job's checkout volume. The server
// decides the repository from the executed job; the guest only asks. It returns
// a nil response while the server is still waiting for GitHub's execution binding.
func (c *CustomVolumes) checkout(ctx context.Context, pod *corev1.Pod, uid int) map[string]any {
	var grant checkoutGrant
	status, err := c.request(ctx, "checkout", map[string]any{"pod_name": pod.Name, "pod_uid": string(pod.UID), "node_name": c.Node, "architecture": "arm64", "uid": uid}, &grant)
	if status == http.StatusTooEarly && ctx.Err() == nil {
		return nil
	}
	if err != nil {
		return map[string]any{"error": "unavailable", "reason": "denied"}
	}
	grant.Kind = cachevolumes.KindCheckout
	grant.CanPublish = false
	// Refresh behind the job, or build the first master, whatever this job gets.
	defer c.Checkouts.Enqueue(checkoutTask{
		Scope: grant.Scope, Generation: grant.Generation, CloneURL: grant.CloneURL, DefaultBranch: grant.DefaultBranch,
		Commit: grant.Commit, Token: grant.Token, TokenExpiresAt: grant.TokenExpiresAt,
	})
	cold := c.Checkouts.Master(grant.Scope, grant.Generation) == ""
	// Acquire even when cold: the journaled lease is what tells the server this
	// use ended, once the pod is gone and the empty slot is reported deleted.
	warm, err := c.Store.Acquire(ctx, grant.Identity, pod.Name, string(pod.UID))
	switch {
	case cold:
		return map[string]any{"error": "unavailable", "reason": "cold"}
	case errors.Is(err, context.DeadlineExceeded):
		return map[string]any{"error": "unavailable", "reason": "timeout"}
	case errors.Is(err, cachevolumes.ErrCapacity):
		return map[string]any{"error": "unavailable", "reason": "capacity"}
	case err != nil:
		return map[string]any{"error": "unavailable", "reason": "error"}
	}
	return map[string]any{"id": grant.ID, "directory": grant.Scope, "warm": warm}
}

// reserveCheckout holds disk for a master build beside every other image on the
// shared cache filesystem, evicting other checkout masters before refusing.
func (c *CustomVolumes) reserveCheckout(ctx context.Context, bytes uint64) (func(), error) {
	release, err := c.guard(ctx)
	if err != nil {
		return nil, err
	}
	defer release()
	free, err := c.freeBytesLocked()
	if err != nil {
		return nil, err
	}
	if free < bytes {
		c.Checkouts.Evict(func() bool {
			free, err = c.freeBytesLocked()
			return err == nil && free >= bytes
		})
		if free, err = c.freeBytesLocked(); err != nil {
			return nil, err
		}
	}
	if free < bytes {
		return nil, cachevolumes.ErrCapacity
	}
	c.checkoutReserved += bytes
	return func() {
		c.Builtins.mu.Lock()
		defer c.Builtins.mu.Unlock()
		c.checkoutReserved -= bytes
	}, nil
}
