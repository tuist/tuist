package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// runnerPoolListGVK is the runners-controller's RunnerPool list. Read as
// unstructured so tart-kubelet does not depend on that module.
var runnerPoolListGVK = schema.GroupVersionKind{Group: "tuist.dev", Version: "v1alpha1", Kind: "RunnerPoolList"}

// prewarmMinFreePercent is the root-volume free space below which the
// prewarmer starts no further pull: twice the golden reclaim floor, so a
// pre-pull never pushes the host into reclaiming the goldens it just pulled.
// A golden is tens of GB, so pulling every pool's image would fill the disk.
const prewarmMinFreePercent = 2 * defaultGoldenReclaimFreeFloor

// defaultPrewarmTimeout bounds how long a fresh host stays out of scheduling.
// A stalled pull must not keep it out for good; past it, Pods pull on demand.
const defaultPrewarmTimeout = time.Hour

// goldenEnsurer is the Reconciler's golden materialisation, the same path a
// Pod's first VM takes.
type goldenEnsurer interface {
	ensureGolden(ctx context.Context, image string) (name string, materialized bool, err error)
}

var _ goldenEnsurer = (*Reconciler)(nil)

// PrewarmGate is what the Prewarmer needs of the Node's scheduling gate.
type PrewarmGate interface {
	Wait(ctx context.Context) (held bool, err error)
	Release()
}

// Prewarmer materialises the golden bases of the runner pools a freshly
// registered host will serve, before the gate lets Pods onto it. A host that
// was already registered is left alone: it is serving, and golden node
// affinity already steers each pool to hosts that hold its image.
type Prewarmer struct {
	K8s     client.Reader
	Goldens goldenEnsurer
	Gate    PrewarmGate
	// Fleet is this Node's `tuist.dev/fleet` label, which a pool's
	// fleetSelector names. Empty disables prewarming.
	Fleet string
	// DiskFree returns the root volume's free percentage.
	DiskFree func() (float64, error)
	// Timeout overrides defaultPrewarmTimeout.
	Timeout time.Duration
	// SyncRetry is how often an image the rack's image cache is still
	// fetching is asked for again. Zero means defaultPrewarmSyncRetry.
	SyncRetry time.Duration
}

// defaultPrewarmSyncRetry matches the requeue a Pod gets while the image
// cache fetches its image (errMirrorSyncing).
const defaultPrewarmSyncRetry = 30 * time.Second

