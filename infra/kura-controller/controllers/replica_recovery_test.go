package controllers

import (
	"context"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	coordinationv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func TestReplicaRecoveryResumesJournalAndPreservesSurvivor(t *testing.T) {
	ctx := context.Background()
	authority, instance, samples := authorityFixture(t)
	r := &KuraInstanceReconciler{Client: authority.Client, Scheme: authority.Scheme()}
	request := kurav1alpha1.ReplicaRecoveryRequest{ID: "lost-host", PodName: "test-0", PodUID: "test-0", PVCUID: "claim-0", PVUID: "volume-0", HostName: "host-test-0", FenceEvidence: "provider power-off receipt"}
	instance.Spec.ReplicaRecovery = &request
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	instance.Status.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryStatus{Request: request, Phase: "Quarantining", SourceIncarnation: "process-test-1", SourcePod: "test-1", SourceUID: "test-1", PVCName: "data-test-0", PVName: "volume-0"}
	if err := r.Status().Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, ordinal := range []string{"0", "1"} {
		if err := r.Create(ctx, &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-" + ordinal, Namespace: "test", UID: types.UID("claim-" + ordinal)}, Spec: corev1.PersistentVolumeClaimSpec{VolumeName: "volume-" + ordinal}}); err != nil {
			t.Fatal(err)
		}
		if err := r.Create(ctx, &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: "volume-" + ordinal, UID: types.UID("volume-" + ordinal)}, Spec: corev1.PersistentVolumeSpec{PersistentVolumeReclaimPolicy: corev1.PersistentVolumeReclaimDelete}}); err != nil {
			t.Fatal(err)
		}
	}
	for range 4 {
		// Reconstruct the reconciler each pass, just as after a leader restart.
		r = &KuraInstanceReconciler{Client: authority.Client, Scheme: authority.Scheme()}
		if err := r.Get(ctx, client.ObjectKeyFromObject(instance), instance); err != nil {
			t.Fatal(err)
		}
		pods := &corev1.PodList{}
		if err := r.List(ctx, pods, client.InNamespace("test")); err != nil {
			t.Fatal(err)
		}
		if handled, err := r.reconcileReplicaRecovery(ctx, instance, pods.Items, samples, "test-1"); !handled || err != nil {
			t.Fatalf("handled=%v error=%v", handled, err)
		}
	}
	survivor := &corev1.Pod{}
	if err := r.Get(ctx, types.NamespacedName{Name: "test-1", Namespace: "test"}, survivor); err != nil || survivor.UID != "test-1" {
		t.Fatalf("survivor changed: %v", err)
	}
	claim := &corev1.PersistentVolumeClaim{}
	if err := r.Get(ctx, types.NamespacedName{Name: "data-test-1", Namespace: "test"}, claim); err != nil || claim.UID != "claim-1" {
		t.Fatalf("survivor claim changed: %v", err)
	}
	pv := &corev1.PersistentVolume{}
	if err := r.Get(ctx, types.NamespacedName{Name: "volume-1"}, pv); err != nil || pv.Spec.PersistentVolumeReclaimPolicy != corev1.PersistentVolumeReclaimDelete || len(pv.Annotations) > 0 {
		t.Fatalf("survivor volume changed: %v", err)
	}
	if err := r.Get(ctx, types.NamespacedName{Name: "volume-0"}, pv); err != nil || pv.Spec.PersistentVolumeReclaimPolicy != corev1.PersistentVolumeReclaimRetain || pv.Annotations[recoveryQuarantine] != "instance/lost-host" {
		t.Fatalf("failed volume not quarantined: %v", err)
	}
	if instance.Status.ReplicaRecovery.Phase != "Rebuilding" {
		t.Fatal(instance.Status.ReplicaRecovery)
	}
	instance.Spec.NodeSelector = map[string]string{"pool": "available"}
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	replacement := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "test-0", Namespace: "test", UID: "replacement"}, Spec: corev1.PodSpec{NodeSelector: map[string]string{"pool": "paused"}}, Status: corev1.PodStatus{Phase: corev1.PodPending}}
	if err := r.Create(ctx, replacement); err != nil {
		t.Fatal(err)
	}
	replacementClaim := &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-0", Namespace: "test", UID: "replacement-claim"}}
	if err := r.Create(ctx, replacementClaim); err != nil {
		t.Fatal(err)
	}
	if _, err := r.reconcileReplicaRecovery(ctx, instance, []corev1.Pod{*replacement, *survivor}, samples, "test-1"); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(replacement), &corev1.Pod{}); !apierrors.IsNotFound(err) {
		t.Fatalf("obsolete unscheduled replacement was not recreated: %v", err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(replacementClaim), replacementClaim); err != nil || replacementClaim.UID != "replacement-claim" {
		t.Fatalf("new replacement claim changed: %v", err)
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil || sts.Spec.Template.Spec.NodeSelector["pool"] != "available" {
		t.Fatalf("recovery did not resume placement: %v", err)
	}
}

func TestRecoverySlotSurvivesRestartAndNeverExpiresIntoAnotherRebuild(t *testing.T) {
	authority, instance, _ := authorityFixture(t)
	r := &KuraInstanceReconciler{Client: authority.Client}
	ctx := context.Background()
	if err := r.acquireRecoverySlot(ctx, instance, "first"); err != nil {
		t.Fatal(err)
	}
	r = &KuraInstanceReconciler{Client: authority.Client}
	if err := r.acquireRecoverySlot(ctx, instance, "first"); err != nil {
		t.Fatal(err)
	}
	if err := r.acquireRecoverySlot(ctx, instance, "second"); err == nil {
		t.Fatal("overlapping rebuild admitted")
	}
	if err := r.releaseRecoverySlot(ctx, instance, "other"); err != nil {
		t.Fatal(err)
	}
	if err := r.acquireRecoverySlot(ctx, instance, "second"); err == nil {
		t.Fatal("unrelated recovery released slot")
	}
	if err := r.releaseRecoverySlot(ctx, instance, "first"); err != nil {
		t.Fatal(err)
	}
	if err := r.acquireRecoverySlot(ctx, instance, "second"); err != nil {
		t.Fatal(err)
	}
}

func recoveryFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, map[string]runtimeStatus) {
	t.Helper()
	authority, instance, samples := authorityFixture(t)
	r := &KuraInstanceReconciler{Client: authority.Client, Scheme: authority.Scheme()}
	instance.Spec.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryRequest{ID: "lost-host", PodName: "test-0", PodUID: "test-0", PVCUID: "claim-0", PVUID: "volume-0", HostName: "host-test-0", FenceEvidence: "provider power-off receipt"}
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "test", UID: "statefulset"}}
	if err := r.Create(context.Background(), sts); err != nil {
		t.Fatal(err)
	}
	for _, ordinal := range []string{"0", "1"} {
		claim := &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-" + ordinal, Namespace: "test", UID: types.UID("claim-" + ordinal)}, Spec: corev1.PersistentVolumeClaimSpec{VolumeName: "volume-" + ordinal}}
		pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: "volume-" + ordinal, UID: types.UID("volume-" + ordinal)}, Spec: corev1.PersistentVolumeSpec{PersistentVolumeReclaimPolicy: corev1.PersistentVolumeReclaimDelete, ClaimRef: &corev1.ObjectReference{UID: claim.UID}, NodeAffinity: &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: corev1.LabelHostname, Operator: corev1.NodeSelectorOpIn, Values: []string{"host-test-" + ordinal}}}}}}}}}
		if err := r.Create(context.Background(), claim); err != nil {
			t.Fatal(err)
		}
		if err := r.Create(context.Background(), pv); err != nil {
			t.Fatal(err)
		}
	}
	return r, instance, samples
}

