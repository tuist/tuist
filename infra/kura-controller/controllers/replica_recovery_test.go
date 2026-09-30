package controllers

import (
	"context"
	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"testing"
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
