package controllers

import (
	"context"
	"errors"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// stubRuntimeStatus answers the rollout endpoint per pod, so a test can say
// "this replica is ready but still filling" without a network.
type stubRuntimeStatus struct {
	byPod map[string]runtimeStatus
	err   error
}

func (s stubRuntimeStatus) Status(_ context.Context, pod corev1.Pod) (runtimeStatus, error) {
	if s.err != nil {
		return runtimeStatus{}, s.err
	}
	status, ok := s.byPod[pod.Name]
	if !ok {
		return runtimeStatus{}, errors.New("no status")
	}
	return status, nil
}

// routableStatus is what the runtime reports for a pod eligible to hold the
// primary role: Ready alone is not enough, selection also needs serving state,
// the writer lock and ring visibility. `cycle` is the catch-up report that
// evacuation gates on separately.
func routableStatus(cycle string) runtimeStatus {
	return runtimeStatus{
		Ready:                true,
		State:                "serving",
		WriterLockOwned:      true,
		RingMembers:          2,
		BackfillInitialCycle: cycle,
	}
}

func evacInstance() *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-acct-region", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			Replicas:     ptr[int32](2),
			NodeSelector: map[string]string{"node.cluster.x-k8s.io/pool": "kura-region"},
		},
	}
}

func evacPod(name, node string, ready bool) *corev1.Pod {
	condition := corev1.ConditionFalse
	if ready {
		condition = corev1.ConditionTrue
	}
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "kura",
			Labels: map[string]string{
				"app.kubernetes.io/name":     "kura",
				"app.kubernetes.io/instance": "kura-acct-region",
				podNameLabel:                 name,
			},
		},
		Spec: corev1.PodSpec{NodeName: node},
		Status: corev1.PodStatus{
			PodIP:      "10.0.0.1",
			Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: condition}},
		},
	}
}

func evacNode(name string, marked bool) *corev1.Node {
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name:   name,
			Labels: map[string]string{"node.cluster.x-k8s.io/pool": "kura-region"},
		},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
		},
	}
	if marked {
		node.Annotations = map[string]string{EvacuateNodeAnnotation: "true"}
	}
	return node
}

// primaryService pins the public Service at a pod, which is how the controller
// reads back which replica is currently serving.
func primaryService(pod string) *corev1.Service {
	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-acct-region", Namespace: "kura"},
		Spec:       corev1.ServiceSpec{Selector: map[string]string{podNameLabel: pod}},
	}
}

// servingEndpoints models the instance's public Service actually having a ready
// address, which is what proves traffic has somewhere to land before the former
// primary is deleted.
func servingEndpoints(pods ...string) *corev1.Endpoints {
	addresses := make([]corev1.EndpointAddress, 0, len(pods))
	for _, pod := range pods {
		addresses = append(addresses, corev1.EndpointAddress{
			IP:        "10.0.0.1",
			TargetRef: &corev1.ObjectReference{Kind: "Pod", Name: pod, Namespace: "kura"},
		})
	}
	return &corev1.Endpoints{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-acct-region", Namespace: "kura"},
		Subsets:    []corev1.EndpointSubset{{Addresses: addresses}},
	}
}

func evacScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	if err := corev1.AddToScheme(s); err != nil {
		t.Fatalf("add corev1 to scheme: %v", err)
	}
	if err := kurav1alpha1.AddToScheme(s); err != nil {
		t.Fatalf("add kura to scheme: %v", err)
	}
	return s
}

func evacReconciler(t *testing.T, status stubRuntimeStatus, objects ...client.Object) (*KuraInstanceReconciler, client.Client) {
	t.Helper()
	s := evacScheme(t)
	c := fake.NewClientBuilder().WithScheme(s).WithObjects(objects...).Build()
	return &KuraInstanceReconciler{Client: c, Scheme: s, RuntimeStatusClient: status}, c
}

func podExists(t *testing.T, c client.Client, name string) bool {
	t.Helper()
	pod := &corev1.Pod{}
	err := c.Get(context.Background(), client.ObjectKey{Namespace: "kura", Name: name}, pod)
	return err == nil
}

