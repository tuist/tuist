package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/record"
	"k8s.io/utils/ptr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	ctrlmetrics "sigs.k8s.io/controller-runtime/pkg/metrics"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

const rackFleet = "tuist-tuist-rack-fleet"

var preemptionNow = time.Date(2026, 10, 14, 15, 20, 0, 0, time.UTC)

func plannerPods(prefix string, n int) []*corev1.Pod {
	pods := make([]*corev1.Pod, n)
	for i := range pods {
		pods[i] = &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: fmt.Sprintf("%s-%d", prefix, i)}}
	}
	return pods
}

func TestPlanPreemption(t *testing.T) {
	const slot = 14336

	tests := []struct {
		name        string
		pools       []*preemptionPool
		plan        string
		wantPods    int
		wantStarved []string
	}{
		{
			name: "idle runners above the allocation yield to a starved sibling",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 3, replicas: 7, preemptible: plannerPods("a", 4)},
				{name: "smoke", cost: slot, queued: 4, rejected: 4, allocated: 12, replicas: 12},
			},
			plan:        "macos-27-0",
			wantPods:    4,
			wantStarved: []string{"smoke"},
		},
		{
			name: "never below the allocation",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 6, replicas: 7, preemptible: plannerPods("a", 4)},
				{name: "smoke", cost: slot, queued: 4, rejected: 4, allocated: 12, replicas: 12},
			},
			plan:        "macos-27-0",
			wantPods:    1,
			wantStarved: []string{"smoke"},
		},
		{
			name: "nothing rejected means nothing starved",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 3, replicas: 7, preemptible: plannerPods("a", 4)},
				{name: "smoke", cost: slot, queued: 4, allocated: 12, replicas: 12},
			},
			plan: "macos-27-0",
		},
		{
			name: "rejected Pods without queued work are not starvation",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 3, replicas: 7, preemptible: plannerPods("a", 4)},
				{name: "smoke", cost: slot, queued: 1, rejected: 4, allocated: 12, replicas: 12},
			},
			plan:        "macos-27-0",
			wantPods:    1,
			wantStarved: []string{"smoke"},
		},
		{
			name: "the starved pool's own idle runners serve its queue first",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 3, replicas: 7, preemptible: plannerPods("a", 4)},
				{name: "smoke", cost: slot, queued: 2, idleBound: 2, rejected: 2, allocated: 12, replicas: 12},
			},
			plan: "macos-27-0",
		},
		{
			name: "seats already being released count against the demand",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 3, replicas: 5, freeing: 2, preemptible: plannerPods("a", 2)},
				{name: "smoke", cost: slot, queued: 2, rejected: 2, allocated: 12, replicas: 12},
			},
			plan: "macos-27-0",
		},
		{
			name: "a starved pool is never a victim",
			pools: []*preemptionPool{
				{name: "macos-26-6", cost: slot, queued: 1, rejected: 1, allocated: 1, replicas: 4, preemptible: plannerPods("b", 3)},
				{name: "smoke", cost: slot, queued: 4, rejected: 4, allocated: 12, replicas: 12},
			},
			plan: "macos-26-6",
		},
		{
			name: "a large guest covers two small seats",
			pools: []*preemptionPool{
				{name: "macos-27-0-12vcpu", cost: 2 * slot, allocated: 0, replicas: 2, preemptible: plannerPods("a", 2)},
				{name: "smoke", cost: slot, queued: 2, rejected: 2, allocated: 12, replicas: 12},
			},
			plan:        "macos-27-0-12vcpu",
			wantPods:    1,
			wantStarved: []string{"smoke"},
		},
		{
			name: "a victim drops its unbound idle Pods within its surplus",
			pools: []*preemptionPool{
				{name: "macos-27-0", cost: slot, allocated: 3, replicas: 6, preemptible: plannerPods("a", 1), unboundIdle: plannerPods("u", 4)},
				{name: "smoke", cost: slot, queued: 1, rejected: 1, allocated: 12, replicas: 12},
			},
			plan:        "macos-27-0",
			wantPods:    3,
			wantStarved: []string{"smoke"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pods, starved := planPreemption(tt.plan, tt.pools)
			if len(pods) != tt.wantPods {
				t.Fatalf("preempted %d Pods, want %d", len(pods), tt.wantPods)
			}
			if strings.Join(starved, ",") != strings.Join(tt.wantStarved, ",") {
				t.Fatalf("starved = %v, want %v", starved, tt.wantStarved)
			}
		})
	}
}

