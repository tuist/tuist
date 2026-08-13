package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

// boundProvisioningPod is a Pod the scheduler placed but whose dispatch
// poller never started — the shape a node that cannot create pod cgroups
// produces, and what startTimedOut reaps.
func boundProvisioningPod(name, poolName, nodeName string, scheduledAt time.Time) *corev1.Pod {
	pod := newRunnerPod(name, "img", corev1.PodPending, poolName)
	pod.Spec.NodeName = nodeName
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionTrue,
		LastTransitionTime: metav1.NewTime(scheduledAt),
	}}
	return pod
}

func TestNodeQuarantineHoldsBelowThreshold(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}

	for i := 0; i < nodeQuarantineThreshold-1; i++ {
		if store.recordStartFailure("node-a", now) {
			t.Fatalf("failure %d quarantined node-a before the threshold", i+1)
		}
	}
	if store.isQuarantined("node-a", now) {
		t.Fatal("node-a quarantined below the failure threshold")
	}
}

func TestNodeQuarantineTripsAtThreshold(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}

	var tripped bool
	for i := 0; i < nodeQuarantineThreshold; i++ {
		tripped = store.recordStartFailure("node-a", now)
	}
	if !tripped {
		t.Fatal("threshold failure did not report a new quarantine")
	}
	if !store.isQuarantined("node-a", now) {
		t.Fatal("node-a not quarantined at the failure threshold")
	}
	if got := store.quarantined(now); len(got) != 1 || got[0] != "node-a" {
		t.Fatalf("quarantined() = %v, want [node-a]", got)
	}
}

// A broken node is diagnosed by failures clustered in time. Timeouts
// spread thinly across hours are ordinary noise and must never
// accumulate into a quarantine.
func TestNodeQuarantineForgetsFailuresOlderThanWindow(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}

	for i := 0; i < nodeQuarantineThreshold-1; i++ {
		store.recordStartFailure("node-a", now)
	}
	later := now.Add(nodeQuarantineWindow + time.Second)
	if store.recordStartFailure("node-a", later) {
		t.Fatal("failure quarantined node-a using counts aged out of the window")
	}
	if store.isQuarantined("node-a", later) {
		t.Fatal("node-a quarantined on failures older than the window")
	}
}

// The breaker is half-open: expiry lets a fresh batch land so a
// repaired host rejoins with no operator action.
func TestNodeQuarantineExpiresAfterDuration(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}
	for i := 0; i < nodeQuarantineThreshold; i++ {
		store.recordStartFailure("node-a", now)
	}

	after := now.Add(nodeQuarantineDuration + time.Second)
	if store.isQuarantined("node-a", after) {
		t.Fatal("node-a still quarantined after the quarantine expired")
	}
	if got := store.quarantined(after); len(got) != 0 {
		t.Fatalf("quarantined() = %v, want empty after expiry", got)
	}
}

// A node that is still broken when the probe batch lands must go back
// into quarantine rather than resuming the churn loop.
func TestNodeQuarantineRetripsAfterExpiry(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}
	for i := 0; i < nodeQuarantineThreshold; i++ {
		store.recordStartFailure("node-a", now)
	}

	after := now.Add(nodeQuarantineDuration + time.Second)
	for i := 0; i < nodeQuarantineThreshold; i++ {
		store.recordStartFailure("node-a", after)
	}
	if !store.isQuarantined("node-a", after) {
		t.Fatal("node-a not re-quarantined after failing its probe batch")
	}
}

// Unschedulable Pods carry no node name. Attributing their timeout to
// the empty string would quarantine a node that does not exist.
func TestNodeQuarantineIgnoresUnboundPods(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}

	for i := 0; i < nodeQuarantineThreshold; i++ {
		if store.recordStartFailure("", now) {
			t.Fatal("empty node name produced a quarantine")
		}
	}
	if got := store.quarantined(now); len(got) != 0 {
		t.Fatalf("quarantined() = %v, want empty", got)
	}
}

