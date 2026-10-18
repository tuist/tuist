package controllers

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

// Sandbox daemons (infra/sandboxd) share the Linux fleet's nodes. Each holds
// a memory carve-out the Tuist server resizes in place: it grows one when
// sandboxes need more than the floor and shrinks it back once they pause.
// The autoscaler keeps that memory out of the fleet's budget, so warm runner
// pools shrink while a carve-out is grown and refill once it shrinks, and it
// retires idle warm runners on a node whose growth the kubelet deferred for
// lack of room. Runners executing a job are never chosen.
const (
	sandboxdLabel           = "tuist.dev/sandboxd"
	sandboxdContainer       = "sandboxd"
	preemptedForSandboxes   = "sandboxes"
	podResizePendingType    = corev1.PodConditionType("PodResizePending")
	podResizeDeferredReason = "Deferred"
)

// sandboxDaemon is one sandboxd Pod as the autoscaler sees it.
type sandboxDaemon struct {
	name string
	node string
	// memory is the larger of what the Pod asks for and what the kubelet
	// has allocated it, which is what the scheduler counts on the node.
	memory int64
	// deferred is how many more bytes a growth the kubelet deferred is
	// waiting for on the node.
	deferred int64
}

// sandboxDaemons lists the bound sandbox daemon Pods. The sandboxes namespace
// is outside the manager's cache, so the read is uncached. A failed read is
// logged and reads as no daemons: the fleet then budgets as it did before
// sandboxes shared it.
func (r *AutoscalerReconciler) sandboxDaemons(ctx context.Context) []sandboxDaemon {
	if r.SandboxesNamespace == "" {
		return nil
	}
	var reader client.Reader = r.Client
	if r.APIReader != nil {
		reader = r.APIReader
	}
	var pods corev1.PodList
	if err := reader.List(ctx, &pods, client.InNamespace(r.SandboxesNamespace), client.MatchingLabels{sandboxdLabel: "true"}); err != nil {
		log.FromContext(ctx).Error(err, "list sandbox daemons; budgeting the fleet without them")
		return nil
	}
	daemons := make([]sandboxDaemon, 0, len(pods.Items))
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName == "" || !isAlive(pod) {
			continue
		}
		asked, allocated := daemonMemory(pod)
		daemon := sandboxDaemon{name: pod.Name, node: pod.Spec.NodeName, memory: max(asked, allocated)}
		if resizeDeferred(pod) && asked > allocated {
			daemon.deferred = asked - allocated
		}
		daemons = append(daemons, daemon)
	}
	return daemons
}

// daemonMemory returns the daemon container's requested memory and what the
// kubelet has allocated it, which trails the request while a resize waits.
func daemonMemory(pod *corev1.Pod) (asked, allocated int64) {
	for _, c := range pod.Spec.Containers {
		if c.Name == sandboxdContainer {
			if q, ok := c.Resources.Requests[corev1.ResourceMemory]; ok {
				asked = q.Value()
			}
		}
	}
	allocated = asked
	for _, cs := range pod.Status.ContainerStatuses {
		if cs.Name != sandboxdContainer {
			continue
		}
		if q, ok := cs.AllocatedResources[corev1.ResourceMemory]; ok {
			allocated = q.Value()
		} else if cs.Resources != nil {
			if q, ok := cs.Resources.Requests[corev1.ResourceMemory]; ok {
				allocated = q.Value()
			}
		}
	}
	return asked, allocated
}

func resizeDeferred(pod *corev1.Pod) bool {
	for _, condition := range pod.Status.Conditions {
		if condition.Type == podResizePendingType && condition.Status == corev1.ConditionTrue && condition.Reason == podResizeDeferredReason {
			return true
		}
	}
	return false
}

// sandboxMemoryOnNodes sums the daemons' memory on the given nodes.
func sandboxMemoryOnNodes(daemons []sandboxDaemon, nodes map[string]bool) int64 {
	var total int64
	for _, d := range daemons {
		if nodes[d.node] {
			total += d.memory
		}
	}
	return total
}

// sandboxCandidate is an idle warm runner that could make room on a node.
type sandboxCandidate struct {
	pod   *corev1.Pod
	pool  string
	since time.Time
}

