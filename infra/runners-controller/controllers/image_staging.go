package controllers

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

const (
	// recentDemandWindow is how long after a pool last wanted runners its
	// image stays on hosts and its next image is staged.
	recentDemandWindow = 7 * 24 * time.Hour

	// imageStagingTimeout bounds how long a pool keeps serving its previous
	// image while hosts download the new one. Past it the pool switches
	// anyway, so a host that cannot download never holds a release back.
	imageStagingTimeout = 2 * time.Hour

	// minStagedHosts is the fewest hosts that hold the image of a pool with
	// recent demand.
	minStagedHosts = 2
)

// stagedHosts is how many hosts should hold the pool's image: none for a
// pool without recent demand, otherwise one more than its warm floor and at
// least minStagedHosts.
func stagedHosts(pool *tuistv1.RunnerPool, now time.Time) int {
	if pool.Spec.OS == "linux" {
		return 0
	}
	floor := 0
	if autoscaling := pool.Spec.Autoscaling; autoscaling != nil && autoscaling.Enabled {
		floor = int(autoscaling.MinWarmPoolFloorOrDefault())
	}
	recent := floor > 0 || pool.Spec.Replicas > 0 ||
		(pool.Status.LastDemandAt != nil && now.Sub(pool.Status.LastDemandAt.Time) < recentDemandWindow)
	if !recent {
		return 0
	}
	return max(floor+1, minStagedHosts)
}

// reconcileImageStaging keeps the fleet's prewarm annotations in line with
// what its pools need and moves this pool to its new image once enough hosts
// hold it. An error leaves the pool on its current image.
func (r *RunnerPoolReconciler) reconcileImageStaging(ctx context.Context, pool *tuistv1.RunnerPool) error {
	if pool.Spec.OS == "linux" || pool.Spec.Image == "" {
		return nil
	}
	now := r.now()

	var pools tuistv1.RunnerPoolList
	if err := r.List(ctx, &pools, client.InNamespace(pool.Namespace)); err != nil {
		return fmt.Errorf("list runner pools: %w", err)
	}
	siblings := make([]*tuistv1.RunnerPool, 0, len(pools.Items))
	for i := range pools.Items {
		sibling := &pools.Items[i]
		if sibling.Name == pool.Name {
			sibling = pool
		}
		if sibling.Spec.OS == "linux" || sibling.Spec.FleetSelector != pool.Spec.FleetSelector || !sibling.DeletionTimestamp.IsZero() {
			continue
		}
		siblings = append(siblings, sibling)
	}

	nodes, err := r.fleetNodes(ctx, pool)
	if err != nil {
		return err
	}
	if err := r.applyPrewarmPlan(ctx, nodes, planImagePrewarm(siblings, nodes, now)); err != nil {
		return err
	}
	return r.promoteImage(ctx, pool, nodes, now)
}

// promoteImage switches the pool to spec.image once min(stagedHosts, healthy
// hosts) of the fleet hold its golden base, or once imageStagingTimeout has
// passed since the controller saw spec.image change. The switch is persisted
// before any Pod is built from it.
func (r *RunnerPoolReconciler) promoteImage(ctx context.Context, pool *tuistv1.RunnerPool, nodes []corev1.Node, now time.Time) error {
	previous := pool.Status.ServingImage
	if previous == pool.Spec.Image {
		return nil
	}

	golden := podtemplate.GoldenNodeAffinityKey(pool.Spec.Image)
	healthy, held := 0, 0
	for i := range nodes {
		if nodeFilterReason(&nodes[i]) != "" {
			continue
		}
		healthy++
		if _, ok := nodes[i].Labels[golden]; ok {
			held++
		}
	}
	want := min(stagedHosts(pool, now), healthy)
	staging := now.Sub(pool.Status.ImageRolledAt.Time)
	if held < want && staging < imageStagingTimeout {
		return nil
	}

	// The patch response replaces the in-memory pool, which would drop the
	// status this reconcile has set but not yet written.
	var status tuistv1.RunnerPoolStatus
	pool.Status.DeepCopyInto(&status)
	status.ServingImage = pool.Spec.Image
	base := pool.DeepCopy()
	pool.Status.ServingImage = pool.Spec.Image
	if err := r.Status().Patch(ctx, pool, client.MergeFrom(base)); err != nil {
		pool.Status.ServingImage = previous
		if apierrors.IsConflict(err) || apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("promote runner image: %w", err)
	}
	pool.Status = status

	reason := fmt.Sprintf("%d of %d healthy hosts hold it", held, healthy)
	if held < want {
		reason = fmt.Sprintf("only %d of the %d hosts it waited for hold it after %s", held, want, imageStagingTimeout)
	}
	log.FromContext(ctx).Info("promoted runner image",
		"pool", pool.Name, "from", previous, "to", pool.Spec.Image,
		"hostsHolding", held, "hostsWanted", want, "staging", staging.Round(time.Second).String())
	if r.Recorder != nil {
		r.Recorder.Eventf(pool, corev1.EventTypeNormal, "RunnerImagePromoted",
			"New runners use %s: %s", pool.Spec.Image, reason)
	}
	return nil
}

