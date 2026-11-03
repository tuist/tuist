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
	"math"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/kubeapi"
)

// Resource is the extended resource Kura pods on a volume group request.
const Resource = "tuist.dev/kura-disk"

// Measure returns the bytes the node's volume group holds for Kura volumes,
// and false when the node has no volume group.
type Measure func(ctx context.Context) (int64, bool, error)

// Patcher reads the node's advertised resource and applies a JSON merge patch
// to its status.
type Patcher interface {
	NodeCapacity(ctx context.Context, node string) (string, bool, error)
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
// re-registers its node resets status and drops the resource. It reads the node
// first and patches only a differing value: every status patch fans out to all
// node watchers, while the value rarely changes.
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
	if current, present, err := a.Patcher.NodeCapacity(ctx, a.Node); err == nil && present == ok {
		if bytes, parsed := parseQuantity(current); !ok || parsed && bytes == capacity {
			return nil
		}
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

func (p *InClusterPatcher) NodeCapacity(ctx context.Context, node string) (string, bool, error) {
	body, err := p.api.Do(ctx, http.MethodGet, "/api/v1/nodes/"+node, "application/json", nil)
	if err != nil {
		return "", false, fmt.Errorf("read node %s: %w", node, err)
	}
	var n struct {
		Status struct {
			Capacity map[string]string `json:"capacity"`
		} `json:"status"`
	}
	if err := json.Unmarshal(body, &n); err != nil {
		return "", false, fmt.Errorf("decode node %s: %w", node, err)
	}
	value, present := n.Status.Capacity[Resource]
	return value, present, nil
}

var quantityPattern = regexp.MustCompile(`^([0-9]+)(Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?$`)

var quantityMultipliers = map[string]int64{
	"": 1, "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "P": 1e15, "E": 1e18,
	"Ki": 1 << 10, "Mi": 1 << 20, "Gi": 1 << 30, "Ti": 1 << 40, "Pi": 1 << 50, "Ei": 1 << 60,
}

// parseQuantity reads the integer forms the API server canonicalizes byte
// quantities to. Anything else reports false, so the caller patches.
func parseQuantity(s string) (int64, bool) {
	m := quantityPattern.FindStringSubmatch(s)
	if m == nil {
		return 0, false
	}
	n, err := strconv.ParseInt(m[1], 10, 64)
	multiplier := quantityMultipliers[m[2]]
	if err != nil || n > math.MaxInt64/multiplier {
		return 0, false
	}
	return n * multiplier, true
}
