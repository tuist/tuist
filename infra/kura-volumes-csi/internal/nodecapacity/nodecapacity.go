// Package nodecapacity advertises the room a node's volume group has for Kura
// volumes as the tuist.dev/kura-disk extended resource, so the scheduler and
// the server's capacity admission place Kura pods against it the way they
// place them against ephemeral-storage on nodes that keep volumes on /data.
package nodecapacity

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/kubeapi"
)

// Resource is the extended resource Kura pods on a volume group request.
const Resource = "tuist.dev/kura-disk"

// Measure returns the bytes the node's volume group holds for Kura volumes,
// and false when the node has no volume group.
type Measure func(ctx context.Context) (int64, bool, error)

// Patcher applies a JSON merge patch to the node's status.
type Patcher interface {
	PatchNodeStatus(ctx context.Context, node string, patch []byte) error
}

type Advertiser struct {
	Node     string
	Measure  Measure
	Patcher  Patcher
	Interval time.Duration
	Logger   *slog.Logger
}

// Run advertises once and then on every interval, because a kubelet that
// re-registers its node resets status and drops the resource.
func (a *Advertiser) Run(ctx context.Context) {
	ticker := time.NewTicker(a.Interval)
	defer ticker.Stop()
	for {
		if err := a.Once(ctx); err != nil && ctx.Err() == nil {
			a.Logger.Warn("advertising Kura disk capacity failed", "resource", Resource, "error", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// Once sets the resource to the measured capacity, or removes it from a node
// without a volume group so nothing is scheduled there against stale room.
func (a *Advertiser) Once(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	capacity, ok, err := a.Measure(ctx)
	if err != nil {
		return err
	}
	var value any
	if ok {
		value = strconv.FormatInt(capacity, 10)
	}
	patch, err := json.Marshal(map[string]any{"status": map[string]any{"capacity": map[string]any{Resource: value}}})
	if err != nil {
		return err
	}
	return a.Patcher.PatchNodeStatus(ctx, a.Node, patch)
}

// InClusterPatcher talks to the API server with the pod's ServiceAccount.
type InClusterPatcher struct{ api *kubeapi.Client }

func NewInClusterPatcher(api *kubeapi.Client) *InClusterPatcher {
	return &InClusterPatcher{api: api}
}

func (p *InClusterPatcher) PatchNodeStatus(ctx context.Context, node string, patch []byte) error {
	if _, err := p.api.Do(ctx, http.MethodPatch, "/api/v1/nodes/"+node+"/status", "application/merge-patch+json", patch); err != nil {
		return fmt.Errorf("patch node %s status: %w", node, err)
	}
	return nil
}
