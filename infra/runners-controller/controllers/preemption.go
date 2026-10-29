package controllers

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

// Cross-pool preemption: when a pool's queued jobs cannot be placed because
// its fleet is full, sibling pools on that fleet give up idle warm runners the
// allocator has already taken from them, without waiting out their scale-down
// cooldown. The autoscaler picks and marks the runners and lowers the
// victim's replicas; the RunnerPool reconciler retires marked runners first.
const (
	preemptedForAnnotation = "tuist.dev/preempted-for"
	preemptedAtAnnotation  = "tuist.dev/preempted-at"

	// preemptionWait is how long the scheduler must have refused a Pod for
	// lack of resources before its pool counts as starved.
	preemptionWait = 30 * time.Second

	// preemptionGrace is how long an idle runner must have been warm before
	// it can be preempted.
	preemptionGrace = 2 * time.Minute

	// preemptionSettle is how long a marked or deleting Pod counts as a seat
	// already on its way back to the fleet.
	preemptionSettle = 2 * time.Minute
)

// preemptionPool is one pool's share of the planner's input.
type preemptionPool struct {
	name      string
	cost      int64
	queued    int32
	allocated int32
	// replicas is the size a cut is taken from: the smaller of spec.replicas
	// and the pool's alive Pods.
	replicas int32

	// rejected counts alive Pods the scheduler refused for capacity for at
	// least preemptionWait.
	rejected int32
	// idleBound counts alive, bound, unclaimed Pods, warm or still booting.
	idleBound int32
	// freeing is how many seats the pool holds above spec.replicas, counting
	// recently deleted Pods still on their node. Those seats return to the
	// fleet; a seat whose Pod the pool is replacing does not.
	freeing int32
	// preemptible are warm idle Pods past preemptionGrace, oldest warm first.
	preemptible []*corev1.Pod
	// unboundIdle are unclaimed Pods with no node yet.
	unboundIdle []*corev1.Pod
}

// starvedNeed is how many of the pool's queued jobs wait on a Pod the
// scheduler cannot place. Idle bound Pods will claim queued jobs on their own,
// so they are subtracted first.
func (p *preemptionPool) starvedNeed() int32 {
	unserved := p.queued - p.idleBound
	if unserved <= 0 {
		return 0
	}
	if p.rejected < unserved {
		return p.rejected
	}
	return unserved
}

func (p *preemptionPool) surplus() int32 {
	return p.replicas - p.allocated
}

// planPreemption returns the Pods `poolName` gives up this tick and the
// starved pools they are given up for.
//
// The starved demand is measured in the allocator's unit (per-Pod cost) and
// reduced by seats already being released. Victims are pools above their
// allocation that are not starved themselves; they give up warm idle Pods one
// per pool per round, in name order, so every reconcile computes the same
// split. A victim never drops below its allocation. A victim also drops its
// unbound idle Pods within its surplus, since those would otherwise race the
// starved Pods for the seats being freed.
func planPreemption(poolName string, pools []*preemptionPool) ([]*corev1.Pod, []string) {
	sorted := append([]*preemptionPool(nil), pools...)
	sort.Slice(sorted, func(a, b int) bool { return sorted[a].name < sorted[b].name })

	var demand int64
	var starved []string
	for _, p := range sorted {
		if need := p.starvedNeed(); need > 0 {
			demand += int64(need) * p.cost
			starved = append(starved, p.name)
		}
	}
	if len(starved) == 0 {
		return nil, nil
	}
	for _, p := range sorted {
		demand -= int64(p.freeing) * p.cost
	}

	var victims []*preemptionPool
	limits := map[string]int{}
	for _, p := range sorted {
		if p.starvedNeed() > 0 || p.surplus() <= 0 || p.cost <= 0 {
			continue
		}
		limit := int(p.surplus())
		if len(p.preemptible) < limit {
			limit = len(p.preemptible)
		}
		victims = append(victims, p)
		limits[p.name] = limit
	}

	taken := map[string]int{}
	for demand > 0 {
		progressed := false
		for _, v := range victims {
			if demand <= 0 {
				break
			}
			if taken[v.name] < limits[v.name] {
				taken[v.name]++
				demand -= v.cost
				progressed = true
			}
		}
		if !progressed {
			break
		}
	}

	for _, v := range victims {
		if v.name != poolName {
			continue
		}
		chosen := append([]*corev1.Pod(nil), v.preemptible[:taken[v.name]]...)
		remaining := int(v.surplus()) - len(chosen)
		for i := 0; i < remaining && i < len(v.unboundIdle); i++ {
			chosen = append(chosen, v.unboundIdle[i])
		}
		if len(chosen) == 0 {
			return nil, nil
		}
		return chosen, starved
	}
	return nil, nil
}