// The standby moves first. Moving the primary first would land traffic on a pod
// whose volume is empty, which is the difference between a warm handover and a
// cold one.
func TestEvacuateMovesTheStandbyBeforeThePrimary(t *testing.T) {
	instance := evacInstance()
	caughtUp := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-0": routableStatus(backfillCycleComplete),
		"kura-acct-region-1": routableStatus(backfillCycleComplete),
	}}
	r, c := evacReconciler(t, caughtUp,
		instance,
		primaryService("kura-acct-region-0"),
		servingEndpoints("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "old-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}

	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("the primary was evacuated first; traffic would land on an empty volume")
	}
	if podExists(t, c, "kura-acct-region-1") {
		t.Fatal("expected the standby to be evacuated")
	}
}

// One replica per pass. Both at once leaves the instance with no serving pod.
func TestEvacuateMovesOneReplicaAtATime(t *testing.T) {
	instance := evacInstance()
	// The standby has already moved to the new box but is still filling.
	stillFilling := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-1": routableStatus("in_progress"),
	}}
	r, c := evacReconciler(t, stillFilling,
		instance,
		primaryService("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "new-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("the primary moved while the standby was still filling; the region would be cold")
	}
}

// Readiness is not proof of a completed catch-up: a pod latches ready at a
// ring-fullness threshold, so it can be ready and still filling. Once the
// runtime reports the cycle complete, the primary is free to follow.
func TestEvacuateWaitsForTheCatchUpSignalNotReadiness(t *testing.T) {
	instance := evacInstance()
	caughtUp := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-1": routableStatus(backfillCycleComplete),
	}}
	r, c := evacReconciler(t, caughtUp,
		instance,
		primaryService("kura-acct-region-0"),
		servingEndpoints("kura-acct-region-1"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "new-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if podExists(t, c, "kura-acct-region-0") {
		t.Fatal("expected the primary to follow once the standby reported a completed catch-up")
	}
}

// An unreachable pod is not evidence that a move finished, and guessing wrong
// costs the region's cache rather than a requeue.
func TestEvacuateHoldsWhenTheCatchUpSignalIsUnreadable(t *testing.T) {
	instance := evacInstance()
	r, c := evacReconciler(t, stubRuntimeStatus{err: errors.New("connection refused")},
		instance,
		primaryService("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "new-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("moved a replica while the previous one's status was unreadable")
	}
}

// Evacuating the only node the pods can run on turns a working box into Pending
// pods and an unreachable region, which is worse than leaving it up until its
// replacement joins the pool.
func TestEvacuateDoesNothingWithNowhereToLand(t *testing.T) {
	instance := evacInstance()
	caughtUp := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-0": routableStatus(backfillCycleComplete),
		"kura-acct-region-1": routableStatus(backfillCycleComplete),
	}}
	r, c := evacReconciler(t, caughtUp,
		instance,
		primaryService("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "old-box", true),
		evacNode("old-box", true),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") || !podExists(t, c, "kura-acct-region-1") {
		t.Fatal("evacuated with no landing node; the region would go unreachable rather than cold")
	}
}

// A node in another pool cannot take these pods, so it is not a landing node
// even though it is Ready and unmarked.
func TestEvacuateIgnoresNodesOutsideTheInstancesPool(t *testing.T) {
	instance := evacInstance()
	other := evacNode("other-pool-box", false)
	other.Labels["node.cluster.x-k8s.io/pool"] = "runners"

	caughtUp := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-0": routableStatus(backfillCycleComplete),
	}}
	r, c := evacReconciler(t, caughtUp,
		instance,
		primaryService("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacNode("old-box", true),
		other,
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("evacuated onto a node in another pool, where the pod cannot schedule")
	}
}

