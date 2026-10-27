package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/event"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

func cordonedNode(name string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Spec:       corev1.NodeSpec{Unschedulable: true},
	}
}

func schedulableNode(name string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{
				{Type: corev1.NodeReady, Status: corev1.ConditionTrue},
			},
		},
	}
}

func podOnNode(pod *corev1.Pod, node string) *corev1.Pod {
	pod.Spec.NodeName = node
	return pod
}

// claimedViaPollerExit marks a Pod as having claimed a job through the
// signal that does not depend on the server's best-effort label patch:
// the `poller` init container has exited, so a JIT is staged and the
// runner is about to run (or is running) a customer's job.
func claimedViaPollerExit(pod *corev1.Pod) *corev1.Pod {
	pod.Status.InitContainerStatuses = []corev1.ContainerStatus{{
		Name: "poller",
		State: corev1.ContainerState{
			Terminated: &corev1.ContainerStateTerminated{ExitCode: 0},
		},
	}}
	return pod
}

// TestReconcile_ReapsIdlePodOnCordonedNode is the half of graceful drain
// that makes a drain finish. A cordoned node is one about to be
// replaced; runner Pods there are waited on rather than evicted, so
// nothing else clears the warm pool sitting on that node, and an idle
// poller never completes on its own. The controller has to retire them.
func TestReconcile_ReapsIdlePodOnCordonedNode(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "img", 1)
	idle := podOnNode(newRunnerPod("p-runner-idle", "img", corev1.PodPending, "p"), "node-a")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, cordonedNode("node-a")).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	err := c.Get(context.Background(), nn(idle.Namespace, idle.Name), got)
	if err == nil {
		t.Fatalf("idle Pod on a cordoned node should have been reaped, but it survived")
	}
}

// TestReconcile_KeepsClaimedPodOnCordonedNode is the half that makes a
// drain safe. A Pod running a customer's job must survive the cordon and
// finish, however long that takes.
func TestReconcile_KeepsClaimedPodOnCordonedNode(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "img", 1)
	busy := podOnNode(newRunnerPod("p-runner-busy", "img", corev1.PodRunning, "p"), "node-a")
	busy.Labels["tuist.dev/runner-pool-owner"] = "acme"

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, busy, cordonedNode("node-a")).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), nn(busy.Namespace, busy.Name), got); err != nil {
		t.Fatalf("claimed Pod on a cordoned node must survive the cordon: %v", err)
	}
}

// TestReconcile_KeepsPollerClaimedPodOnCordonedNodeWithoutOwnerLabel is
// the case a PodDisruptionBudget could not express, and the reason this
// reap keys off `isIdle` rather than the label alone.
// `tuist.dev/runner-pool-owner` is best-effort: the server degrades to
// running the job without the label rather than dropping the job when
// the apiserver patch fails. A label-only test would reap a Pod that is
// running a customer's job.
func TestReconcile_KeepsPollerClaimedPodOnCordonedNodeWithoutOwnerLabel(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "img", 1)
	busy := claimedViaPollerExit(
		podOnNode(newRunnerPod("p-runner-unlabeled", "img", corev1.PodPending, "p"), "node-a"),
	)
	delete(busy.Labels, "tuist.dev/runner-pool-owner")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, busy, cordonedNode("node-a")).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), nn(busy.Namespace, busy.Name), got); err != nil {
		t.Fatalf("Pod claimed via poller exit (no owner label) must survive the cordon: %v", err)
	}
}

// TestReconcile_LeavesIdlePodOnSchedulableNodeAlone keeps the reap
// scoped to cordoned nodes. An idle Pod on a healthy node is warm
// capacity and belongs to the scale-down path, not to this one.
func TestReconcile_LeavesIdlePodOnSchedulableNodeAlone(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "img", 1)
	idle := podOnNode(newRunnerPod("p-runner-idle", "img", corev1.PodPending, "p"), "node-a")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, schedulableNode("node-a")).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), nn(idle.Namespace, idle.Name), got); err != nil {
		t.Fatalf("idle Pod on a schedulable node must not be reaped by the cordon path: %v", err)
	}
}

// TestReconcile_UnscheduledIdlePodSurvivesCordonReap guards the nil-node
// case. A Pod with no `spec.nodeName` is not on any node, so it cannot be
// on a cordoned one, and looking up the empty node name must not reap it.
func TestReconcile_UnscheduledIdlePodSurvivesCordonReap(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "img", 1)
	idle := newRunnerPod("p-runner-unscheduled", "img", corev1.PodPending, "p")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, cordonedNode("node-a")).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), nn(idle.Namespace, idle.Name), got); err != nil {
		t.Fatalf("unscheduled idle Pod must not be reaped by the cordon path: %v", err)
	}
}

func powerHeldNode(name string) *corev1.Node {
	node := schedulableNode(name)
	node.Spec.Taints = []corev1.Taint{{Key: powerBudgetTaintKey, Value: "chain", Effect: corev1.TaintEffectNoSchedule}}
	return node
}

