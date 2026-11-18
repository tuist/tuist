package controllers

import (
	"context"
	"strings"
	"testing"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

type lvmStandbyFixture struct {
	resizeHoldFixture
	c        client.Client
	r        *KuraInstanceReconciler
	statuses map[string]runtimeStatus
	request  ctrl.Request
}

func newLVMStandbyFixture(t *testing.T, standbyClaim *corev1.PersistentVolumeClaim, class string) lvmStandbyFixture {
	t.Helper()
	ctx := context.Background()
	scheme := meshTestScheme(t)
	f := lvmStandbyFixture{resizeHoldFixture: newResizeHoldFixture(100), statuses: map[string]runtimeStatus{}}
	f.instance.Spec.Replicas = ptr(int32(1))
	f.instance.Spec.StorageClassName = class
	f.instance.Spec.DiskResource = string(kuraDiskResource)
	sharedSecret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: f.instance.Namespace, ResourceVersion: "1"}}
	source := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "source", Annotations: map[string]string{lvmMigrationNodeAnnotation: "true"}}, Spec: corev1.NodeSpec{Unschedulable: true}}
	landing := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "landing", Labels: map[string]string{"node.cluster.x-k8s.io/pool": "kura"}}, Status: corev1.NodeStatus{
		Allocatable: corev1.ResourceList{kuraDiskResource: resource.MustParse("64Gi")},
		Conditions:  []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
	}}
	claim, pv := f.boundClaim(0, false, source.Name)
	pod := f.settledPod(0, source.Name)
	objects := []client.Object{f.instance, sharedSecret, source, landing, claim, pv, pod}
	if class == thinLocalStorageClass {
		landing.Labels["tuist.dev/kura-thin-ready"] = "true"
		objects = append(objects, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}})
	}
	if standbyClaim != nil {
		objects = append(objects, standbyClaim)
	}
	f.c = fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).WithStatusSubresource(f.instance, &appsv1.StatefulSet{}).Build()
	f.r = &KuraInstanceReconciler{Client: f.c, Scheme: scheme, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: f.statuses}, PublicConnectionRetirer: stubConnectionRetirer{ready: true}}
	if err := f.r.applyStatefulSet(ctx, f.instance, true); err != nil {
		t.Fatal(err)
	}
	f.request = ctrl.Request{NamespacedName: client.ObjectKeyFromObject(f.instance)}
	return f
}

func (f lvmStandbyFixture) boundClaim(ordinal int, verified bool, node string) (*corev1.PersistentVolumeClaim, *corev1.PersistentVolume) {
	claim := f.claim(ordinal, "32Gi")
	attributes := map[string]string{"backing": "file"}
	if verified && f.instance.Spec.StorageClassName == thinLocalStorageClass {
		attributes = map[string]string{"backing": "thin", "layout": "thin-luks-xfs-v1", "capacity_mode": "ceiling-backed-v1"}
	} else if verified {
		attributes["backing"] = "lvm"
	}
	claim.Spec.StorageClassName = ptr(f.instance.Spec.StorageClassName)
	claim.Spec.VolumeName = claim.Name + "-" + attributes["backing"]
	claim.Status.Phase = corev1.ClaimBound
	pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: claim.Spec.VolumeName}, Spec: corev1.PersistentVolumeSpec{
		PersistentVolumeSource: corev1.PersistentVolumeSource{CSI: &corev1.CSIPersistentVolumeSource{Driver: "kura-volumes.tuist.dev", VolumeHandle: claim.Spec.VolumeName, VolumeAttributes: attributes}},
		NodeAffinity:           &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: encryptedLocalTopologyKey, Operator: corev1.NodeSelectorOpIn, Values: []string{node}}}}}}},
	}}
	return claim, pv
}

func (f lvmStandbyFixture) settledPod(ordinal int, node string) *corev1.Pod {
	pod := f.servingPod(ordinal, "100m")
	pod.Spec.NodeName = node
	pod.Status.PodIP = "10.0.0." + string(rune('1'+ordinal))
	f.statuses[pod.Name] = runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: backfillCycleComplete, ConnectionIncarnation: "current-boot"}
	return pod
}

func (f lvmStandbyFixture) reconcile(t *testing.T) {
	t.Helper()
	if _, err := f.r.Reconcile(context.Background(), f.request); err != nil {
		t.Fatal(err)
	}
}

