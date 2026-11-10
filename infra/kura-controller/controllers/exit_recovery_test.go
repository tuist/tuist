package controllers

import (
	"context"
	"encoding/json"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestRequestExitRecovery(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = kurav1alpha1.AddToScheme(scheme)
	exited := servingHolder{InstanceUID: "instance", PodUID: "old-pod-uid-0", Incarnation: "incarnation-exited-0", Host: "host-0"}
	promoted := servingGrant{Epoch: 6, Phase: "Serving", PodName: "test-1", Holder: servingHolder{InstanceUID: "instance", PodUID: "pod-1", Incarnation: "incarnation-1", Host: "host-1"},
		FenceEvidence: "kubelet reported the exit", ExitPromotedFrom: &exited}
	build := func(t *testing.T, grant servingGrant, mutate func(*kurav1alpha1.KuraInstance)) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, []corev1.Pod) {
		t.Helper()
		instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "test", UID: "instance", Annotations: map[string]string{servingRollbackFloor: servingMode}}, Spec: kurav1alpha1.KuraInstanceSpec{ServingMode: servingMode, Replicas: ptr(int32(2))}}
		if mutate != nil {
			mutate(instance)
		}
		data, _ := json.Marshal(grant)
		pods := []corev1.Pod{
			{ObjectMeta: metav1.ObjectMeta{Name: "test-0", Namespace: "test", UID: "old-pod-uid-0"}, Spec: corev1.PodSpec{NodeName: "host-0"}},
			{ObjectMeta: metav1.ObjectMeta{Name: "test-1", Namespace: "test", UID: "pod-1"}, Spec: corev1.PodSpec{NodeName: "host-1"}},
		}
		objects := []client.Object{instance,
			&corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "test-serving", Namespace: "test"}, Data: map[string]string{"grant": string(data)}},
			&corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-test-0", Namespace: "test", UID: "claim-0"}, Spec: corev1.PersistentVolumeClaimSpec{VolumeName: "volume-0"}},
			&corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: "volume-0", UID: "volume-uid-0"}},
		}
		c := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance).WithObjects(objects...).Build()
		return &KuraInstanceReconciler{Client: c, Scheme: scheme}, instance, pods
	}
	request := func(t *testing.T, r *KuraInstanceReconciler, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) *kurav1alpha1.ReplicaRecoveryRequest {
		t.Helper()
		if err := r.requestExitRecovery(context.Background(), instance, pods); err != nil {
			t.Fatal(err)
		}
		fresh := &kurav1alpha1.KuraInstance{}
		if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), fresh); err != nil {
			t.Fatal(err)
		}
		*instance = *fresh
		return fresh.Spec.ReplicaRecovery
	}

	t.Run("requests the exited ordinal's recovery with its exact identities", func(t *testing.T) {
		r, instance, pods := build(t, promoted, nil)
		got := request(t, r, instance, pods)
		want := kurav1alpha1.ReplicaRecoveryRequest{ID: "exit-old-pod--exited-0", PodName: "test-0", PodUID: "old-pod-uid-0", PVCUID: "claim-0", PVUID: "volume-uid-0", HostName: "host-0", FenceEvidence: "kubelet reported the exit"}
		if got == nil || *got != want {
			t.Fatalf("got %+v", got)
		}
		if again := request(t, r, instance, pods); *again != want {
			t.Fatal("the request changed on a second pass", again)
		}
	})

	t.Run("replaces a verified earlier recovery", func(t *testing.T) {
		old := kurav1alpha1.ReplicaRecoveryRequest{ID: "operator-oct19"}
		r, instance, pods := build(t, promoted, func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.ReplicaRecovery = &old
			instance.Status.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryStatus{Phase: "Verified", Request: old}
		})
		if got := request(t, r, instance, pods); got == nil || got.ID == old.ID {
			t.Fatal("a verified earlier recovery blocked the new one", got)
		}
	})

	for name, setup := range map[string]struct {
		grant  servingGrant
		mutate func(*kurav1alpha1.KuraInstance)
	}{
		"an operator recovery in progress": {promoted, func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryRequest{ID: "operator"}
			instance.Status.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryStatus{Phase: "Rebuilding", Request: *instance.Spec.ReplicaRecovery}
		}},
		"an operator request not yet started": {promoted, func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryRequest{ID: "operator"}
		}},
		"a grant without an exit promotion": {func() servingGrant { g := promoted; g.ExitPromotedFrom = nil; return g }(), nil},
		"a grant that is not serving":       {func() servingGrant { g := promoted; g.Phase = "Fencing"; return g }(), nil},
		"an exited pod already replaced": {func() servingGrant {
			g := promoted
			other := exited
			other.PodUID = "replaced-pod-uid"
			g.ExitPromotedFrom = &other
			return g
		}(), nil},
	} {
		t.Run("leaves "+name+" alone", func(t *testing.T) {
			r, instance, pods := build(t, setup.grant, setup.mutate)
			before := instance.Spec.ReplicaRecovery
			got := request(t, r, instance, pods)
			if (before == nil) != (got == nil) || (got != nil && got.ID != before.ID) {
				t.Fatal("an automatic request replaced or added a recovery", got)
			}
		})
	}
}