// Two victims split one demand by round, so concurrent reconciles of each
// victim agree on who gives what.
func TestPlanPreemption_SplitsDemandAcrossVictims(t *testing.T) {
	pools := []*preemptionPool{
		{name: "macos-26-6", cost: 1, allocated: 1, replicas: 4, preemptible: plannerPods("a", 3)},
		{name: "macos-27-0", cost: 1, allocated: 1, replicas: 4, preemptible: plannerPods("b", 3)},
		{name: "smoke", cost: 1, queued: 3, rejected: 3, allocated: 8, replicas: 8},
	}

	first, _ := planPreemption("macos-26-6", pools)
	second, _ := planPreemption("macos-27-0", pools)
	if len(first) != 2 || len(second) != 1 {
		t.Fatalf("split = %d/%d, want 2/1", len(first), len(second))
	}
}

func darwinRackPool(name string, replicas int32) *tuistv1.RunnerPool {
	pool := macosFleetPool(name, rackFleet, replicas, 0, 18)
	pool.Spec.PodCPUMilli = 6000
	pool.Spec.Autoscaling.ScaleDownCooldownSeconds = ptr.To[int32](300)
	return pool
}

func warmDarwinPod(name, pool, node string, warmFor time.Duration) *corev1.Pod {
	pod := newRunnerPod(name, "ghcr.io/tuist/tuist-runner:"+pool, corev1.PodRunning, pool)
	pod.Spec.NodeName = node
	pod.Status.ContainerStatuses = []corev1.ContainerStatus{{
		Name:  "runner",
		State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{StartedAt: metav1.NewTime(preemptionNow.Add(-warmFor))}},
	}}
	return pod
}

func busyDarwinPod(name, pool, node string) *corev1.Pod {
	pod := warmDarwinPod(name, pool, node, time.Hour)
	pod.Labels["tuist.dev/runner-pool-owner"] = "tuist"
	return pod
}

func rejectedPod(name, pool string, rejectedFor time.Duration, message string) *corev1.Pod {
	pod := newRunnerPod(name, "ghcr.io/tuist/tuist-runner:"+pool, corev1.PodPending, pool)
	pod.Status.Conditions = []corev1.PodCondition{{
		Type:               corev1.PodScheduled,
		Status:             corev1.ConditionFalse,
		Reason:             corev1.PodReasonUnschedulable,
		Message:            message,
		LastTransitionTime: metav1.NewTime(preemptionNow.Add(-rejectedFor)),
	}}
	return pod
}

const insufficientCPU = "0/8 nodes are available: 8 Insufficient cpu."

func TestClassifyForPreemption(t *testing.T) {
	pool := darwinRackPool("macos-27-0", 6)
	member := fleetMember{pool: pool, cost: 1, queued: 0, allocated: 2}

	marked := warmDarwinPod("marked", pool.Name, "b02", time.Hour)
	marked.Annotations = map[string]string{
		preemptedForAnnotation: "smoke",
		preemptedAtAnnotation:  preemptionNow.Add(-10 * time.Second).Format(time.RFC3339),
	}
	deleting := warmDarwinPod("deleting", pool.Name, "b03", time.Hour)
	deleting.DeletionTimestamp = ptr.To(metav1.NewTime(preemptionNow.Add(-5 * time.Second)))
	booting := newRunnerPod("booting", pool.Spec.Image, corev1.PodPending, pool.Name)
	booting.Spec.NodeName = "b04"

	pods := []corev1.Pod{
		*warmDarwinPod("warm-old", pool.Name, "b02", 10*time.Minute),
		*warmDarwinPod("warm-older", pool.Name, "b03", 20*time.Minute),
		*warmDarwinPod("just-warm", pool.Name, "b04", 30*time.Second),
		*busyDarwinPod("busy", pool.Name, "b05"),
		*booting,
		*marked,
		*deleting,
		*rejectedPod("rejected", pool.Name, time.Minute, insufficientCPU),
		*rejectedPod("rejected-fresh", pool.Name, 5*time.Second, insufficientCPU),
		*rejectedPod("rejected-taint", pool.Name, time.Minute, "0/8 nodes are available: 8 node(s) had untolerated taint."),
	}

	got := classifyForPreemption(member, 6, pods, preemptionNow)

	var names []string
	for _, pod := range got.preemptible {
		names = append(names, pod.Name)
	}
	if strings.Join(names, ",") != "warm-older,warm-old" {
		t.Errorf("preemptible = %v, want warm-older,warm-old (oldest warm first; busy, booting, marked and just-warm excluded)", names)
	}
	if got.idleBound != 5 {
		t.Errorf("idleBound = %d, want 5 (both warm, just-warm, booting, marked)", got.idleBound)
	}
	if got.freeing != 1 {
		t.Errorf("freeing = %d, want 1 (7 seats held, including the deleting Pod, against 6 replicas)", got.freeing)
	}
	if got.rejected != 1 {
		t.Errorf("rejected = %d, want 1 (only a capacity refusal past the wait)", got.rejected)
	}
	if len(got.unboundIdle) != 3 {
		t.Errorf("unboundIdle = %d, want 3", len(got.unboundIdle))
	}
}

