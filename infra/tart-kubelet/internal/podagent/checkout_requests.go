package podagent

import (
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
)

// The server's checkout allocation: the volume identity, its HEAD, and what the
// populator needs to build a master from the job's export.
type checkoutGrant struct {
	cachevolumes.Identity
	CloneURL         string `json:"clone_url"`
	DefaultBranch    string `json:"default_branch"`
	Commit           string `json:"commit"`
	DefaultBranchJob bool   `json:"default_branch_job"`
	MayStartMaster   bool   `json:"may_start_master"`
	VolumeKey        string `json:"volume_key"`
}

// checkout answers a guest's request for its job's checkout volume. The server
// decides the repository from the executed job; the guest only asks. It returns
// a nil response while the server is still waiting for GitHub's execution binding.
func (c *CustomVolumes) checkout(ctx context.Context, pod *corev1.Pod, uid int) map[string]any {
	// Without working git the host builds nothing, so the guest should not export.
	if !c.Checkouts.Ready() {
		return map[string]any{"error": "unavailable", "reason": "denied"}
	}
	var grant checkoutGrant
	status, err := c.request(ctx, "checkout", map[string]any{"pod_name": pod.Name, "pod_uid": string(pod.UID), "node_name": c.Node, "architecture": "arm64", "uid": uid}, &grant)
	if status == http.StatusTooEarly && ctx.Err() == nil {
		return nil
	}
	if err != nil {
		return map[string]any{"error": "unavailable", "reason": "denied"}
	}
	task := cachevolumes.CheckoutTask{
		Scope: grant.Scope, Generation: grant.Generation, CloneURL: grant.CloneURL, DefaultBranch: grant.DefaultBranch,
		Commit: grant.Commit, DefaultBranchJob: grant.DefaultBranchJob, MayStartMaster: grant.MayStartMaster, Use: grant.ID, VolumeKey: grant.VolumeKey, UID: grant.UID,
		BaseGeneration: grant.BaseGeneration, ImageDigest: grant.ImageDigest, ContentDigest: grant.ContentDigest,
	}
	// The job's branch is a clone of this host's master; the HEAD only restores it.
	identity := grant.Identity
	identity.Kind, identity.CanPublish = cachevolumes.KindCheckout, false
	identity.ParentID, identity.BaseGeneration, identity.ImageDigest, identity.ContentDigest = "", 0, "", ""
	c.rememberCheckout(string(pod.UID), task)
	c.Checkouts.Track(task)
	if c.Checkouts.Master(grant.Scope, grant.Generation) == "" {
		if task.BaseGeneration > 0 {
			c.Checkouts.Enqueue(task)
		}
		// No branch can exist, so nothing is admitted or journaled: the use ends now.
		c.endUse(ctx, grant.ID)
		return map[string]any{"error": "unavailable", "reason": "cold"}
	}
	warm, err := c.Store.Acquire(ctx, identity, pod.Name, string(pod.UID))
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return map[string]any{"error": "unavailable", "reason": "timeout"}
	case errors.Is(err, cachevolumes.ErrCapacity):
		return map[string]any{"error": "unavailable", "reason": "capacity"}
	case err != nil:
		return map[string]any{"error": "unavailable", "reason": "error"}
	}
	return map[string]any{"id": grant.ID, "directory": grant.Scope, "warm": warm}
}

// endUse reports a use that never got a branch as deleted, as reconcile does for
// a branch it removed.
func (c *CustomVolumes) endUse(ctx context.Context, id string) {
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
	defer cancel()
	_, _ = c.request(ctx, "report", map[string]any{"id": id, "node_name": c.Node, "state": "deleted", "gone": true, "warm": false, "size_bytes": 0, "capacity_bytes": 0, "attach_ms": nil}, &struct{}{})
}

func (c *CustomVolumes) rememberCheckout(podUID string, task cachevolumes.CheckoutTask) {
	c.checkoutMu.Lock()
	defer c.checkoutMu.Unlock()
	if c.checkoutJobs == nil {
		c.checkoutJobs = map[string]cachevolumes.CheckoutTask{}
	}
	c.checkoutJobs[podUID] = task
}

// collectCheckout moves a finished job's export out of its share before the share
// is removed, and queues a build from it. The guest wrote the export, so only a
// real directory is taken, never a link out of the share.
func (c *CustomVolumes) collectCheckout(podUID string) {
	c.checkoutMu.Lock()
	task, ok := c.checkoutJobs[podUID]
	delete(c.checkoutJobs, podUID)
	c.checkoutMu.Unlock()
	if !ok || !c.Checkouts.Ready() {
		return
	}
	src := filepath.Join(c.Root, "pods", podUID, cachevolumes.CheckoutExportDir)
	if info, err := os.Lstat(src); err != nil || !info.IsDir() {
		return
	}
	dst := c.Checkouts.Incoming(podUID)
	if err := os.MkdirAll(filepath.Dir(dst), 0700); err != nil {
		return
	}
	_ = os.RemoveAll(dst)
	if err := os.Rename(src, dst); err != nil {
		return
	}
	task.Export = dst
	c.Checkouts.Enqueue(task)
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
	// Evict only when it can make the room: a refused build retries every reconcile.
	if free < bytes && free+c.Checkouts.Evictable(c.Space.backend.allocatedBytes) >= bytes {
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
		c.Space.mu.Lock()
		defer c.Space.mu.Unlock()
		c.checkoutReserved -= bytes
	}, nil
}
