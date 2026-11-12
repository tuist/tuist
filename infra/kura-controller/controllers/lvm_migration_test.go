package controllers

import (
	"context"
	"fmt"
	"reflect"
	"testing"

	kurav1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestLVMMigrationPreservesDonorAndHonorsGates(t *testing.T) {
	for _, tc := range []struct {
		name, backing, cycle                      string
		paused, single, wantDelete                bool
		skipMark, uncordoned, multiple, noLanding bool
		sourceOrdinal                             int
		otherLegacy, colocated                    bool
		thin                                      bool
	}{
		{name: "same class legacy file rebuilds one replica", colocated: true, backing: "file", cycle: backfillCycleComplete, wantDelete: true},
		{name: "thin migration advances with overhead backed reservation", thin: true, colocated: true, backing: "file", cycle: backfillCycleComplete, wantDelete: true},
		{name: "thick to thin migration advances with overhead backed reservation", thin: true, colocated: true, backing: "lvm", cycle: backfillCycleComplete, wantDelete: true},
		{name: "old driver without backing is migrated", cycle: backfillCycleComplete, wantDelete: true},
		{name: "verified LVM is preserved", backing: "lvm", cycle: backfillCycleComplete},
		{name: "backfill in progress holds both copies", backing: "file", cycle: "running"},
		{name: "operator pause holds both copies", backing: "file", cycle: backfillCycleComplete, paused: true},
		{name: "single copy holds for a standby", backing: "file", cycle: backfillCycleComplete, single: true},
		{name: "cross-host legacy claims hold the whole template", backing: "file", cycle: backfillCycleComplete, otherLegacy: true},
		{name: "regional enrollment alone holds legacy claims", backing: "file", cycle: backfillCycleComplete, skipMark: true},
		{name: "no prepared landing node holds the source", backing: "file", cycle: backfillCycleComplete, noLanding: true},
		{name: "source must be cordoned", backing: "file", cycle: backfillCycleComplete, uncordoned: true},
		{name: "multiple sources fail closed", backing: "file", cycle: backfillCycleComplete, multiple: true},
		{name: "skip unselected ordinal and migrate selected host only", backing: "file", cycle: backfillCycleComplete, sourceOrdinal: 1, wantDelete: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			scheme := runtime.NewScheme()
			_ = clientgoscheme.AddToScheme(scheme)
			_ = kurav1.AddToScheme(scheme)
			f := newResizeHoldFixture(100)
			f.instance.Spec.StorageClassName = encryptedLocalStorageClass
			if tc.thin {
				f.instance.Spec.StorageClassName = thinLocalStorageClass
			}
			f.instance.Spec.DiskResource = string(kuraDiskResource)
			if tc.single {
				f.instance.Spec.Replicas = ptr(int32(1))
			}
			sts := f.statefulSet(rollingUpdate(), "100m", nil)
			if tc.paused {
				sts.Spec.UpdateStrategy = onDelete()
			}
			sts.Spec.VolumeClaimTemplates[0].Spec.StorageClassName = ptr(f.instance.Spec.StorageClassName)
			sts.Spec.Template.Spec.Containers[0].Resources.Requests[kuraDiskResource] = diskReservation(f.instance)
			templateHeld := tc.skipMark || tc.noLanding || tc.uncordoned || tc.multiple || tc.otherLegacy
			if templateHeld {
				delete(sts.Spec.Template.Spec.Containers[0].Resources.Requests, kuraDiskResource)
				sts.Spec.Template.Spec.Containers[0].Resources.Requests[corev1.ResourceEphemeralStorage] = resource.MustParse("32Gi")
			}
			objects := []client.Object{f.instance, sts}
			if tc.thin {
				objects = append(objects, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}})
			}
			if !tc.noLanding {
				objects = append(objects, &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "prepared-spare", Labels: map[string]string{"tuist.dev/kura-thin-ready": "true", "node.cluster.x-k8s.io/pool": "kura"}}, Status: corev1.NodeStatus{Allocatable: corev1.ResourceList{kuraDiskResource: resource.MustParse("64Gi")}, Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}})
			}
			statuses := map[string]runtimeStatus{}
			for i := 0; i < int(replicas(f.instance)); i++ {
				claim := f.claim(i, "32Gi")
				claim.Spec.StorageClassName = ptr(encryptedLocalStorageClass)
				claim.Spec.VolumeName = fmt.Sprintf("pv-%d", i)
				claim.Status.Phase = corev1.ClaimBound
				pod := f.servingPod(i, "100m")
				pod.Status.PodIP = fmt.Sprintf("10.0.0.%d", i+1)
				pod.Spec.NodeName = fmt.Sprintf("source-%d", i)
				if tc.colocated {
					pod.Spec.NodeName = "source-0"
				}
				node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: pod.Spec.NodeName}, Spec: corev1.NodeSpec{Unschedulable: !tc.uncordoned}}
				if !tc.skipMark && (i == tc.sourceOrdinal || tc.multiple) {
					node.Annotations = map[string]string{lvmMigrationNodeAnnotation: "true"}
				}
				pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: claim.Spec.VolumeName}, Spec: corev1.PersistentVolumeSpec{PersistentVolumeSource: corev1.PersistentVolumeSource{CSI: &corev1.CSIPersistentVolumeSource{Driver: "kura-volumes.tuist.dev", VolumeHandle: claim.Spec.VolumeName, VolumeAttributes: map[string]string{"backing": tc.backing}}}}}
				pv.Spec.NodeAffinity = &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: encryptedLocalTopologyKey, Operator: corev1.NodeSelectorOpIn, Values: []string{node.Name}}}}}}}
				if !tc.otherLegacy && !tc.colocated && i != tc.sourceOrdinal {
					pv.Spec.CSI.VolumeAttributes["backing"] = "lvm"
				}
				objects = append(objects, claim, pod, pv)
				if !tc.colocated || i == 0 {
					objects = append(objects, node)
				}
				if i != tc.sourceOrdinal {
					objects = append(objects, &corev1.Endpoints{ObjectMeta: metav1.ObjectMeta{Name: f.instance.Name, Namespace: f.instance.Namespace}, Subsets: []corev1.EndpointSubset{{Addresses: []corev1.EndpointAddress{{IP: "10.0.0.2", TargetRef: &corev1.ObjectReference{Name: pod.Name}}}}}})
				}

				statuses[pod.Name] = runtimeStatus{Ready: true, BackfillInitialCycle: tc.cycle, ConnectionIncarnation: "current-boot"}
			}
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
			r := &KuraInstanceReconciler{Client: c, Scheme: scheme, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}, PublicConnectionRetirer: stubConnectionRetirer{ready: true}}
			_, err := r.reconcileDataStorageResize(context.Background(), f.instance)
			if err != nil {
				t.Fatal(err)
			}
			if templateHeld {
				if err := r.reconcileStatefulSetDuringResize(context.Background(), f.instance); err != nil {
					t.Fatal(err)
				}
				got := &appsv1.StatefulSet{}
				if err := c.Get(context.Background(), client.ObjectKeyFromObject(sts), got); err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(sts.Spec, got.Spec) {
					t.Fatal("waiting for node selection changed the legacy replacement template")
				}
			}
			if tc.wantDelete {
				for i := 0; i < 2; i++ {
					if err := c.Get(context.Background(), client.ObjectKeyFromObject(f.claim(i, "32Gi")), &corev1.PersistentVolumeClaim{}); err != nil {
						t.Fatal("deleted before endpoint handoff")
					}
				}
				for pass := 0; pass < 3; pass++ {
					if _, err := r.reconcileDataStorageResize(context.Background(), f.instance); err != nil {
						t.Fatal(err)
					}
				}
			}
			for i := 0; i < int(replicas(f.instance)); i++ {
				err := c.Get(context.Background(), types.NamespacedName{Name: f.claim(i, "32Gi").Name, Namespace: f.instance.Namespace}, &corev1.PersistentVolumeClaim{})
				if (err != nil) != (tc.wantDelete && i == tc.sourceOrdinal) {
					t.Fatalf("claim %d deletion=%v, want %v", i, err, tc.wantDelete && i == tc.sourceOrdinal)
				}
			}
			if tc.wantDelete {
				got := &appsv1.StatefulSet{}
				if err := c.Get(context.Background(), client.ObjectKeyFromObject(sts), got); err != nil {
					t.Fatal(err)
				}
				if got.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType || got.Annotations[resizeRolloutHoldAnnotation] == "" {
					t.Fatal("donor not held")
				}
			}
		})
	}
}