func pendingRecoveryPod(uid string) *corev1.Pod {
	return &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "test-0", Namespace: "test", UID: types.UID(uid), OwnerReferences: []metav1.OwnerReference{{APIVersion: "apps/v1", Kind: "StatefulSet", Name: "test", UID: "statefulset", Controller: ptr(true)}}}, Spec: corev1.PodSpec{Volumes: []corev1.Volume{{Name: "data", VolumeSource: corev1.VolumeSource{PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{ClaimName: "data-test-0"}}}}}, Status: corev1.PodStatus{Phase: corev1.PodPending}}
}

func replaceRecoveryPod(t *testing.T, r *KuraInstanceReconciler, pod *corev1.Pod) {
	t.Helper()
	old := &corev1.Pod{}
	key := types.NamespacedName{Name: "test-0", Namespace: "test"}
	if err := r.Get(context.Background(), key, old); err == nil {
		if err := r.Delete(context.Background(), old); err != nil {
			t.Fatal(err)
		}
	} else if !apierrors.IsNotFound(err) {
		t.Fatal(err)
	}
	if pod != nil {
		if err := r.Create(context.Background(), pod); err != nil {
			t.Fatal(err)
		}
	}
}

func recoveryStep(r *KuraInstanceReconciler, instance *kurav1alpha1.KuraInstance, samples map[string]runtimeStatus) error {
	ctx := context.Background()
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), instance); err != nil {
		return err
	}
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace)); err != nil {
		return err
	}
	_, err := r.reconcileReplicaRecovery(ctx, instance, pods.Items, samples, "test-1")
	return err
}