// Nothing marked means nothing moves. Cordoning a box to look at something must
// not spend a region's warm cache.
func TestEvacuateIsANoOpWithoutTheMarker(t *testing.T) {
	instance := evacInstance()
	cordonedButUnmarked := evacNode("old-box", false)
	cordonedButUnmarked.Spec.Unschedulable = true

	r, c := evacReconciler(t, stubRuntimeStatus{},
		instance,
		primaryService("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		cordonedButUnmarked,
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("a plain cordon triggered an evacuation")
	}
}

// The claim has to go before the pod. A local-path PV is pinned to the box that
// carved it, so deleting the pod alone reschedules it straight back onto the
// same node.
func TestReleaseNodeLocalVolumeDeletesTheClaimAndThePod(t *testing.T) {
	pod := evacPod("kura-acct-region-1", "old-box", true)
	claim := &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{Name: "data-kura-acct-region-1", Namespace: "kura"},
	}
	r, c := evacReconciler(t, stubRuntimeStatus{}, pod, claim)

	if err := r.releaseNodeLocalVolume(context.Background(), pod); err != nil {
		t.Fatalf("releaseNodeLocalVolume: %v", err)
	}
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(claim), &corev1.PersistentVolumeClaim{}); err == nil {
		t.Fatal("the claim survived; the replacement pod would rebind to the same node")
	}
	if podExists(t, c, pod.Name) {
		t.Fatal("the pod survived")
	}
}

// Deleting a pod the public Service still points at empties the endpoint until
// the next reconcile repoints it, which turns every primary evacuation into a
// gap. The delete waits for the role to move first.
func TestEvacuateWillNotDeleteThePodTheServiceStillNames(t *testing.T) {
	instance := evacInstance()
	caughtUp := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-0": routableStatus(backfillCycleComplete),
	}}
	// Only the primary is left on the outgoing box, and the Service still names it.
	r, c := evacReconciler(t, caughtUp,
		instance,
		primaryService("kura-acct-region-0"),
		servingEndpoints("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("deleted the pod the Service still selects; the endpoint would be empty until the next reconcile")
	}
}

// A moved selector is a write; a ready address elsewhere is a fact. Endpoints
// propagate asynchronously, so the delete waits on the fact.
func TestEvacuateWaitsForAnotherPodToActuallyServe(t *testing.T) {
	instance := evacInstance()
	caughtUp := stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-1": routableStatus(backfillCycleComplete),
	}}
	// Selector has moved to the standby, but only the outgoing pod is serving.
	r, c := evacReconciler(t, caughtUp,
		instance,
		primaryService("kura-acct-region-1"),
		servingEndpoints("kura-acct-region-0"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "new-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("deleted the only serving pod before another had a ready endpoint")
	}
}

// The case where only the selector guard can help: the standby has caught up on
// data but has not taken the writer lock, so it is in the Service's endpoints
// yet is not eligible to hold the primary role. Selection therefore keeps the
// outgoing pod as primary, and deleting it would empty the selector even though
// another address is present.
func TestEvacuateHoldsWhileTheOutgoingPodStillHoldsThePrimaryRole(t *testing.T) {
	instance := evacInstance()
	caughtUpButNotServing := runtimeStatus{
		Ready:                true,
		State:                "filling",
		WriterLockOwned:      false,
		RingMembers:          2,
		BackfillInitialCycle: backfillCycleComplete,
	}
	r, c := evacReconciler(t, stubRuntimeStatus{byPod: map[string]runtimeStatus{
		"kura-acct-region-0": routableStatus(backfillCycleComplete),
		"kura-acct-region-1": caughtUpButNotServing,
	}},
		instance,
		primaryService("kura-acct-region-0"),
		servingEndpoints("kura-acct-region-0", "kura-acct-region-1"),
		evacPod("kura-acct-region-0", "old-box", true),
		evacPod("kura-acct-region-1", "new-box", true),
		evacNode("old-box", true),
		evacNode("new-box", false),
	)

	if err := r.evacuateMarkedNodes(context.Background(), instance); err != nil {
		t.Fatalf("evacuateMarkedNodes: %v", err)
	}
	if !podExists(t, c, "kura-acct-region-0") {
		t.Fatal("deleted the pod still holding the primary role; the Service selector would name nothing")
	}
}