// TestReconcile_ReapsIdlePodOnPowerHeldNodeAndKeepsItsJob: a rack mini whose
// chain is over its power budget starts no more jobs. Its idle runner would
// take the next one, so it is retired; the runner already running a job
// finishes.
func TestReconcile_ReapsIdlePodOnPowerHeldNodeAndKeepsItsJob(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("p", "img", 2)
	idle := podOnNode(newRunnerPod("p-runner-idle", "img", corev1.PodPending, "p"), "node-a")
	busy := podOnNode(newRunnerPod("p-runner-busy", "img", corev1.PodRunning, "p"), "node-a")
	busy.Labels["tuist.dev/runner-pool-owner"] = "acme"

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, busy, powerHeldNode("node-a")).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	if err := c.Get(context.Background(), nn(idle.Namespace, idle.Name), &corev1.Pod{}); err == nil {
		t.Fatal("idle Pod on a power-held node survived")
	}
	if err := c.Get(context.Background(), nn(busy.Namespace, busy.Name), &corev1.Pod{}); err != nil {
		t.Fatalf("the job on a power-held node must finish: %v", err)
	}
}

func TestNodeFilterReason_PowerHeldNodeIsNoCapacity(t *testing.T) {
	if reason := nodeFilterReason(powerHeldNode("node-a")); reason != nodeFilteredPowerBudget {
		t.Fatalf("nodeFilterReason = %q, want %q", reason, nodeFilteredPowerBudget)
	}
	if !drainingNodePredicate().Update(event.UpdateEvent{ObjectOld: schedulableNode("node-a"), ObjectNew: powerHeldNode("node-a")}) {
		t.Fatal("a Node newly held by its power budget does not wake the pools")
	}
}

func notReadyNode(name string, since time.Time) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{
				{Type: corev1.NodeReady, Status: corev1.ConditionUnknown, LastTransitionTime: metav1.NewTime(since)},
			},
		},
	}
}

// TestReconcile_ReapsIdlePodOnUnreachableNodeAndKeepsItsJob: every mini of a
// rack site that went dark is NotReady. Its idle runners cannot claim, and
// while they exist the autoscaler counts them as warm capacity, so they are
// retired once the Node has been NotReady past the grace. A runner that
// claimed a job is left alone.
func TestReconcile_ReapsIdlePodOnUnreachableNodeAndKeepsItsJob(t *testing.T) {
	scheme := mustScheme(t)
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	pool := newPool("p", "img", 2)
	idle := podOnNode(newRunnerPod("p-runner-idle", "img", corev1.PodRunning, "p"), "node-a")
	busy := podOnNode(newRunnerPod("p-runner-busy", "img", corev1.PodRunning, "p"), "node-a")
	busy.Labels["tuist.dev/runner-pool-owner"] = "acme"

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, busy, notReadyNode("node-a", now.Add(-nodeUnreachableRetireAfter))).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch", Now: func() time.Time { return now }}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	if err := c.Get(context.Background(), nn(idle.Namespace, idle.Name), &corev1.Pod{}); err == nil {
		t.Fatal("idle Pod on an unreachable node survived")
	}
	if err := c.Get(context.Background(), nn(busy.Namespace, busy.Name), &corev1.Pod{}); err != nil {
		t.Fatalf("the job on an unreachable node must be left alone: %v", err)
	}
}

// TestReconcile_KeepsIdlePodOnBrieflyNotReadyNode: a kubelet restart takes a
// Node NotReady for moments, which must not cost its warm runners.
func TestReconcile_KeepsIdlePodOnBrieflyNotReadyNode(t *testing.T) {
	scheme := mustScheme(t)
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	pool := newPool("p", "img", 1)
	idle := podOnNode(newRunnerPod("p-runner-idle", "img", corev1.PodRunning, "p"), "node-a")

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idle, notReadyNode("node-a", now.Add(-30*time.Second))).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch", Now: func() time.Time { return now }}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: nn(pool.Namespace, pool.Name),
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	if err := c.Get(context.Background(), nn(idle.Namespace, idle.Name), &corev1.Pod{}); err != nil {
		t.Fatalf("idle Pod on a node NotReady for 30s must survive: %v", err)
	}
}

func TestDrainingNodePredicate_NodeGoingNotReadyWakesThePools(t *testing.T) {
	if !drainingNodePredicate().Update(event.UpdateEvent{
		ObjectOld: schedulableNode("node-a"),
		ObjectNew: notReadyNode("node-a", time.Now()),
	}) {
		t.Fatal("a Node going NotReady does not wake the pools")
	}
}

// The reservation, preemption and shape caps reason about the Nodes a pool's
// Pods can land on, so a site-pinned pool's set is its site's Nodes.
func TestFleetNodeSelector_SitePinnedPoolSelectsItsSite(t *testing.T) {
	pool := newPool("p", "img", 1)
	if _, ok := fleetNodeSelector(pool)["node.cluster.x-k8s.io/rack-site"]; ok {
		t.Fatalf("a pool without a site selects a site: %v", fleetNodeSelector(pool))
	}

	pool.Spec.Site = "ber1"
	if got := fleetNodeSelector(pool)["node.cluster.x-k8s.io/rack-site"]; got != "ber1" {
		t.Fatalf("site selector = %q, want ber1", got)
	}
}