// planSandboxPreemption chooses, per node with a deferred growth, the idle
// warm runners whose memory covers what the growth still waits for once
// runners already on their way off the node are counted. It is deterministic
// over its inputs, so every pool's reconcile computes the same plan and
// applies only its own part of it.
func planSandboxPreemption(
	deficits map[string]int64,
	freeing map[string]int64,
	candidates map[string][]sandboxCandidate,
) []sandboxCandidate {
	nodes := make([]string, 0, len(deficits))
	for node := range deficits {
		nodes = append(nodes, node)
	}
	sort.Strings(nodes)

	var chosen []sandboxCandidate
	for _, node := range nodes {
		remaining := deficits[node] - freeing[node]
		if remaining <= 0 {
			continue
		}
		pool := append([]sandboxCandidate(nil), candidates[node]...)
		sort.SliceStable(pool, func(a, b int) bool {
			if !pool[a].since.Equal(pool[b].since) {
				return pool[a].since.Before(pool[b].since)
			}
			return pool[a].pod.Name < pool[b].pod.Name
		})
		for _, c := range pool {
			if remaining <= 0 {
				break
			}
			chosen = append(chosen, c)
			remaining -= podMemory(c.pod)
		}
	}
	return chosen
}

// podMemory is what a Pod holds on its node: its containers' memory requests
// plus the RuntimeClass overhead admission added.
func podMemory(pod *corev1.Pod) int64 {
	var total int64
	for _, c := range pod.Spec.Containers {
		if q, ok := c.Resources.Requests[corev1.ResourceMemory]; ok {
			total += q.Value()
		}
	}
	if q, ok := pod.Spec.Overhead[corev1.ResourceMemory]; ok {
		total += q.Value()
	}
	return total
}