// rackFixture is the 2026-10-14 15:19 UTC shape: 8 dual-guest rack hosts,
// the 27.0 pool holding 7 runners for 3 jobs inside its cooldown, the smoke
// pool running 9 jobs on the remaining slots, and
// 4 more smoke jobs queued whose Pods the scheduler cannot place.
func rackFixture(t *testing.T, smokeQueued int32, idleWarmFor time.Duration, extra ...client.Object) (*AutoscalerReconciler, client.Client) {
	t.Helper()

	xcode := darwinRackPool("macos-ber1-27-0", 7)
	xcode.Status.LastScaleDownAt = ptr.To(metav1.NewTime(preemptionNow.Add(-time.Minute)))
	smoke := darwinRackPool("ber1", 12)

	objs := []client.Object{xcode, smoke}
	for i := 1; i <= 8; i++ {
		node := macosNodeWithResources(fmt.Sprintf("ber1-runner-b%02d", i), rackFleet, 12, 2*macosGuestMemoryMB)
		objs = append(objs, node)
	}
	for i := 0; i < 3; i++ {
		objs = append(objs, busyDarwinPod(fmt.Sprintf("xcode-busy-%d", i), xcode.Name, fmt.Sprintf("ber1-runner-b%02d", i+1)))
	}
	for i := 0; i < 4; i++ {
		objs = append(objs, warmDarwinPod(fmt.Sprintf("xcode-idle-%d", i), xcode.Name, fmt.Sprintf("ber1-runner-b%02d", i+4), idleWarmFor))
	}
	for i := 0; i < 9; i++ {
		objs = append(objs, busyDarwinPod(fmt.Sprintf("smoke-busy-%d", i), smoke.Name, fmt.Sprintf("ber1-runner-b%02d", i%8+1)))
	}
	for i := int32(0); i < smokeQueued; i++ {
		objs = append(objs, rejectedPod(fmt.Sprintf("smoke-pending-%d", i), smoke.Name, time.Minute, insufficientCPU))
	}
	objs = append(objs, extra...)

	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objs...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()

	signals := map[string]scaling.Signals{
		xcode.Name: {Fleet: xcode.Name, Claimed: 3, Occupied: 3, P95ConcurrentLastHour: 7},
		smoke.Name: {Fleet: smoke.Name, Claimed: 9, Occupied: 9, Queued: smokeQueued, P95ConcurrentLastHour: 6},
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signals[r.URL.Query().Get("fleet")])
	}))
	t.Cleanup(server.Close)
	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	sc := scaling.NewClient(server.URL)
	sc.TokenPath = tokenPath

	return &AutoscalerReconciler{
		Client:        c,
		Scheme:        scheme,
		SignalsClient: sc,
		PollInterval:  time.Millisecond,
		Now:           func() time.Time { return preemptionNow },
	}, c
}

func markedPods(t *testing.T, c client.Client, pool string) []string {
	t.Helper()
	var pods corev1.PodList
	if err := c.List(context.Background(), &pods, client.MatchingLabels{"tuist.dev/runner-pool": pool}); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	var marked []string
	for i := range pods.Items {
		if forPools, ok := preemptionMark(&pods.Items[i], preemptionNow); ok {
			marked = append(marked, pods.Items[i].Name+"="+forPools)
		}
	}
	return marked
}