func TestLVMMigrationCanRecreateItsOrphanedStatefulSet(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = kurav1.AddToScheme(scheme)
	f := newResizeHoldFixture(100)
	f.instance.Spec.DiskResource = string(kuraDiskResource)
	f.instance.Spec.NodeSelector = map[string]string{"pool": "cache"}
	claim := f.claim(0, "32Gi")
	claim.Spec.VolumeName = "legacy-pv"
	pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: claim.Spec.VolumeName}, Spec: corev1.PersistentVolumeSpec{
		NodeAffinity: &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: corev1.LabelHostname, Operator: corev1.NodeSelectorOpIn, Values: []string{"source"}}}}}}},
	}}
	source := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "source", Annotations: map[string]string{lvmMigrationNodeAnnotation: "true"}}, Spec: corev1.NodeSpec{Unschedulable: true}}
	landing := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "landing", Labels: map[string]string{"pool": "cache"}}, Status: corev1.NodeStatus{
		Allocatable: corev1.ResourceList{kuraDiskResource: resource.MustParse("64Gi")},
		Conditions:  []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
	}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(f.instance, claim, pv, source, landing).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme}
	allowed, err := r.lvmMigrationAllowed(context.Background(), f.instance, dataVolumeReplacement{claim: claim})
	if err != nil || !allowed {
		t.Fatalf("orphaned immutable-template replacement cannot resume: allowed=%v err=%v", allowed, err)
	}
}