// planImagePrewarm returns, per healthy node, the prewarm annotations it
// should carry: for every pool with recent demand, stagedHosts hosts hold its
// serving image and, while it stages one, its spec.image. Pools sharing an
// image share its hosts. Hosts are ranked so assignments stay put: hosts
// already holding the image, then hosts already asked for it, then hosts
// holding the image it replaces, then hosts holding fewer golden bases (a
// proxy for free disk), then by name.
func planImagePrewarm(pools []*tuistv1.RunnerPool, nodes []corev1.Node, now time.Time) map[string]map[string]string {
	type want struct {
		hosts    int
		replaces map[string]struct{}
	}
	wants := map[string]*want{}
	add := func(image string, hosts int, replaces string) {
		w, ok := wants[image]
		if !ok {
			w = &want{replaces: map[string]struct{}{}}
			wants[image] = w
		}
		w.hosts = max(w.hosts, hosts)
		if replaces != "" {
			w.replaces[replaces] = struct{}{}
		}
	}
	for _, pool := range pools {
		hosts := stagedHosts(pool, now)
		if hosts == 0 || pool.Spec.Image == "" {
			continue
		}
		serving := pool.PodImage()
		add(serving, hosts, "")
		if pool.Spec.Image != serving {
			add(pool.Spec.Image, hosts, serving)
		}
	}

	var healthy []*corev1.Node
	for i := range nodes {
		if nodeFilterReason(&nodes[i]) == "" {
			healthy = append(healthy, &nodes[i])
		}
	}
	goldenCount := map[string]int{}
	for _, node := range healthy {
		for key := range node.Labels {
			if podtemplate.IsGoldenNodeLabel(key) {
				goldenCount[node.Name]++
			}
		}
	}

	plan := map[string]map[string]string{}
	for _, node := range healthy {
		plan[node.Name] = map[string]string{}
	}
	images := make([]string, 0, len(wants))
	for image := range wants {
		images = append(images, image)
	}
	sort.Strings(images)
	for _, image := range images {
		w := wants[image]
		golden := podtemplate.GoldenNodeAffinityKey(image)
		annotation := podtemplate.PrewarmImageAnnotationKey(image)
		holdsReplaced := func(node *corev1.Node) bool {
			for replaced := range w.replaces {
				if _, ok := node.Labels[podtemplate.GoldenNodeAffinityKey(replaced)]; ok {
					return true
				}
			}
			return false
		}
		ranked := append([]*corev1.Node(nil), healthy...)
		sort.SliceStable(ranked, func(a, b int) bool {
			na, nb := ranked[a], ranked[b]
			_, heldA := na.Labels[golden]
			_, heldB := nb.Labels[golden]
			if heldA != heldB {
				return heldA
			}
			_, askedA := na.Annotations[annotation]
			_, askedB := nb.Annotations[annotation]
			if askedA != askedB {
				return askedA
			}
			if replacedA, replacedB := holdsReplaced(na), holdsReplaced(nb); replacedA != replacedB {
				return replacedA
			}
			if goldenCount[na.Name] != goldenCount[nb.Name] {
				return goldenCount[na.Name] < goldenCount[nb.Name]
			}
			return na.Name < nb.Name
		})
		for _, node := range ranked[:min(w.hosts, len(ranked))] {
			plan[node.Name][annotation] = image
		}
	}
	return plan
}

// applyPrewarmPlan rewrites the prewarm annotations of every node in plan.
// Nodes outside it (unhealthy ones) keep theirs until they recover. A node
// changed since it was read is left for the next reconcile.
func (r *RunnerPoolReconciler) applyPrewarmPlan(ctx context.Context, nodes []corev1.Node, plan map[string]map[string]string) error {
	for i := range nodes {
		node := &nodes[i]
		desired, planned := plan[node.Name]
		if !planned || prewarmAnnotationsMatch(node.Annotations, desired) {
			continue
		}
		base := node.DeepCopy()
		for key := range node.Annotations {
			if strings.HasPrefix(key, podtemplate.PrewarmImageAnnotationPrefix) {
				delete(node.Annotations, key)
			}
		}
		if len(desired) > 0 && node.Annotations == nil {
			node.Annotations = map[string]string{}
		}
		for key, image := range desired {
			node.Annotations[key] = image
		}
		if err := r.Patch(ctx, node, optimisticPatch(base)); err != nil {
			if apierrors.IsConflict(err) || apierrors.IsNotFound(err) {
				continue
			}
			return fmt.Errorf("patch prewarm annotations on node %s: %w", node.Name, err)
		}
	}
	return nil
}

func prewarmAnnotationsMatch(annotations, desired map[string]string) bool {
	current := 0
	for key, value := range annotations {
		if !strings.HasPrefix(key, podtemplate.PrewarmImageAnnotationPrefix) {
			continue
		}
		current++
		if desired[key] != value {
			return false
		}
	}
	return current == len(desired)
}

// recordDemand stamps status.lastDemandAt while the pool wants runners.
func recordDemand(pool *tuistv1.RunnerPool, now time.Time) {
	if pool.Spec.Replicas > 0 {
		stamp := metav1.NewTime(now)
		pool.Status.LastDemandAt = &stamp
	}
}