func TestAutoscaler_PreemptsIdleRunnersForStarvedSiblingDuringCooldown(t *testing.T) {
	r, c := rackFixture(t, 4, 5*time.Minute)

	reconcileOnce(t, r, "macos-ber1-27-0")

	got := &tuistv1.RunnerPool{}
	_ = c.Get(context.Background(), client.ObjectKey{Name: "macos-ber1-27-0", Namespace: "tuist-runners"}, got)
	if got.Spec.Replicas != 3 {
		t.Fatalf("Replicas = %d, want 3 (its 3 jobs; the 4 idle runners yield to the smoke pool's queue)", got.Spec.Replicas)
	}
	marked := markedPods(t, c, "macos-ber1-27-0")
	if len(marked) != 4 {
		t.Fatalf("marked = %v, want the 4 idle runners", marked)
	}
	for _, m := range marked {
		if !strings.HasPrefix(m, "xcode-idle-") || !strings.HasSuffix(m, "=ber1") {
			t.Errorf("marked %q, want only idle runners preempted for ber1", m)
		}
	}
	if !got.Status.LastScaleDownAt.Time.Equal(preemptionNow) {
		t.Errorf("LastScaleDownAt = %v, want %v", got.Status.LastScaleDownAt, preemptionNow)
	}
}

func TestAutoscaler_CooldownHoldsWhenNoSiblingIsStarved(t *testing.T) {
	r, c := rackFixture(t, 0, 5*time.Minute)

	reconcileOnce(t, r, "macos-ber1-27-0")

	got := &tuistv1.RunnerPool{}
	_ = c.Get(context.Background(), client.ObjectKey{Name: "macos-ber1-27-0", Namespace: "tuist-runners"}, got)
	if got.Spec.Replicas != 7 {
		t.Fatalf("Replicas = %d, want 7 (cooldown applies when nothing waits)", got.Spec.Replicas)
	}
	if marked := markedPods(t, c, "macos-ber1-27-0"); len(marked) != 0 {
		t.Fatalf("marked = %v, want none", marked)
	}
}

func TestAutoscaler_DoesNotPreemptRunnersWithinTheirWarmGrace(t *testing.T) {
	r, c := rackFixture(t, 4, 30*time.Second)

	reconcileOnce(t, r, "macos-ber1-27-0")

	got := &tuistv1.RunnerPool{}
	_ = c.Get(context.Background(), client.ObjectKey{Name: "macos-ber1-27-0", Namespace: "tuist-runners"}, got)
	if got.Spec.Replicas != 7 {
		t.Fatalf("Replicas = %d, want 7 (runners warm for 30s may be about to claim)", got.Spec.Replicas)
	}
}

func TestAutoscaler_StarvedPoolKeepsItsOwnReplicas(t *testing.T) {
	r, c := rackFixture(t, 4, 5*time.Minute)

	reconcileOnce(t, r, "ber1")

	got := &tuistv1.RunnerPool{}
	_ = c.Get(context.Background(), client.ObjectKey{Name: "ber1", Namespace: "tuist-runners"}, got)
	if got.Spec.Replicas < 12 {
		t.Fatalf("Replicas = %d, want >= 12 (a starved pool is never preempted)", got.Spec.Replicas)
	}
	if marked := markedPods(t, c, "ber1"); len(marked) != 0 {
		t.Fatalf("marked = %v, want none", marked)
	}
}

func preemptedCounter(t *testing.T, fleetSelector, pool string) float64 {
	t.Helper()
	families, err := ctrlmetrics.Registry.Gather()
	if err != nil {
		t.Fatalf("gather: %v", err)
	}
	for _, f := range families {
		if f.GetName() != "tuist_runners_pool_preempted_pods_total" {
			continue
		}
		for _, m := range f.GetMetric() {
			labels := map[string]string{}
			for _, l := range m.GetLabel() {
				labels[l.GetName()] = l.GetValue()
			}
			if labels["fleet_selector"] == fleetSelector && labels["pool"] == pool {
				return m.GetCounter().GetValue()
			}
		}
	}
	return 0
}