// Start conforms to manager.Runnable. It never returns an error: a failed
// prewarm only costs the first Pod of each image its pull.
func (p *Prewarmer) Start(ctx context.Context) error {
	logger := log.FromContext(ctx).WithName("prewarm")

	held, err := p.Gate.Wait(ctx)
	if err != nil {
		return nil
	}
	defer p.Gate.Release()
	if !held || p.Fleet == "" {
		return nil
	}

	timeout := p.Timeout
	if timeout <= 0 {
		timeout = defaultPrewarmTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	images, err := p.images(ctx)
	if err != nil {
		logger.Error(err, "list runner pools; taking Pods without prewarming")
		return nil
	}
	logger.Info("prewarming runner images before taking Pods", "fleet", p.Fleet, "images", images)
	for _, image := range images {
		if free, err := p.DiskFree(); err == nil && free < prewarmMinFreePercent {
			logger.Info("stopping prewarm on disk space", "freePercent", free, "floorPercent", prewarmMinFreePercent, "image", image)
			break
		}
		started := time.Now()
		name, materialized, err := p.ensureGolden(ctx, image)
		if err != nil {
			logger.Error(err, "prewarm runner image", "image", image)
			if ctx.Err() != nil {
				break
			}
			continue
		}
		logger.Info("prewarmed runner image", "image", image, "golden", name, "pulled", materialized, "duration", time.Since(started).String())
	}
	return nil
}

func (p *Prewarmer) images(ctx context.Context) ([]string, error) {
	pools, err := listRunnerPools(ctx, p.K8s)
	if err != nil {
		return nil, err
	}
	return prewarmImages(pools, p.Fleet), nil
}

// listRunnerPools reads every RunnerPool as the slice tart-kubelet needs.
func listRunnerPools(ctx context.Context, k8s client.Reader) ([]runnerPoolSpec, error) {
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(runnerPoolListGVK)
	if err := k8s.List(ctx, list); err != nil {
		return nil, err
	}
	pools := make([]runnerPoolSpec, 0, len(list.Items))
	for _, item := range list.Items {
		raw, err := json.Marshal(item.Object)
		if err != nil {
			return nil, fmt.Errorf("encode runner pool %s: %w", item.GetName(), err)
		}
		var pool runnerPoolSpec
		if err := json.Unmarshal(raw, &pool); err != nil {
			return nil, fmt.Errorf("decode runner pool %s: %w", item.GetName(), err)
		}
		pools = append(pools, pool)
	}
	return pools, nil
}

// runnerPoolSpec is the slice of a RunnerPool the prewarmer and the GC read.
type runnerPoolSpec struct {
	Spec struct {
		Image         string `json:"image"`
		OS            string `json:"os"`
		FleetSelector string `json:"fleetSelector"`
		Replicas      int32  `json:"replicas"`
		Autoscaling   *struct {
			Enabled          bool   `json:"enabled"`
			MinWarmPoolFloor *int32 `json:"minWarmPoolFloor"`
		} `json:"autoscaling"`
	} `json:"spec"`
}

// runsOn reports whether the pool runs macOS VMs on fleet's hosts.
func (p runnerPoolSpec) runsOn(fleet string) bool {
	if p.Spec.OS != "" && p.Spec.OS != "darwin" {
		return false
	}
	return p.Spec.FleetSelector == fleet && p.Spec.Image != ""
}

func (p runnerPoolSpec) warmFloor() int32 {
	a := p.Spec.Autoscaling
	if a == nil || !a.Enabled || a.MinWarmPoolFloor == nil {
		return 0
	}
	return *a.MinWarmPoolFloor
}

// prewarmImages returns the images of fleet's macOS pools that keep a warm
// floor or want runners right now (spec.replicas, which the autoscaler sets),
// warm floors first, then by demand. A pool that wants nothing is skipped: its
// image may never run here, and a golden is tens of GB.
func prewarmImages(pools []runnerPoolSpec, fleet string) []string {
	type candidate struct {
		image    string
		floor    int32
		replicas int32
	}
	best := map[string]candidate{}
	for _, pool := range pools {
		if !pool.runsOn(fleet) {
			continue
		}
		c := candidate{image: pool.Spec.Image, floor: pool.warmFloor(), replicas: pool.Spec.Replicas}
		if c.floor <= 0 && c.replicas <= 0 {
			continue
		}
		prev, seen := best[c.image]
		if !seen {
			best[c.image] = c
			continue
		}
		prev.floor += c.floor
		prev.replicas += c.replicas
		best[c.image] = prev
	}

	ordered := make([]candidate, 0, len(best))
	for _, c := range best {
		ordered = append(ordered, c)
	}
	sort.Slice(ordered, func(i, j int) bool {
		a, b := ordered[i], ordered[j]
		if (a.floor > 0) != (b.floor > 0) {
			return a.floor > 0
		}
		if a.replicas != b.replicas {
			return a.replicas > b.replicas
		}
		return a.image < b.image
	})
	images := make([]string, len(ordered))
	for i, c := range ordered {
		images[i] = c.image
	}
	return images
}

// ensureGolden materialises image, asking again while the rack's image cache
// is still fetching it rather than moving on: the host would otherwise take
// Pods without the image, and those Pods would wait on the same fetch. The
// cache's own sync timeout and the prewarm timeout bound the wait.
func (p *Prewarmer) ensureGolden(ctx context.Context, image string) (string, bool, error) {
	retry := p.SyncRetry
	if retry <= 0 {
		retry = defaultPrewarmSyncRetry
	}
	for {
		name, materialized, err := p.Goldens.ensureGolden(ctx, image)
		if !errors.Is(err, errMirrorSyncing) {
			return name, materialized, err
		}
		select {
		case <-ctx.Done():
			return "", false, err
		case <-time.After(retry):
		}
	}
}
