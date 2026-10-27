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
	}{
		{name: "same class legacy file rebuilds one replica", colocated: true, backing: "file", cycle: backfillCycleComplete, wantDelete: true},
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
			f.instance.Spec.DiskResource = string(kuraDiskResource)
			if tc.single {
				f.instance.Spec.Replicas = ptr(int32(1))
			}
			sts := f.statefulSet(rollingUpdate(), "100m", nil)
			if tc.paused {
				sts.Spec.UpdateStrategy = onDelete()
			}
			sts.Spec.VolumeClaimTemplates[0].Spec.StorageClassName = ptr(encryptedLocalStorageClass)
			sts.Spec.Template.Spec.Containers[0].Resources.Requests[kuraDiskResource] = resource.MustParse("32Gi")
			templateHeld := tc.skipMark || tc.noLanding || tc.uncordoned || tc.multiple || tc.otherLegacy
			if templateHeld {
				delete(sts.Spec.Template.Spec.Containers[0].Resources.Requests, kuraDiskResource)
				sts.Spec.Template.Spec.Containers[0].Resources.Requests[corev1.ResourceEphemeralStorage] = resource.MustParse("32Gi")
			}
			objects := []client.Object{f.instance, sts}
			if !tc.noLanding {
				objects = append(objects, &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "prepared-spare"}, Status: corev1.NodeStatus{Allocatable: corev1.ResourceList{kuraDiskResource: resource.MustParse("64Gi")}, Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}})
			}
			statuses := map[string]runtimeStatus{}
			for i := 0; i < int(replicas(f.instance)); i++ {
				claim := f.claim(i, "32Gi")
				claim.Spec.StorageClassName = ptr(encryptedLocalStorageClass)
				claim.Spec.VolumeName = fmt.Sprintf("pv-%d", i)
				claim.Status.Phase = corev1.ClaimBound
				pod := f.servingPod(i, "100m")
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

				statuses[pod.Name] = runtimeStatus{Ready: true, BackfillInitialCycle: tc.cycle}
			}
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
			r := &KuraInstanceReconciler{Client: c, Scheme: scheme, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}}
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
				if _, err := r.reconcileDataStorageResize(context.Background(), f.instance); err != nil {
					t.Fatal(err)
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