func TestReconcile_RetiresPreemptedRunnersFirst(t *testing.T) {
	const poolName = "macos-ber1-27-0"
	metrics.ClearRunnerPool(poolName)
	t.Cleanup(func() { metrics.ClearRunnerPool(poolName) })

	scheme := mustScheme(t)
	pool := newPool(poolName, "img", 2)
	pool.Spec.OS = "darwin"
	pool.Spec.FleetSelector = rackFleet

	idleA := newRunnerPod(poolName+"-runner-a", "img", corev1.PodRunning, poolName)
	idleB := newRunnerPod(poolName+"-runner-b", "img", corev1.PodRunning, poolName)
	preempted := newRunnerPod(poolName+"-runner-c", "img", corev1.PodRunning, poolName)
	preempted.Annotations = map[string]string{
		preemptedForAnnotation: "ber1",
		preemptedAtAnnotation:  preemptionNow.Add(-5 * time.Second).Format(time.RFC3339),
	}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, idleA, idleB, preempted).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()
	recorder := record.NewFakeRecorder(4)
	r := &RunnerPoolReconciler{
		Client:      c,
		Scheme:      scheme,
		DispatchURL: "http://dispatch",
		Recorder:    recorder,
		Now:         func() time.Time { return preemptionNow },
	}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	if err := c.Get(context.Background(), nn(pool.Namespace, preempted.Name), &corev1.Pod{}); !apierrors.IsNotFound(err) {
		t.Fatalf("preempted Pod get error = %v, want NotFound", err)
	}
	for _, name := range []string{idleA.Name, idleB.Name} {
		if err := c.Get(context.Background(), nn(pool.Namespace, name), &corev1.Pod{}); err != nil {
			t.Errorf("unmarked idle Pod %s: %v, want kept", name, err)
		}
	}
	select {
	case event := <-recorder.Events:
		if !strings.Contains(event, "RunnerPodPreemptedForSiblingDemand") || !strings.Contains(event, "ber1") {
			t.Errorf("event = %q, want RunnerPodPreemptedForSiblingDemand naming ber1", event)
		}
	default:
		t.Fatal("expected a RunnerPodPreemptedForSiblingDemand event")
	}
	if got := preemptedCounter(t, rackFleet, poolName); got != 1 {
		t.Errorf("preempted counter = %v, want 1", got)
	}
}

func TestReconcile_ExpiredPreemptionMarkIsAnOrdinaryScaleDown(t *testing.T) {
	const poolName = "macos-ber1-26-6"
	metrics.ClearRunnerPool(poolName)
	t.Cleanup(func() { metrics.ClearRunnerPool(poolName) })

	scheme := mustScheme(t)
	pool := newPool(poolName, "img", 0)
	pool.Spec.OS = "darwin"
	pool.Spec.FleetSelector = rackFleet

	stale := newRunnerPod(poolName+"-runner-a", "img", corev1.PodRunning, poolName)
	stale.Annotations = map[string]string{
		preemptedForAnnotation: "ber1",
		preemptedAtAnnotation:  preemptionNow.Add(-time.Hour).Format(time.RFC3339),
	}

	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(pool, stale).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()
	recorder := record.NewFakeRecorder(4)
	r := &RunnerPoolReconciler{
		Client:      c,
		Scheme:      scheme,
		DispatchURL: "http://dispatch",
		Recorder:    recorder,
		Now:         func() time.Time { return preemptionNow },
	}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	select {
	case event := <-recorder.Events:
		t.Fatalf("event = %q, want none for an expired mark", event)
	default:
	}
	if got := preemptedCounter(t, rackFleet, poolName); got != 0 {
		t.Errorf("preempted counter = %v, want 0", got)
	}
}

// The cut is taken from the Pods that exist, not from spec.replicas: a pool
// still recreating Pods would otherwise keep some of the runners it marked.
func TestPreemption_RetiresEveryMarkedRunnerWhenThePoolHasAReplicaGap(t *testing.T) {
	r, c := rackFixture(t, 4, 5*time.Minute)
	ctx := context.Background()
	key := client.ObjectKey{Name: "macos-ber1-27-0", Namespace: "tuist-runners"}
	t.Cleanup(func() { metrics.Clear(key.Name) })

	xcode := &tuistv1.RunnerPool{}
	if err := c.Get(ctx, key, xcode); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	xcode.Spec.Replicas = 9
	if err := c.Update(ctx, xcode); err != nil {
		t.Fatalf("update pool: %v", err)
	}

	reconcileOnce(t, r, key.Name)
	if marked := markedPods(t, c, key.Name); len(marked) != 4 {
		t.Fatalf("marked = %v, want the 4 idle runners", marked)
	}

	pools := &RunnerPoolReconciler{
		Client:      c,
		Scheme:      c.Scheme(),
		DispatchURL: "http://dispatch",
		Now:         func() time.Time { return preemptionNow },
	}
	if _, err := pools.Reconcile(ctx, ctrl.Request{NamespacedName: key}); err != nil {
		t.Fatalf("reconcile pool: %v", err)
	}

	if marked := markedPods(t, c, key.Name); len(marked) != 0 {
		t.Fatalf("marked runners left after the reap = %v, want none", marked)
	}
	got := &tuistv1.RunnerPool{}
	_ = c.Get(ctx, key, got)
	if got.Spec.Replicas != 3 {
		t.Fatalf("Replicas = %d, want 3 (7 Pods minus the 4 preempted)", got.Spec.Replicas)
	}
}

