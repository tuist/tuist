package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
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
	hasGolden(ctx context.Context, image string) (bool, error)
}

var _ goldenEnsurer = (*Reconciler)(nil)

// PrewarmGate is what the Prewarmer needs of the Node's scheduling gate.
type PrewarmGate interface {
	Wait(ctx context.Context) (held bool, err error)
	Release()
}

// Prewarmer materialises golden bases ahead of the Pods that need them. A
// freshly registered host pulls the images of the runner pools it will serve
// before the gate lets Pods onto it; a host that was already registered is
// serving and skips that. Afterwards, every host downloads the images the
// runners-controller asks it to hold through prewarm annotations on its Node,
// which is how a new runner image reaches a few hosts before pools switch to
// it.
type Prewarmer struct {
	K8s     client.Reader
	Goldens goldenEnsurer
	Gate    PrewarmGate
	// Fleet is this Node's `tuist.dev/fleet` label, which a pool's
	// fleetSelector names. Empty disables the joining host's prewarm.
	Fleet string
	// NodeName is this host's Node, whose prewarm annotations name the
	// images to hold. Empty disables annotation-driven downloads.
	NodeName string
	// DiskFree returns the root volume's free percentage.
	DiskFree func() (float64, error)
	// Timeout overrides defaultPrewarmTimeout, for the joining host's
	// prewarm and for each requested image.
	Timeout time.Duration
	// Interval is how often the Node's prewarm annotations are read. Zero
	// means defaultPrewarmInterval.
	Interval time.Duration
	// SyncRetry is how often an image the rack's image cache is still
	// fetching is asked for again. Zero means defaultPrewarmSyncRetry.
	SyncRetry time.Duration
}

// defaultPrewarmSyncRetry matches the requeue a Pod gets while the image
// cache fetches its image (errMirrorSyncing).
const defaultPrewarmSyncRetry = 30 * time.Second

// defaultPrewarmInterval is how often a host checks which images it was asked
// to hold. Promotion waits on the result, so this only adds to how long a
// release takes to reach new runners, never to a job's wait.
const defaultPrewarmInterval = time.Minute

// prewarmImageAnnotationPrefix namespaces the Node annotations through which
// the runners-controller asks this host to hold an image's golden base. The
// value is the image ref and the suffix is the image hash goldenVMName uses.
//
// CONTRACT: must match the runners-controller's
// `podtemplate.PrewarmImageAnnotationPrefix`.
const prewarmImageAnnotationPrefix = "tuist.dev/prewarm-image-"