func TestNodeQuarantineIsolatesNodes(t *testing.T) {
	now := time.Unix(1000, 0)
	store := NodeQuarantine{}
	for i := 0; i < nodeQuarantineThreshold; i++ {
		store.recordStartFailure("node-a", now)
	}
	store.recordStartFailure("node-b", now)

	if store.isQuarantined("node-b", now) {
		t.Fatal("node-b quarantined by node-a's failures")
	}
}

func TestApplyNodeQuarantineNoOpWithoutQuarantine(t *testing.T) {
	pod := &corev1.Pod{}
	applyNodeQuarantine(pod, nil)

	if pod.Spec.Affinity != nil {
		t.Fatalf("affinity = %+v, want nil when nothing is quarantined", pod.Spec.Affinity)
	}
}

func TestApplyNodeQuarantineExcludesNodes(t *testing.T) {
	pod := &corev1.Pod{}
	applyNodeQuarantine(pod, []string{"node-a", "node-b"})

	selector := pod.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution
	if selector == nil || len(selector.NodeSelectorTerms) != 1 {
		t.Fatalf("required node affinity = %+v, want one term", selector)
	}
	expressions := selector.NodeSelectorTerms[0].MatchExpressions
	if len(expressions) != 1 {
		t.Fatalf("match expressions = %+v, want one", expressions)
	}
	if expressions[0].Key != corev1.LabelHostname {
		t.Fatalf("key = %q, want %q", expressions[0].Key, corev1.LabelHostname)
	}
	if expressions[0].Operator != corev1.NodeSelectorOpNotIn {
		t.Fatalf("operator = %q, want NotIn", expressions[0].Operator)
	}
	if len(expressions[0].Values) != 2 ||
		expressions[0].Values[0] != "node-a" || expressions[0].Values[1] != "node-b" {
		t.Fatalf("values = %v, want [node-a node-b]", expressions[0].Values)
	}
}

// The macOS golden-base preference lives on the same Affinity struct.
// Quarantine must add a requirement, not replace the steering.
func TestApplyNodeQuarantinePreservesPreferredAffinity(t *testing.T) {
	preferred := []corev1.PreferredSchedulingTerm{{
		Weight: 100,
		Preference: corev1.NodeSelectorTerm{
			MatchExpressions: []corev1.NodeSelectorRequirement{{
				Key:      "tuist.dev/golden-abc",
				Operator: corev1.NodeSelectorOpExists,
			}},
		},
	}}
	pod := &corev1.Pod{Spec: corev1.PodSpec{Affinity: &corev1.Affinity{
		NodeAffinity: &corev1.NodeAffinity{
			PreferredDuringSchedulingIgnoredDuringExecution: preferred,
		},
	}}}

	applyNodeQuarantine(pod, []string{"node-a"})

	if len(pod.Spec.Affinity.NodeAffinity.PreferredDuringSchedulingIgnoredDuringExecution) != 1 {
		t.Fatal("quarantine dropped the preferred node affinity")
	}
	if pod.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution == nil {
		t.Fatal("quarantine did not add the required node affinity")
	}
}

// summarizeFleetNodes feeds both the healthy-node count that gates
// admission and the filtered-reason gauges. A quarantined node is not
// capacity, so it must not be counted as ready.
func TestSummarizeFleetNodesFiltersQuarantinedNode(t *testing.T) {
	nodes := []corev1.Node{
		*readyLinuxRunnerNode("node-a", "runners-linux"),
		*readyLinuxRunnerNode("node-b", "runners-linux"),
	}

	ready, filtered := summarizeFleetNodes(nodes, map[string]struct{}{"node-a": {}})

	if ready != 1 {
		t.Fatalf("ready = %d, want 1", ready)
	}
	if filtered[nodeFilteredQuarantined] != 1 {
		t.Fatalf("filtered[%s] = %d, want 1", nodeFilteredQuarantined, filtered[nodeFilteredQuarantined])
	}
}