func (f lvmStandbyFixture) statefulSetReplicas(t *testing.T) int32 {
	t.Helper()
	sts := &appsv1.StatefulSet{}
	if err := f.c.Get(context.Background(), f.request.NamespacedName, sts); err != nil {
		t.Fatal(err)
	}
	return *sts.Spec.Replicas
}

func (f lvmStandbyFixture) serveFrom(t *testing.T, pod string) {
	t.Helper()
	ctx := context.Background()
	endpoints := &corev1.Endpoints{ObjectMeta: metav1.ObjectMeta{Name: f.instance.Name, Namespace: f.instance.Namespace}}
	_ = f.c.Delete(ctx, endpoints)
	serving := &corev1.Pod{}
	if err := f.c.Get(ctx, client.ObjectKey{Namespace: f.instance.Namespace, Name: pod}, serving); err != nil {
		t.Fatal(err)
	}
	endpoints.Subsets = []corev1.EndpointSubset{{Addresses: []corev1.EndpointAddress{{IP: "10.0.0.9", TargetRef: &corev1.ObjectReference{Name: pod, UID: serving.UID}}}}}
	if err := f.c.Create(ctx, endpoints); err != nil {
		t.Fatal(err)
	}
}

func (f lvmStandbyFixture) exists(t *testing.T, object client.Object, name string) bool {
	t.Helper()
	err := f.c.Get(context.Background(), client.ObjectKey{Namespace: f.instance.Namespace, Name: name}, object)
	if err != nil && !apierrors.IsNotFound(err) {
		t.Fatal(err)
	}
	return err == nil
}

func TestLVMMigrationMovesASingleCopyBehindATemporaryStandby(t *testing.T) {
	for _, class := range []string{encryptedLocalStorageClass, thinLocalStorageClass} {
		t.Run(class, func(t *testing.T) { testSingleCopyStandbyMigration(t, class) })
	}
}

func testSingleCopyStandbyMigration(t *testing.T, class string) {
	ctx := context.Background()
	f := newLVMStandbyFixture(t, nil, class)
	name := func(ordinal int) string { return f.claim(ordinal, "32Gi").Name }
	podName := func(ordinal int) string { return f.instance.Name + "-" + string(rune('0'+ordinal)) }

	// The selected source is the only copy: a second ordinal is added on the
	// declared storage before anything is taken down.
	f.reconcile(t)
	if got := f.statefulSetReplicas(t); got != 2 {
		t.Fatalf("StatefulSet replicas = %d, want a temporary standby", got)
	}
	if !f.exists(t, &corev1.PersistentVolumeClaim{}, name(0)) {
		t.Fatal("source claim removed before a standby existed")
	}

	// The StatefulSet creates the standby from the current template. Until it
	// has caught up, the source keeps serving.
	standby := f.claim(1, "32Gi")
	standby.Spec.StorageClassName = ptr(class)
	if err := f.c.Create(ctx, standby); err != nil {
		t.Fatal(err)
	}
	pending := f.settledPod(1, "landing")
	f.statuses[pending.Name] = runtimeStatus{Ready: true, State: "serving", RingMembers: 2, BackfillInitialCycle: "running", ConnectionIncarnation: "current-boot"}
	if err := f.c.Create(ctx, pending); err != nil {
		t.Fatal(err)
	}
	f.reconcile(t)
	if !f.exists(t, standby, name(1)) || standby.Annotations[lvmMigrationStandbyAnnotation] == "" {
		t.Fatal("the migration did not record its standby claim")
	}
	source := &corev1.Pod{}
	if !f.exists(t, source, podName(0)) || source.Annotations[lvmRebuildAnnotation] != "" {
		t.Fatal("source handed over before its standby caught up")
	}

	// Caught up: the ordinary handoff moves the endpoint, then rebuilds the source.
	f.statuses[pending.Name] = runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: backfillCycleComplete, ConnectionIncarnation: "current-boot"}
	f.reconcile(t)
	// A thin source first records its destination, then proves its writes there.
	f.reconcile(t)
	if !f.exists(t, source, podName(0)) || source.Annotations[lvmRebuildAnnotation] == "" {
		t.Fatal("source was not marked for handoff")
	}
	f.serveFrom(t, podName(1))
	f.reconcile(t)
	if f.exists(t, &corev1.PersistentVolumeClaim{}, name(0)) || f.exists(t, &corev1.Pod{}, podName(0)) {
		t.Fatal("source volume was not rebuilt behind the standby")
	}
	if got := f.statefulSetReplicas(t); got != 2 {
		t.Fatalf("standby removed while the source was rebuilt: replicas = %d", got)
	}

	// The rebuilt source comes back on verified storage and refills from the
	// standby. The standby keeps serving until the source has caught up.
	claim, pv := f.boundClaim(0, true, "landing")
	rebuilt := f.settledPod(0, "landing")
	f.statuses[rebuilt.Name] = runtimeStatus{Ready: true, State: "serving", RingMembers: 2, BackfillInitialCycle: "running", ConnectionIncarnation: "current-boot"}
	for _, object := range []client.Object{claim, pv, rebuilt} {
		if err := f.c.Create(ctx, object); err != nil {
			t.Fatal(err)
		}
	}
	f.reconcile(t)
	if !f.exists(t, source, podName(1)) || source.Annotations[lvmRebuildAnnotation] != "" {
		t.Fatal("standby handed back before the rebuilt source caught up")
	}
	f.statuses[rebuilt.Name] = runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: backfillCycleComplete, ConnectionIncarnation: "current-boot"}
	f.reconcile(t)
	f.reconcile(t)
	if !f.exists(t, source, podName(1)) || source.Annotations[lvmRebuildAnnotation] == "" {
		t.Fatal("standby was not handed back through the same handoff")
	}
	if class == thinLocalStorageClass && !strings.Contains(source.Annotations[lvmWriteTargetAnnotation], `"pod":"`+podName(0)+`"`) {
		t.Fatalf("standby write bridge targets %s, want the rebuilt source", source.Annotations[lvmWriteTargetAnnotation])
	}
	if !f.exists(t, &corev1.PersistentVolumeClaim{}, name(1)) {
		t.Fatal("standby claim released before the endpoint moved back")
	}
	f.serveFrom(t, podName(0))
	f.reconcile(t)
	if f.exists(t, &corev1.PersistentVolumeClaim{}, name(1)) {
		t.Fatal("standby claim was not released after the handback")
	}
	f.reconcile(t)
	if got := f.statefulSetReplicas(t); got != 1 {
		t.Fatalf("StatefulSet replicas = %d after the migration, want the declared single copy", got)
	}
	instance := &kurav1.KuraInstance{}
	if err := f.c.Get(ctx, f.request.NamespacedName, instance); err != nil {
		t.Fatal(err)
	}
	if replicas(instance) != 1 {
		t.Fatalf("the standby leaked into the declared spec: replicas = %d", replicas(instance))
	}
}