// Start conforms to manager.Runnable. It never returns an error: a failed
// prewarm only costs the first Pod of each image its pull.
func (p *Prewarmer) Start(ctx context.Context) error {
	if err := p.prewarmJoiningHost(ctx); err != nil {
		return nil
	}
	if p.NodeName == "" {
		return nil
	}
	interval := p.Interval
	if interval <= 0 {
		interval = defaultPrewarmInterval
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		p.prewarmRequested(ctx)
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

// prewarmJoiningHost pulls the fleet's in-demand images while the gate keeps
// Pods off a host that just registered. It returns an error only when ctx
// ended while waiting on the gate.
func (p *Prewarmer) prewarmJoiningHost(ctx context.Context) error {
	logger := log.FromContext(ctx).WithName("prewarm")

	held, err := p.Gate.Wait(ctx)
	if err != nil {
		return err
	}
	defer p.Gate.Release()
	if !held || p.Fleet == "" {
		return nil
	}

	ctx, cancel := context.WithTimeout(ctx, p.timeout())
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

// prewarmRequested downloads, one at a time, the images this host's Node
// asks it to hold and does not hold yet. A pull stops below the prewarm disk
// floor; the request stays and is retried on a later pass.
func (p *Prewarmer) prewarmRequested(ctx context.Context) {
	logger := log.FromContext(ctx).WithName("prewarm")

	node := &corev1.Node{}
	if err := p.K8s.Get(ctx, client.ObjectKey{Name: p.NodeName}, node); err != nil {
		if !apierrors.IsNotFound(err) {
			logger.Error(err, "read this host's prewarm requests")
		}
		return
	}
	for _, image := range requestedImages(node.Annotations) {
		if ctx.Err() != nil {
			return
		}
		held, err := p.Goldens.hasGolden(ctx, image)
		if err != nil {
			logger.Error(err, "check for a requested image's golden base", "image", image)
			continue
		}
		if held {
			continue
		}
		if free, err := p.DiskFree(); err == nil && free < prewarmMinFreePercent {
			logger.Info("deferring requested image on disk space", "freePercent", free, "floorPercent", prewarmMinFreePercent, "image", image)
			return
		}
		started := time.Now()
		imageCtx, cancel := context.WithTimeout(ctx, p.timeout())
		name, _, err := p.ensureGolden(imageCtx, image)
		cancel()
		if err != nil {
			logger.Error(err, "download requested runner image", "image", image)
			continue
		}
		logger.Info("downloaded requested runner image", "image", image, "golden", name, "duration", time.Since(started).String())
	}
}

func (p *Prewarmer) timeout() time.Duration {
	if p.Timeout > 0 {
		return p.Timeout
	}
	return defaultPrewarmTimeout
}

// requestedImages returns the images named by prewarm annotations whose key
// matches the image they name, sorted.
func requestedImages(annotations map[string]string) []string {
	var images []string
	for key, image := range annotations {
		if !strings.HasPrefix(key, prewarmImageAnnotationPrefix) || image == "" {
			continue
		}
		if key != prewarmImageAnnotationPrefix+strings.TrimPrefix(goldenVMName(image), goldenBaseVMPrefix) {
			continue
		}
		images = append(images, image)
	}
	sort.Strings(images)
	return images
}

func (p *Prewarmer) images(ctx context.Context) ([]string, error) {
	pools, err := listRunnerPools(ctx, p.K8s)
	if err != nil {
		return nil, err
	}
	return prewarmImages(pools, p.Fleet), nil
}

// listRunnerPools reads every RunnerPool as the slice tart-kubelet needs.
func listRunnerPools(ctx context.Context, reader client.Reader) ([]prewarmPool, error) {
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(runnerPoolListGVK)
	if err := reader.List(ctx, list); err != nil {
		return nil, err
	}
	pools := make([]prewarmPool, 0, len(list.Items))
	for _, item := range list.Items {
		raw, err := json.Marshal(item.Object)
		if err != nil {
			return nil, fmt.Errorf("encode runner pool %s: %w", item.GetName(), err)
		}
		var pool prewarmPool
		if err := json.Unmarshal(raw, &pool); err != nil {
			return nil, fmt.Errorf("decode runner pool %s: %w", item.GetName(), err)
		}
		pools = append(pools, pool)
	}
	return pools, nil
}

// prewarmPool is the slice of a RunnerPool tart-kubelet reads.
type prewarmPool struct {
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
	Status struct {
		ServingImage string `json:"servingImage"`
	} `json:"status"`
}

// podImage is the image the pool's Pods run: its serving image once the
// runners-controller has set one, which trails spec.image while a new image
// is staged.
func (p prewarmPool) podImage() string {
	if p.Status.ServingImage != "" {
		return p.Status.ServingImage
	}
	return p.Spec.Image
}

func (p prewarmPool) warmFloor() int32 {
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
func prewarmImages(pools []prewarmPool, fleet string) []string {
	type candidate struct {
		image    string
		floor    int32
		replicas int32
	}
	best := map[string]candidate{}
	for _, pool := range pools {
		if pool.Spec.OS != "" && pool.Spec.OS != "darwin" {
			continue
		}
		if pool.Spec.FleetSelector != fleet || pool.podImage() == "" {
			continue
		}
		c := candidate{image: pool.podImage(), floor: pool.warmFloor(), replicas: pool.Spec.Replicas}
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