func TestLVMHandoverMovesClientAndPeerRoles(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = kurav1.AddToScheme(scheme)
	f := newResizeHoldFixture(100)
	f.instance.Spec.DiskResource = string(kuraDiskResource)
	old, next := f.servingPod(0, "100m"), f.servingPod(1, "100m")
	old.Annotations = map[string]string{lvmRebuildAnnotation: "true"}
	primary := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: f.instance.Name, Namespace: f.instance.Namespace}, Spec: corev1.ServiceSpec{Selector: map[string]string{podNameLabel: old.Name}}}
	peer := primary.DeepCopy()
	peer.Name = instancePublicPeerServiceName(f.instance)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(primary, peer).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme}
	pods := []corev1.Pod{*old, *next}
	samples := map[string]runtimeStatus{}
	for _, pod := range pods {
		samples[pod.Name] = runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: backfillCycleComplete}
	}
	selected, leaving, err := r.selectPrimaryPod(context.Background(), f.instance, pods, samples)
	if err != nil || selected != next.Name {
		t.Fatalf("primary=%q err=%v", selected, err)
	}
	gateway, err := r.selectGatewayPod(context.Background(), f.instance, pods, samples, selected, leaving)
	if err != nil || gateway != next.Name {
		t.Fatalf("gateway=%q err=%v", gateway, err)
	}
	// A role decision alone cannot authorize deleting the former holder.
	ready, err := r.lvmHandoverReady(context.Background(), f.instance, 0)
	// Missing pods are already gone; use the real pod below to exercise endpoints.
	if err != nil || !ready {
		t.Fatal(err)
	}
	if err := c.Create(context.Background(), old); err != nil {
		t.Fatal(err)
	}
	ready, err = r.lvmHandoverReady(context.Background(), f.instance, 0)
	if err != nil || ready {
		t.Fatalf("handover without observed endpoints: ready=%v err=%v", ready, err)
	}
}

func TestLVMEnrollmentKeepsReconcilingUnselectedInstances(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	f := newResizeHoldFixture(100)
	f.instance.Spec.StorageClassName = localPathStorageClass
	sharedSecret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: f.instance.Namespace, ResourceVersion: "1"}}
	box := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "legacy-box", Labels: map[string]string{"node.cluster.x-k8s.io/pool": "kura"}}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	objects := []client.Object{f.instance, sharedSecret, box}
	for i := 0; i < 2; i++ {
		claim := f.claim(i, "32Gi")
		claim.Spec.StorageClassName = ptr(localPathStorageClass)
		claim.Spec.VolumeName = fmt.Sprintf("legacy-pv-%d", i)
		claim.Status.Phase = corev1.ClaimBound
		pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: claim.Spec.VolumeName}, Spec: corev1.PersistentVolumeSpec{
			NodeAffinity: &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: corev1.LabelHostname, Operator: corev1.NodeSelectorOpIn, Values: []string{box.Name}}}}}}},
		}}
		objects = append(objects, claim, pv)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).WithStatusSubresource(f.instance).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme}
	request := ctrl.Request{NamespacedName: client.ObjectKeyFromObject(f.instance)}
	if _, err := r.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	legacy := &appsv1.StatefulSet{}
	if err := c.Get(ctx, request.NamespacedName, legacy); err != nil {
		t.Fatal(err)
	}

	// Regional enrollment flips every instance in the region at once, but only
	// the selected node's claims may move. An image release must still roll out.
	instance := &kurav1.KuraInstance{}
	if err := c.Get(ctx, request.NamespacedName, instance); err != nil {
		t.Fatal(err)
	}
	instance.Spec.StorageClassName = encryptedLocalStorageClass
	instance.Spec.DiskResource = string(kuraDiskResource)
	instance.Spec.Image = "ghcr.io/tuist/kura:0.5.3"
	if err := c.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}

	got := &appsv1.StatefulSet{}
	if err := c.Get(ctx, request.NamespacedName, got); err != nil {
		t.Fatal(err)
	}
	var kura corev1.Container
	for _, container := range got.Spec.Template.Spec.Containers {
		if container.Name == kuraContainerName {
			kura = container
		}
	}
	if kura.Image != "ghcr.io/tuist/kura:0.5.3" {
		t.Fatalf("held instance stopped reconciling: image = %q", kura.Image)
	}
	if _, requested := kura.Resources.Requests[kuraDiskResource]; requested {
		t.Fatal("held template requests LVM capacity on an unconverted host")
	}
	if got := kura.Resources.Requests[corev1.ResourceEphemeralStorage]; got.Cmp(resource.MustParse("32Gi")) != 0 {
		t.Fatalf("held template disk request = %s, want the legacy 32Gi", got.String())
	}
	if !reflect.DeepEqual(got.Spec.VolumeClaimTemplates, legacy.Spec.VolumeClaimTemplates) || !reflect.DeepEqual(got.Spec.Template.Spec.NodeSelector, legacy.Spec.Template.Spec.NodeSelector) {
		t.Fatal("held template changed its storage placement")
	}
	for i := 0; i < 2; i++ {
		if err := c.Get(ctx, client.ObjectKeyFromObject(f.claim(i, "32Gi")), &corev1.PersistentVolumeClaim{}); err != nil {
			t.Fatalf("legacy claim %d removed without node selection: %v", i, err)
		}
	}
	if err := c.Get(ctx, request.NamespacedName, instance); err != nil {
		t.Fatal(err)
	}
	if instance.Status.LastReconciledAt == nil {
		t.Fatal("held instance status was never reconciled")
	}
}