func TestReplicaRecoveryHandlesPodGCBeforeAndDuringJournal(t *testing.T) {
	for _, timing := range []string{"before", "during", "absent"} {
		t.Run(timing, func(t *testing.T) {
			ctx := context.Background()
			r, instance, samples := recoveryFixture(t)
			if timing == "before" {
				replaceRecoveryPod(t, r, pendingRecoveryPod("pending-1"))
			}
			if timing == "absent" {
				replaceRecoveryPod(t, r, nil)
			}
			if err := recoveryStep(r, instance, samples); err != nil {
				t.Fatal(err)
			}
			if instance.Status.ReplicaRecovery == nil || instance.Status.ReplicaRecovery.Request.PodUID != "test-0" {
				t.Fatal("original fence identity not persisted")
			}
			if timing == "before" && instance.Status.ReplicaRecovery.TargetPodUID != "pending-1" {
				t.Fatal("replacement deletion identity not persisted")
			}
			if timing == "during" {
				replaceRecoveryPod(t, r, pendingRecoveryPod("pending-1"))
			}
			for range 2 {
				if err := recoveryStep(r, instance, samples); err != nil {
					t.Fatal(err)
				}
			}
			if timing == "before" {
				replaceRecoveryPod(t, r, pendingRecoveryPod("pending-2"))
			}
			if timing != "absent" {
				if err := recoveryStep(r, instance, samples); err != nil {
					t.Fatal(err)
				}
				// Changed pod identity must be journaled without deleting it in that pass.
				pod := &corev1.Pod{}
				if err := r.Get(ctx, types.NamespacedName{Name: "test-0", Namespace: "test"}, pod); err != nil {
					t.Fatal(err)
				}
				if instance.Status.ReplicaRecovery.TargetPodUID != string(pod.UID) || instance.Status.ReplicaRecovery.Phase != "DeletingPod" {
					t.Fatal("replacement identity not persisted before deletion")
				}
			}
			// Resume with a new controller, using only the persisted journal.
			r = &KuraInstanceReconciler{Client: r.Client, Scheme: r.Scheme}
			if err := recoveryStep(r, instance, samples); err != nil {
				t.Fatal(err)
			}
			if instance.Status.ReplicaRecovery.Phase != "Rebuilding" {
				t.Fatal(instance.Status.ReplicaRecovery)
			}
			if err := r.Get(ctx, types.NamespacedName{Name: "test-0", Namespace: "test"}, &corev1.Pod{}); !apierrors.IsNotFound(err) {
				t.Fatalf("target still exists: %v", err)
			}
			for _, object := range []client.Object{&corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "test-1", Namespace: "test"}}, &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-1", Namespace: "test"}}, &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: "volume-1"}}} {
				if err := r.Get(ctx, client.ObjectKeyFromObject(object), object); err != nil {
					t.Fatalf("survivor changed: %v", err)
				}
			}
			pv := &corev1.PersistentVolume{}
			if err := r.Get(ctx, types.NamespacedName{Name: "volume-0"}, pv); err != nil || pv.Spec.PersistentVolumeReclaimPolicy != corev1.PersistentVolumeReclaimRetain {
				t.Fatalf("old volume not retained: %v", err)
			}
		})
	}
}

func TestInvalidRecoveryDoesNotReserveSlotAndCorrectedRequestCanStart(t *testing.T) {
	for _, invalid := range []string{"claim", "volume", "host", "scheduled-replacement", "wrong-claim", "wrong-owner"} {
		t.Run(invalid, func(t *testing.T) {
			r, instance, samples := recoveryFixture(t)
			original := *instance.Spec.ReplicaRecovery
			pod := pendingRecoveryPod("pending")
			switch invalid {
			case "claim":
				instance.Spec.ReplicaRecovery.PVCUID = "wrong"
			case "volume":
				instance.Spec.ReplicaRecovery.PVUID = "wrong"
			case "host":
				instance.Spec.ReplicaRecovery.HostName = "wrong"
			case "scheduled-replacement":
				pod.Spec.NodeName = "other-host"
			case "wrong-claim":
				pod.Spec.Volumes[0].PersistentVolumeClaim.ClaimName = "other-claim"
			case "wrong-owner":
				pod.OwnerReferences[0].UID = "other-statefulset"
			}
			replaceRecoveryPod(t, r, pod)
			if err := r.Update(context.Background(), instance); err != nil {
				t.Fatal(err)
			}
			if err := recoveryStep(r, instance, samples); err == nil {
				t.Fatal("invalid request accepted")
			}
			if err := r.Get(context.Background(), types.NamespacedName{Name: "kura-replica-recovery", Namespace: "test"}, &coordinationv1.Lease{}); !apierrors.IsNotFound(err) {
				t.Fatalf("invalid request reserved slot: %v", err)
			}
			if instance.Status.ReplicaRecovery != nil {
				t.Fatal("invalid request created journal")
			}
			original.ID = "corrected"
			instance.Spec.ReplicaRecovery = &original
			if err := r.Update(context.Background(), instance); err != nil {
				t.Fatal(err)
			}
			replaceRecoveryPod(t, r, pendingRecoveryPod("corrected-pending"))
			for range 2 {
				if err := recoveryStep(r, instance, samples); err != nil {
					t.Fatal(err)
				}
			}
			lease := &coordinationv1.Lease{}
			if err := r.Get(context.Background(), types.NamespacedName{Name: "kura-replica-recovery", Namespace: "test"}, lease); err != nil || lease.Spec.HolderIdentity == nil || *lease.Spec.HolderIdentity != "instance/corrected" {
				t.Fatalf("corrected request did not acquire slot: %v", err)
			}
		})
	}
}

