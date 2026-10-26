package podagent

import (
	"context"
	"errors"
	"sort"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// upcomingImagesLabel marks the ConfigMap a runner image release writes into
// each cluster before a deploy moves the RunnerPools to its images
// (`.github/workflows/runner-image-release.yml`). Its keys are
// `<xcode>.<variant>` and its values the image a pool of that Xcode and
// variant will run.
const upcomingImagesLabel = "tuist.dev/upcoming-runner-images"

// xcodeVersionLabel and runnerImageVariantLabel are the RunnerPool labels the
// chart renders on a pool that follows the catalog's image for its Xcode:
// `standalone` or `stacked`. A pool that pins its own image has no variant.
const (
	xcodeVersionLabel       = "tuist.dev/xcode-version"
	runnerImageVariantLabel = "tuist.dev/runner-image-variant"
)

// runnerPoolOwnerLabel is the account the Tuist server stamps on a runner Pod
// when the Pod claims a job.
const runnerPoolOwnerLabel = "tuist.dev/runner-pool-owner"

// stageJobWaitCap bounds how long staging waits for the host's jobs to
// finish before it pulls beside them, so a host that is never without a job
// does not hold a release until the staging gate gives up on it.
const stageJobWaitCap = 20 * time.Minute

// upcomingImages maps `<xcode>.<variant>` to the image the next release gives
// pools of that Xcode and variant.
type upcomingImages map[string]string

func listUpcomingImages(ctx context.Context, k8s client.Reader) (upcomingImages, error) {
	list := &corev1.ConfigMapList{}
	if err := k8s.List(ctx, list, client.MatchingLabels{upcomingImagesLabel: "true"}); err != nil {
		return nil, err
	}
	out := upcomingImages{}
	for _, cm := range list.Items {
		for key, image := range cm.Data {
			out[key] = image
		}
	}
	return out, nil
}

// forPool returns the image pool moves to next, or "" when it stays on its
// image, pins its own or would leave its repository.
func (u upcomingImages) forPool(pool runnerPoolSpec) string {
	xcode := pool.Metadata.Labels[xcodeVersionLabel]
	variant := pool.Metadata.Labels[runnerImageVariantLabel]
	if xcode == "" || variant == "" {
		return ""
	}
	image := u[xcode+"."+variant]
	if image == "" || image == pool.Spec.Image || ociRepository(image) != ociRepository(pool.Spec.Image) {
		return ""
	}
	return image
}

func (p *Prewarmer) stageEvery(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		p.stage(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// stage materializes, one at a time, the image each pool this host serves
// moves to next, so the deploy that moves the pool finds it here and holds
// the pool until it does (.github/scripts/runner-image-staging-gate.sh). A Pod
// of a new image otherwise pays the pull on each host its pool lands on.
// After a pool moves, the GC follows it (follow.go).
//
// Staging stays out of the jobs' way. It starts no pull while a Pod waits on
// one, since the host runs one golden pull at a time, nor while a runner on
// the host is running a job, for up to stageJobWaitCap. Its pulls run at
// background priority (tart.InBackground). It stops below
// prewarmMinFreePercent, and an image the rack's image cache is still
// fetching is asked for again on the next pass.
func (p *Prewarmer) stage(ctx context.Context) {
	logger := log.FromContext(ctx).WithName("stage")

	pools, err := listRunnerPools(ctx, p.K8s)
	if err != nil {
		logger.Error(err, "list runner pools; not staging runner images")
		return
	}
	upcoming, err := listUpcomingImages(ctx, p.K8s)
	if err != nil {
		logger.Error(err, "list upcoming runner images; not staging runner images")
		return
	}
	held, err := p.Goldens.heldGoldens(ctx)
	if err != nil {
		logger.Error(err, "list this host's golden bases; not staging runner images")
		return
	}

	images := p.stageImages(pools, upcoming, held)
	if len(images) == 0 {
		p.jobsDeferredSince = time.Time{}
		return
	}
	for _, image := range images {
		if ctx.Err() != nil {
			return
		}
		if p.Goldens.podsAwaitGolden() {
			logger.Info("deferring runner image staging to a Pod's golden pull", "image", image)
			return
		}
		if p.deferForJobs(ctx) {
			logger.Info("deferring runner image staging until this host's jobs finish", "image", image, "since", p.jobsDeferredSince, "capSeconds", stageJobWaitCap.Seconds())
			return
		}
		if free, err := p.DiskFree(); err != nil || free < prewarmMinFreePercent {
			logger.Info("not staging runner images on disk space", "freePercent", free, "floorPercent", prewarmMinFreePercent, "error", err, "image", image)
			return
		}
		started := time.Now()
		name, materialized, err := p.Goldens.ensureGolden(tart.InBackground(ctx), image)
		switch {
		case errors.Is(err, errMirrorSyncing):
			recordGoldenStaged("syncing")
			logger.Info("the rack image cache is still fetching a runner image to stage", "image", image)
		case err != nil:
			recordGoldenStaged("error")
			logger.Error(err, "stage runner image", "image", image)
		default:
			result := "present"
			if materialized {
				result = "pulled"
			}
			recordGoldenStaged(result)
			logger.Info("staged runner image", "image", image, "golden", name, "pulled", materialized, "duration", time.Since(started).String())
		}
	}
}

// deferForJobs reports whether staging waits for the host's jobs: true while
// a runner on the host runs a job, until stageJobWaitCap after staging first
// waited for them. A Pod list that fails counts as a running job.
func (p *Prewarmer) deferForJobs(ctx context.Context) bool {
	busy, err := p.runsJob(ctx)
	if err != nil {
		log.FromContext(ctx).WithName("stage").Error(err, "list this host's runner Pods; treating a job as running")
		busy = true
	}
	if !busy {
		p.jobsDeferredSince = time.Time{}
		return false
	}
	now := p.clock()
	if p.jobsDeferredSince.IsZero() {
		p.jobsDeferredSince = now
	}
	return now.Sub(p.jobsDeferredSince) < stageJobWaitCap
}

// runsJob reports whether a runner Pod on this host has claimed a job: the
// server stamped its owner, or its guest reports `claimed`. An idle warm
// runner has neither.
func (p *Prewarmer) runsJob(ctx context.Context) (bool, error) {
	pods := &corev1.PodList{}
	if err := p.K8s.List(ctx, pods, client.MatchingFields{"spec.nodeName": p.NodeName}); err != nil {
		return false, err
	}
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.DeletionTimestamp != nil {
			continue
		}
		if pod.Labels[runnerPoolOwnerLabel] != "" || pod.Annotations[runnerHeartbeatStateAnnotation] == heartbeatStateClaimed {
			return true, nil
		}
	}
	return false, nil
}

func (p *Prewarmer) clock() time.Time {
	if p.Now != nil {
		return p.Now()
	}
	return time.Now()
}

// stageImages returns the images to stage, given the goldens the host holds:
// the next image of each pool of the fleet whose current image the host holds,
// when it lacks the next one. Warm floors go first, then demand, as for
// prewarming.
func (p *Prewarmer) stageImages(pools []runnerPoolSpec, upcoming upcomingImages, held map[string]struct{}) []string {
	type candidate struct {
		image    string
		floor    int32
		replicas int32
	}
	best := map[string]candidate{}
	for _, pool := range pools {
		if !pool.runsOn(p.Fleet) {
			continue
		}
		if _, serves := held[goldenVMName(pool.Spec.Image)]; !serves {
			continue
		}
		next := upcoming.forPool(pool)
		if next == "" {
			continue
		}
		if _, ok := held[goldenVMName(next)]; ok {
			continue
		}
		c := best[next]
		c.image = next
		c.floor += pool.warmFloor()
		c.replicas += pool.Spec.Replicas
		best[next] = c
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

// heldGoldens names the golden bases on this host's disk.
func (r *Reconciler) heldGoldens(ctx context.Context) (map[string]struct{}, error) {
	vms, err := r.Tart.List(ctx)
	if err != nil {
		return nil, err
	}
	held := map[string]struct{}{}
	for _, vm := range vms {
		if vm.Source == "local" && isGoldenVMName(vm.Name) {
			held[vm.Name] = struct{}{}
		}
	}
	return held, nil
}

// podsAwaitGolden reports whether a Pod on this host waits on a golden pull.
func (r *Reconciler) podsAwaitGolden() bool {
	r.goldenMu.Lock()
	defer r.goldenMu.Unlock()
	return len(r.goldenWaiters) > 0
}