func TestLVMMigrationStandbyNeverAdoptsALeftoverClaim(t *testing.T) {
	// A claim retained by an earlier scale-down still holds the old storage.
	// Scaling up would bring it back as the copy that receives the endpoint.
	leftover := (resizeHoldFixture{instance: newResizeHoldFixture(100).instance}).claim(1, "32Gi")
	leftover.Spec.StorageClassName = ptr(localPathStorageClass)
	f := newLVMStandbyFixture(t, leftover, encryptedLocalStorageClass)
	f.reconcile(t)
	if got := f.statefulSetReplicas(t); got != 1 {
		t.Fatalf("StatefulSet replicas = %d with a leftover claim, want the single copy held", got)
	}
	claim := &corev1.PersistentVolumeClaim{}
	if !f.exists(t, claim, leftover.Name) || claim.Annotations[lvmMigrationStandbyAnnotation] != "" {
		t.Fatal("leftover claim was adopted as the standby")
	}
	if !f.exists(t, &corev1.PersistentVolumeClaim{}, f.claim(0, "32Gi").Name) {
		t.Fatal("source claim removed without a standby")
	}
}

func TestLVMMigrationStandbyWaitsForSourceSelection(t *testing.T) {
	ctx := context.Background()
	f := newLVMStandbyFixture(t, nil, encryptedLocalStorageClass)
	source := &corev1.Node{}
	if err := f.c.Get(ctx, client.ObjectKey{Name: "source"}, source); err != nil {
		t.Fatal(err)
	}
	delete(source.Annotations, lvmMigrationNodeAnnotation)
	if err := f.c.Update(ctx, source); err != nil {
		t.Fatal(err)
	}
	f.reconcile(t)
	if got := f.statefulSetReplicas(t); got != 1 {
		t.Fatalf("StatefulSet replicas = %d before the source was selected", got)
	}
}