func TestLVMEnrollmentKeepsAPartlyMigratedInstanceOnItsResizeHold(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	f := newResizeHoldFixture(100)
	f.instance.Spec.StorageClassName = encryptedLocalStorageClass
	f.instance.Spec.DiskResource = string(kuraDiskResource)
	sharedSecret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: f.instance.Namespace, ResourceVersion: "1"}}
	box := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box", Labels: map[string]string{"node.cluster.x-k8s.io/pool": "kura"}}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	objects := []client.Object{f.instance, sharedSecret, box}
	statuses := map[string]runtimeStatus{}
	for i := 0; i < 2; i++ {
		claim := f.claim(i, "32Gi")
		claim.Spec.StorageClassName = ptr(encryptedLocalStorageClass)
		claim.Spec.VolumeName = fmt.Sprintf("pv-%d", i)
		claim.Status.Phase = corev1.ClaimBound
		backing := "lvm"
		if i == 1 {
			backing = "file"
		}
		pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: claim.Spec.VolumeName}, Spec: corev1.PersistentVolumeSpec{
			PersistentVolumeSource: corev1.PersistentVolumeSource{CSI: &corev1.CSIPersistentVolumeSource{Driver: "kura-volumes.tuist.dev", VolumeHandle: claim.Spec.VolumeName, VolumeAttributes: map[string]string{"backing": backing}}},
			NodeAffinity:           &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: encryptedLocalTopologyKey, Operator: corev1.NodeSelectorOpIn, Values: []string{box.Name}}}}}}},
		}}
		pod := f.servingPod(i, "100m")
		pod.Spec.NodeName = box.Name
		pod.Status.PodIP = fmt.Sprintf("10.0.0.%d", i+1)
		pod.Labels[appsv1.ControllerRevisionHashLabelKey] = "current"
		statuses[pod.Name] = runtimeStatus{Ready: true, State: "serving", BackfillInitialCycle: backfillCycleComplete, ConnectionIncarnation: "boot"}
		objects = append(objects, claim, pv, pod)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).WithStatusSubresource(f.instance, &appsv1.StatefulSet{}).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}, PublicConnectionRetirer: stubConnectionRetirer{ready: true}}
	if err := r.applyStatefulSet(ctx, f.instance, true); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	if err := c.Get(ctx, client.ObjectKeyFromObject(f.instance), sts); err != nil {
		t.Fatal(err)
	}
	sts.Status.UpdateRevision = "current"
	if err := c.Status().Update(ctx, sts); err != nil {
		t.Fatal(err)
	}

	// Ordinal 0 already moved; ordinal 1 waits because no source node is
	// selected. Releasing the hold would roll it onto LVM capacity its host
	// does not have.
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: client.ObjectKeyFromObject(f.instance)}); err != nil {
		t.Fatal(err)
	}
	if err := c.Get(ctx, client.ObjectKeyFromObject(f.instance), sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType || sts.Annotations[resizeRolloutHoldAnnotation] == "" {
		t.Fatalf("partly migrated instance released its hold: %+v", sts.Spec.UpdateStrategy)
	}
	if err := c.Get(ctx, client.ObjectKeyFromObject(f.claim(1, "32Gi")), &corev1.PersistentVolumeClaim{}); err != nil {
		t.Fatalf("legacy claim removed without node selection: %v", err)
	}
}