// classifyForPreemption folds one pool's Pods into the planner's input.
func classifyForPreemption(member fleetMember, replicas int32, pods []corev1.Pod, now time.Time) *preemptionPool {
	p := &preemptionPool{
		name:      member.pool.Name,
		cost:      member.cost,
		queued:    member.queued,
		allocated: member.allocated,
	}

	var alive, seated int32
	var marked []*corev1.Pod
	for i := range pods {
		pod := &pods[i]
		bound := pod.Spec.NodeName != ""

		if !isAlive(pod) {
			if bound && !pod.DeletionTimestamp.IsZero() && now.Sub(pod.DeletionTimestamp.Time) < preemptionSettle {
				seated++
			}
			continue
		}
		alive++
		if bound {
			seated++
		}

		if !bound {
			if rejectedForCapacity(pod, now) {
				p.rejected++
			}
			if isIdle(pod) && !isStaleRunner(pod, member.pool) {
				p.unboundIdle = append(p.unboundIdle, pod)
			}
			continue
		}

		if !isIdle(pod) {
			continue
		}
		p.idleBound++
		if isStaleRunner(pod, member.pool) || !isWarmCapacity(pod, member.pool) {
			continue
		}
		since, ok := warmSince(pod)
		if !ok || now.Sub(since) < preemptionGrace {
			continue
		}
		if _, isMarked := preemptionMark(pod, now); isMarked {
			marked = append(marked, pod)
			continue
		}
		p.preemptible = append(p.preemptible, pod)
	}

	p.replicas = replicas
	if alive < replicas {
		p.replicas = alive
	}
	if released := seated - replicas; released > 0 {
		p.freeing = released
	}
	// A marked runner above spec.replicas is already on its way out. One the
	// pool is keeping (its reap lost a race) can be chosen again.
	if alive <= replicas {
		p.preemptible = append(p.preemptible, marked...)
	}

	sort.SliceStable(p.preemptible, func(a, b int) bool {
		sa, _ := warmSince(p.preemptible[a])
		sb, _ := warmSince(p.preemptible[b])
		if !sa.Equal(sb) {
			return sa.Before(sb)
		}
		return p.preemptible[a].Name < p.preemptible[b].Name
	})
	sort.SliceStable(p.unboundIdle, func(a, b int) bool {
		return p.unboundIdle[a].Name < p.unboundIdle[b].Name
	})
	return p
}

