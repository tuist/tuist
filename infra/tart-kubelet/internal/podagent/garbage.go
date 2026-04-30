// Garbage collection for Tart-managed disk. Lives in podagent so it
// shares the Pod ↔ VM name mapping with the reconciler.
//
// Without this, the host fills with leftover clones from terminated
// Pods + tag-superseded OCI images and `tart pull` eventually fails
// with "The file couldn't be saved because there isn't enough
// space.", which the reconciler can't recover from on its own.
//
// Two entry points:
//   - `Start` is a controller-runtime Runnable that fires every
//     `Interval` to drop orphan local VMs and stale OCI cache entries.
//   - `RunOnce` is invoked synchronously by the reconciler when a
//     Pull errors with a no-space signature, before retrying.
//
// "Backed by a Pod" = the VM's name matches `VMNameForPod` of some
// Pod scheduled to this Node OR the OCI cache entry matches some
// Pod's container image.
package podagent

import (
	"context"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Collector is a controller-runtime Runnable that periodically
// reclaims Tart-managed disk on the local Mac mini.
type Collector struct {
	K8s      client.Reader
	Tart     *tart.Client
	NodeName string
	Interval time.Duration

	mu sync.Mutex
}

// Start blocks until ctx is cancelled. Conforms to manager.Runnable.
func (c *Collector) Start(ctx context.Context) error {
	c.RunOnce(ctx)
	t := time.NewTicker(c.Interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			c.RunOnce(ctx)
		}
	}
}

// RunOnce performs a single GC pass. Safe to call concurrently with
// itself (mutex serializes). Logs but doesn't return errors — there's
// nothing the caller can usefully do with them.
func (c *Collector) RunOnce(ctx context.Context) {
	c.mu.Lock()
	defer c.mu.Unlock()

	logger := log.FromContext(ctx).WithName("gc")

	expected, err := c.expectedSet(ctx)
	if err != nil {
		logger.Error(err, "list pods scheduled to this node")
		return
	}

	vms, err := c.Tart.List(ctx)
	if err != nil {
		logger.Error(err, "list tart entries")
		return
	}

	var droppedClones, droppedImages int
	for _, vm := range vms {
		switch vm.Source {
		case "local":
			if _, want := expected.vms[vm.Name]; want {
				continue
			}
			if err := c.Tart.Delete(ctx, vm.Name); err != nil {
				logger.Error(err, "delete orphan VM", "name", vm.Name)
				continue
			}
			_ = c.Tart.CleanupVMUserData(vm.Name)
			droppedClones++
		case "OCI":
			if _, want := expected.images[vm.Name]; want {
				continue
			}
			if err := c.Tart.Delete(ctx, vm.Name); err != nil {
				logger.Error(err, "delete stale OCI cache entry", "image", vm.Name)
				continue
			}
			droppedImages++
		}
	}
	if droppedClones > 0 || droppedImages > 0 {
		logger.Info("reclaimed disk", "orphan_clones", droppedClones, "stale_oci_images", droppedImages)
	}
}

// IsNoSpaceError matches the stderr signature Tart returns when a
// pull/clone/run can't write because the disk is full. Stable enough
// across Tart 2.x to gate the disk-pressure GC on.
func IsNoSpaceError(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	return strings.Contains(s, "isn’t enough space") || // curly apostrophe used by Foundation
		strings.Contains(s, "isn't enough space") ||
		strings.Contains(s, "database or disk is full") ||
		strings.Contains(s, "No space left on device")
}

type expectedSet struct {
	vms    map[string]struct{}
	images map[string]struct{}
}

func (c *Collector) expectedSet(ctx context.Context) (*expectedSet, error) {
	pods := &corev1.PodList{}
	if err := c.K8s.List(ctx, pods, client.MatchingFields{"spec.nodeName": c.NodeName}); err != nil {
		return nil, err
	}
	out := &expectedSet{
		vms:    map[string]struct{}{},
		images: map[string]struct{}{},
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		// Pods being deleted are about to release their VMs; let the
		// reconciler's DeletePod handle them. GC stays out of the way.
		if pod.DeletionTimestamp != nil {
			continue
		}
		if len(pod.Spec.Containers) != 1 {
			continue
		}
		out.vms[VMNameForPod(pod)] = struct{}{}
		out.images[pod.Spec.Containers[0].Image] = struct{}{}
	}
	return out, nil
}