// preemptForSandboxGrowth retires `pool`'s share of the idle warm runners on
// nodes where a sandbox daemon's growth waits for room. It reports whether
// it lowered the pool's replicas.
func (r *AutoscalerReconciler) preemptForSandboxGrowth(
	ctx context.Context,
	pool *tuistv1.RunnerPool,
	fleet *fleetAllocation,
	now time.Time,
	logger logr.Logger,
) (bool, error) {
	if r.SandboxesNamespace == "" || pool.Spec.OS != "linux" {
		return false, nil
	}

	var nodes corev1.NodeList
	// The same nodes the fleet's budget counts.
	if err := r.List(ctx, &nodes, client.MatchingLabels{fleetNodePoolLabel: pool.Spec.FleetSelector}); err != nil {
		return false, fmt.Errorf("list fleet nodes: %w", err)
	}
	inFleet := map[string]bool{}
	for i := range nodes.Items {
		inFleet[nodes.Items[i].Name] = true
	}
	deficits := map[string]int64{}
	for _, d := range r.sandboxDaemons(ctx) {
		if d.deferred > 0 && inFleet[d.node] {
			deficits[d.node] += d.deferred
		}
	}
	if len(deficits) == 0 {
		return false, nil
	}

	pools := map[string]*tuistv1.RunnerPool{pool.Name: pool}
	if fleet != nil {
		for name, member := range fleet.members {
			if name != pool.Name {
				pools[name] = member.pool
			}
		}
	}

	var pods corev1.PodList
	if err := r.List(ctx, &pods, client.InNamespace(pool.Namespace), client.HasLabels{"tuist.dev/runner-pool"}); err != nil {
		return false, fmt.Errorf("list runner pods: %w", err)
	}
	retired := r.retiredForSandboxes(now)
	freeing := map[string]int64{}
	for node, runners := range retired {
		for _, runner := range runners {
			freeing[node] += runner.memory
		}
	}
	candidates := map[string][]sandboxCandidate{}
	for i := range pods.Items {
		pod := &pods.Items[i]
		node := pod.Spec.NodeName
		if _, ok := deficits[node]; !ok {
			continue
		}
		if _, remembered := retired[node][pod.UID]; remembered {
			continue
		}
		if !isAlive(pod) {
			if !pod.DeletionTimestamp.IsZero() && now.Sub(pod.DeletionTimestamp.Time) < preemptionSettle {
				freeing[node] += podMemory(pod)
			}
			continue
		}
		if markedFor, marked := preemptionMark(pod, now); marked {
			if markedFor == preemptedForSandboxes {
				freeing[node] += podMemory(pod)
			}
			continue
		}
		owner, ok := pools[pod.Labels["tuist.dev/runner-pool"]]
		if !ok || !isIdle(pod) || isStaleRunner(pod, owner) || !isWarmCapacity(pod, owner) {
			continue
		}
		since, ok := warmSince(pod)
		if !ok || now.Sub(since) < preemptionGrace {
			continue
		}
		candidates[node] = append(candidates[node], sandboxCandidate{pod: pod, pool: owner.Name, since: since})
	}

	var mine []*corev1.Pod
	for _, c := range planSandboxPreemption(deficits, freeing, candidates) {
		if c.pool == pool.Name {
			mine = append(mine, c.pod)
		}
	}
	if len(mine) == 0 {
		return false, nil
	}

	stamp := now.UTC().Format(time.RFC3339)
	for _, pod := range mine {
		patch := client.MergeFrom(pod.DeepCopy())
		if pod.Annotations == nil {
			pod.Annotations = map[string]string{}
		}
		pod.Annotations[preemptedForAnnotation] = preemptedForSandboxes
		pod.Annotations[preemptedAtAnnotation] = stamp
		if err := r.Patch(ctx, pod, patch); err != nil && !apierrors.IsNotFound(err) {
			return false, fmt.Errorf("mark pod %s for a sandbox growth: %w", pod.Name, err)
		}
		r.rememberRetiredForSandboxes(pod, now)
	}

	current := pool.Spec.Replicas
	target := max(current-int32(len(mine)), 0) //nolint:gosec // A pool holds far fewer than 2^31 Pods.
	if err := r.applyReplicas(ctx, pool, target); err != nil {
		return false, fmt.Errorf("lower replicas for a sandbox growth: %w", err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(pool), pool); err != nil {
		return true, fmt.Errorf("get pool after sandbox preemption patch: %w", err)
	}
	ts := metav1.NewTime(now)
	pool.Status.LastScaleDownAt = &ts
	if err := r.Status().Update(ctx, pool); err != nil && !apierrors.IsConflict(err) && !apierrors.IsNotFound(err) {
		return true, fmt.Errorf("stamp lastScaleDownAt: %w", err)
	}

	logger.Info("retiring idle runners for a sandbox carve-out's growth",
		"from", current, "to", target, "pods", len(mine), "nodes", len(deficits))
	return true, nil
}

// retiredRunner is a runner retired for a sandbox growth, remembered after
// it is gone: a retired Pod can leave the API before the kubelet has applied
// the growth it made room for, and without the memory the next tick would
// see the same growth waiting and retire another runner for it.
type retiredRunner struct {
	memory int64
	at     time.Time
}

// retiredForSandboxes returns the runners retired for sandbox growths within
// preemptionSettle, by node, dropping older ones.
func (r *AutoscalerReconciler) retiredForSandboxes(now time.Time) map[string]map[types.UID]retiredRunner {
	r.sandboxMu.Lock()
	defer r.sandboxMu.Unlock()
	out := map[string]map[types.UID]retiredRunner{}
	for node, runners := range r.sandboxRetired {
		for uid, runner := range runners {
			if now.Sub(runner.at) >= preemptionSettle {
				delete(runners, uid)
				continue
			}
			if out[node] == nil {
				out[node] = map[types.UID]retiredRunner{}
			}
			out[node][uid] = runner
		}
		if len(runners) == 0 {
			delete(r.sandboxRetired, node)
		}
	}
	return out
}

func (r *AutoscalerReconciler) rememberRetiredForSandboxes(pod *corev1.Pod, now time.Time) {
	r.sandboxMu.Lock()
	defer r.sandboxMu.Unlock()
	if r.sandboxRetired == nil {
		r.sandboxRetired = map[string]map[types.UID]retiredRunner{}
	}
	if r.sandboxRetired[pod.Spec.NodeName] == nil {
		r.sandboxRetired[pod.Spec.NodeName] = map[types.UID]retiredRunner{}
	}
	r.sandboxRetired[pod.Spec.NodeName][pod.UID] = retiredRunner{memory: podMemory(pod), at: now}
}