// A runner whose job ended is replaced at once by its pool, so its seat is
// not coming back to the fleet and must not cancel a sibling's starvation.
func TestPreemption_ReplacedRunnerIsNotFreeCapacity(t *testing.T) {
	victim := darwinRackPool("macos-ber1-26-6", 4)
	busy := darwinRackPool("macos-ber1-27-0", 3)
	smoke := darwinRackPool("ber1", 1)

	finished := busyDarwinPod("finished", busy.Name, "b01")
	finished.DeletionTimestamp = ptr.To(metav1.NewTime(preemptionNow.Add(-5 * time.Second)))
	finished.Finalizers = []string{"tart-kubelet.tuist.dev/vm-cleanup"}
	replacement := newRunnerPod("replacement", busy.Spec.Image, corev1.PodPending, busy.Name)
	busyPods := []corev1.Pod{
		*busyDarwinPod("busy-a", busy.Name, "b02"),
		*busyDarwinPod("busy-b", busy.Name, "b03"),
		*finished,
		*replacement,
	}
	victimPods := []corev1.Pod{
		*warmDarwinPod("idle-a", victim.Name, "b04", 10*time.Minute),
		*warmDarwinPod("idle-b", victim.Name, "b05", 10*time.Minute),
	}
	smokePods := []corev1.Pod{*rejectedPod("pending", smoke.Name, time.Minute, insufficientCPU)}

	inputs := []*preemptionPool{
		classifyForPreemption(fleetMember{pool: victim, cost: 1, allocated: 1}, victim.Spec.Replicas, victimPods, preemptionNow),
		classifyForPreemption(fleetMember{pool: busy, cost: 1, allocated: 3}, busy.Spec.Replicas, busyPods, preemptionNow),
		classifyForPreemption(fleetMember{pool: smoke, cost: 1, queued: 1, allocated: 1}, smoke.Spec.Replicas, smokePods, preemptionNow),
	}

	chosen, starved := planPreemption(victim.Name, inputs)
	if len(chosen) != 1 || strings.Join(starved, ",") != "ber1" {
		t.Fatalf("chosen %d for %v, want 1 for ber1 (the finished runner's seat goes to its replacement)", len(chosen), starved)
	}
}

// The starved Pod takes whichever seat frees, so the victim gives up the
// runner on a host that already holds the starved pool's golden image and
// the starved job clones it instead of pulling it.
func TestPreemption_PrefersHostsHoldingTheStarvedPoolsImage(t *testing.T) {
	r, c := rackFixture(t, 1, 5*time.Minute)
	ctx := context.Background()

	smoke := &tuistv1.RunnerPool{}
	if err := c.Get(ctx, client.ObjectKey{Name: "ber1", Namespace: "tuist-runners"}, smoke); err != nil {
		t.Fatalf("get smoke pool: %v", err)
	}
	node := &corev1.Node{}
	if err := c.Get(ctx, client.ObjectKey{Name: "ber1-runner-b07"}, node); err != nil {
		t.Fatalf("get node: %v", err)
	}
	node.Labels[podtemplate.GoldenNodeAffinityKey(smoke.Spec.Image)] = "true"
	if err := c.Update(ctx, node); err != nil {
		t.Fatalf("label node: %v", err)
	}

	reconcileOnce(t, r, "macos-ber1-27-0")

	if marked := markedPods(t, c, "macos-ber1-27-0"); strings.Join(marked, ",") != "xcode-idle-3=ber1" {
		t.Fatalf("marked = %v, want xcode-idle-3 (the idle runner on b07, which holds the smoke pool's image)", marked)
	}
}