func TestStaleColocatedStorageKeepsLegacyRecoveryAndActivatedHold(t *testing.T) {
	for _, mode := range []string{"legacy", "activated", "rollback-floor"} {
		t.Run(mode, func(t *testing.T) {
			r, instance, _ := recoveryFixture(t)
			instance.Spec.ReplicaRecovery = nil
			if mode != "activated" {
				instance.Spec.ServingMode = ""
			}
			if mode == "legacy" {
				instance.Annotations = nil
			}
			for _, ordinal := range []string{"0", "1"} {
				claim := &corev1.PersistentVolumeClaim{}
				if err := r.Get(context.Background(), types.NamespacedName{Name: "data-test-" + ordinal, Namespace: "test"}, claim); err != nil {
					t.Fatal(err)
				}
				claim.Status.Phase = corev1.ClaimBound
				if err := r.Status().Update(context.Background(), claim); err != nil {
					t.Fatal(err)
				}
				pv := &corev1.PersistentVolume{}
				if err := r.Get(context.Background(), types.NamespacedName{Name: "volume-" + ordinal}, pv); err != nil {
					t.Fatal(err)
				}
				pv.Spec.NodeAffinity.Required.NodeSelectorTerms[0].MatchExpressions[0].Values = []string{"deleted-shared-host"}
				if err := r.Update(context.Background(), pv); err != nil {
					t.Fatal(err)
				}
			}
			handled, err := r.reconcileStaleDataStorage(context.Background(), instance)
			if err != nil || !handled {
				t.Fatalf("handled=%v error=%v", handled, err)
			}
			for _, object := range []client.Object{&appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "test"}}, &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "test-0", Namespace: "test"}}, &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "test-1", Namespace: "test"}}, &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-0", Namespace: "test"}}, &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-1", Namespace: "test"}}} {
				err := r.Get(context.Background(), client.ObjectKeyFromObject(object), object)
				if mode == "legacy" {
					if !apierrors.IsNotFound(err) {
						t.Fatalf("legacy storage not recreated: %T %v", object, err)
					}
				} else if err != nil {
					t.Fatalf("activated storage removed: %T %v", object, err)
				}
				if sts, ok := object.(*appsv1.StatefulSet); ok && mode != "legacy" && (sts.Annotations[recoveryRolloutHold] != "true" || sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType) {
					t.Fatal("activated rollout not held")
				}
			}
			if mode == "legacy" {
				if handled, err := r.reconcileStaleDataStorage(context.Background(), instance); err != nil || handled {
					t.Fatalf("legacy recovery remained stuck: %v %v", handled, err)
				}
			}
		})
	}
}

func TestRecoveryNeverDeletesScheduledReplacementOrUnlocksWithdrawnJournal(t *testing.T) {
	r, instance, samples := recoveryFixture(t)
	replaceRecoveryPod(t, r, pendingRecoveryPod("pending"))
	for range 3 {
		if err := recoveryStep(r, instance, samples); err != nil {
			t.Fatal(err)
		}
	}
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "test-0", Namespace: "test"}, pod); err != nil {
		t.Fatal(err)
	}
	pod.Spec.NodeName = "new-host"
	if err := r.Update(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if err := recoveryStep(r, instance, samples); err == nil {
		t.Fatal("scheduled replacement accepted for deletion")
	}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(pod), pod); err != nil {
		t.Fatal("scheduled replacement deleted", err)
	}
	instance.Spec.ReplicaRecovery = nil
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	if err := recoveryStep(r, instance, samples); err == nil {
		t.Fatal("withdrawn in-flight request accepted")
	}
	if err := r.acquireRecoverySlot(context.Background(), instance, "other"); err == nil {
		t.Fatal("withdrawal released an in-flight rebuild slot")
	}
}