// preemptForStarvedSiblings retires `pool`'s share of idle runners for
// siblings whose queued jobs cannot be placed. It reports whether it lowered
// the pool's replicas.
func (r *AutoscalerReconciler) preemptForStarvedSiblings(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	fleet *fleetAllocation,
	now time.Time,
	logger logr.Logger,
) (bool, error) {
	if fleet == nil {
		return false, nil
	}
	if _, ok := fleet.members[pool.Name]; !ok {
		return false, nil
	}

	var pods corev1.PodList
	if err := r.List(ctx, &pods, client.InNamespace(pool.Namespace), client.HasLabels{"tuist.dev/runner-pool"}); err != nil {
		return false, fmt.Errorf("list runner pods: %w", err)
	}
	byPool := map[string][]corev1.Pod{}
	for i := range pods.Items {
		name := pods.Items[i].Labels["tuist.dev/runner-pool"]
		if _, ok := fleet.members[name]; ok {
			byPool[name] = append(byPool[name], pods.Items[i])
		}
	}

	inputs := make([]*preemptionPool, 0, len(fleet.members))
	var mine *preemptionPool
	for name, member := range fleet.members {
		replicas := member.pool.Spec.Replicas
		if name == pool.Name {
			replicas = pool.Spec.Replicas
		}
		input := classifyForPreemption(member, replicas, byPool[name], now)
		if name == pool.Name {
			mine = input
		}
		inputs = append(inputs, input)
	}

	warm, err := r.nodesHoldingStarvedImages(ctx, pool, fleet, inputs)
	if err != nil {
		return false, err
	}
	mine.preemptible = preferPodsOnNodes(mine.preemptible, warm)

	chosen, starved := planPreemption(pool.Name, inputs)
	if len(chosen) == 0 {
		return false, nil
	}

	forPools := strings.Join(starved, ",")
	stamp := now.UTC().Format(time.RFC3339)
	for _, pod := range chosen {
		patch := client.MergeFrom(pod.DeepCopy())
		if pod.Annotations == nil {
			pod.Annotations = map[string]string{}
		}
		pod.Annotations[preemptedForAnnotation] = forPools
		pod.Annotations[preemptedAtAnnotation] = stamp
		if err := r.Patch(ctx, pod, patch); err != nil && !apierrors.IsNotFound(err) {
			return false, fmt.Errorf("mark pod %s for preemption: %w", pod.Name, err)
		}
	}

	current := pool.Spec.Replicas
	target := mine.replicas - int32(len(chosen))
	if err := r.applyReplicas(ctx, pool, target); err != nil {
		return false, fmt.Errorf("lower replicas for preemption: %w", err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(pool), pool); err != nil {
		return true, fmt.Errorf("get pool after preemption patch: %w", err)
	}
	ts := metav1.NewTime(now)
	pool.Status.LastScaleDownAt = &ts
	if err := r.Status().Update(ctx, pool); err != nil && !apierrors.IsConflict(err) && !apierrors.IsNotFound(err) {
		return true, fmt.Errorf("stamp lastScaleDownAt: %w", err)
	}

	logger.Info("preempting idle runners for starved siblings",
		"from", current, "to", target, "pods", len(chosen), "for", forPools)
	return true, nil
}

// nodesHoldingStarvedImages returns the fleet's hosts that already hold the
// golden image of a starved pool. A starved Pod takes whichever seat frees,
// so freeing one of these lets its job clone the image instead of pulling it.
func (r *AutoscalerReconciler) nodesHoldingStarvedImages(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	fleet *fleetAllocation,
	inputs []*preemptionPool,
) (map[string]bool, error) {
	var keys []string
	for _, input := range inputs {
		if input.starvedNeed() <= 0 {
			continue
		}
		if image := fleet.members[input.name].pool.Spec.Image; image != "" {
			keys = append(keys, podtemplate.GoldenNodeAffinityKey(image))
		}
	}
	if len(keys) == 0 {
		return nil, nil
	}

	var nodes corev1.NodeList
	if err := r.List(ctx, &nodes, fleetNodeSelector(pool)); err != nil {
		return nil, fmt.Errorf("list fleet nodes: %w", err)
	}
	warm := map[string]bool{}
	for i := range nodes.Items {
		for _, key := range keys {
			if _, ok := nodes.Items[i].Labels[key]; ok {
				warm[nodes.Items[i].Name] = true
				break
			}
		}
	}
	return warm, nil
}

// preferPodsOnNodes moves the Pods bound to `nodes` ahead of the rest,
// keeping the order within each group.
func preferPodsOnNodes(pods []*corev1.Pod, nodes map[string]bool) []*corev1.Pod {
	if len(nodes) == 0 {
		return pods
	}
	sorted := append([]*corev1.Pod(nil), pods...)
	sort.SliceStable(sorted, func(a, b int) bool {
		return nodes[sorted[a].Spec.NodeName] && !nodes[sorted[b].Spec.NodeName]
	})
	return sorted
}

// rejectedForCapacity reports whether the scheduler has refused a Pod for
// insufficient resources for at least preemptionWait. Refusals for any other
// reason (taints, selectors) cannot be fixed by freeing a seat.
func rejectedForCapacity(pod *corev1.Pod, now time.Time) bool {
	since, ok := unschedulableSince(pod)
	if !ok || now.Sub(since) < preemptionWait {
		return false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodScheduled {
			return strings.Contains(condition.Message, "Insufficient")
		}
	}
	return false
}

// warmSince is when an idle runner started polling for work: the Linux
// poller init container's start, or the macOS guest VM's start.
func warmSince(pod *corev1.Pod) (time.Time, bool) {
	for _, cs := range pod.Status.InitContainerStatuses {
		if cs.Name == "poller" {
			if cs.State.Running == nil {
				return time.Time{}, false
			}
			return cs.State.Running.StartedAt.Time, true
		}
	}
	for _, cs := range pod.Status.ContainerStatuses {
		if cs.State.Running != nil && !cs.State.Running.StartedAt.IsZero() {
			return cs.State.Running.StartedAt.Time, true
		}
	}
	return time.Time{}, false
}

// preemptionMark returns the pools a Pod was preempted for, if it was marked
// within preemptionSettle.
func preemptionMark(pod *corev1.Pod, now time.Time) (string, bool) {
	at, err := time.Parse(time.RFC3339, pod.Annotations[preemptedAtAnnotation])
	if err != nil {
		return "", false
	}
	if now.Sub(at) >= preemptionSettle {
		return "", false
	}
	return pod.Annotations[preemptedForAnnotation], true
}