// The incident this breaker exists for: a node that is Ready and free of
// every pressure condition silently fails to start each Pod it accepts.
// Before the breaker, the reaped Pod's replacement landed on the same node
// and the fleet-wide provisioning ceiling stayed saturated by Pods that
// could never run, so every sibling shape was refused admission and the
// queue drained at zero.
func TestReconcileQuarantinesNodeThatNeverStartsPods(t *testing.T) {
	scheme := mustScheme(t)
	now := time.Unix(100000, 0)
	pool := newLinuxKataPool("linux-a", 4, 4)
	badNode := readyLinuxRunnerNode("node-bad", pool.Spec.FleetSelector)
	goodNode := readyLinuxRunnerNode("node-good", pool.Spec.FleetSelector)

	// Scheduled well past the pool's 300s start timeout.
	scheduledAt := now.Add(-10 * time.Minute)
	objects := []client.Object{pool, badNode, goodNode}
	for _, name := range []string{"linux-a-runner-1", "linux-a-runner-2", "linux-a-runner-3"} {
		objects = append(objects, boundProvisioningPod(name, pool.Name, badNode.Name, scheduledAt))
	}

	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(objects...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).Build()
	quarantine := NewNodeQuarantine()
	r := &RunnerPoolReconciler{
		Client:         c,
		Scheme:         scheme,
		DispatchURL:    "http://dispatch",
		NodeQuarantine: quarantine,
		Now:            func() time.Time { return now },
	}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	if !quarantine.isQuarantined(badNode.Name, now) {
		t.Fatal("node-bad not quarantined after three pod-start timeouts")
	}
	if quarantine.isQuarantined(goodNode.Name, now) {
		t.Fatal("node-good quarantined by node-bad's failures")
	}

	var pods corev1.PodList
	if err := c.List(context.Background(), &pods, client.InNamespace(pool.Namespace)); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	replacements := 0
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != "" {
			continue // a survivor of the reap, not a replacement
		}
		replacements++
		affinity := pod.Spec.Affinity
		if affinity == nil || affinity.NodeAffinity == nil ||
			affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution == nil {
			t.Fatalf("replacement %s carries no required node affinity", pod.Name)
		}
		terms := affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution.NodeSelectorTerms
		if len(terms) != 1 || len(terms[0].MatchExpressions) != 1 {
			t.Fatalf("replacement %s affinity = %+v, want one exclusion", pod.Name, terms)
		}
		expression := terms[0].MatchExpressions[0]
		if expression.Operator != corev1.NodeSelectorOpNotIn ||
			len(expression.Values) != 1 || expression.Values[0] != badNode.Name {
			t.Fatalf("replacement %s does not exclude node-bad: %+v", pod.Name, expression)
		}
	}
	if replacements == 0 {
		t.Fatal("reconcile created no replacement Pods to steer away from node-bad")
	}
}

// A single timeout is ordinary noise. Quarantining on it would drain a
// healthy fleet one node at a time.
func TestReconcileKeepsNodeAfterSingleStartTimeout(t *testing.T) {
	scheme := mustScheme(t)
	now := time.Unix(100000, 0)
	pool := newLinuxKataPool("linux-a", 4, 4)
	node := readyLinuxRunnerNode("node-a", pool.Spec.FleetSelector)
	stuck := boundProvisioningPod("linux-a-runner-1", pool.Name, node.Name, now.Add(-10*time.Minute))

	c := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(pool, node, stuck).
		WithStatusSubresource(&tuistv1.RunnerPool{}).Build()
	quarantine := NewNodeQuarantine()
	r := &RunnerPoolReconciler{
		Client:         c,
		Scheme:         scheme,
		DispatchURL:    "http://dispatch",
		NodeQuarantine: quarantine,
		Now:            func() time.Time { return now },
	}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	if quarantine.isQuarantined(node.Name, now) {
		t.Fatal("node-a quarantined on a single start timeout")
	}
}
