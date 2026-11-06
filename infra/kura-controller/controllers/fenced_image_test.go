package controllers

import (
	"context"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func TestFencedImageHoldDoesNotBlockWorkloadReconciliation(t *testing.T) {
	r, instance, _ := authorityFixture(t)
	instance.Spec.Image = "requested-but-unqualified"
	instance.Annotations["kura.tuist.dev/fenced-runtime-image"] = "qualified-runtime"
	workload := &KuraInstanceReconciler{Client: r.Client, Scheme: r.Scheme()}
	if err := workload.reconcileStatefulSet(context.Background(), instance); err != nil {
		t.Fatal("image hold blocked safe workload reconciliation", err)
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), sts); err != nil {
		t.Fatal(err)
	}
	if got := podKuraImage(&corev1.Pod{Spec: sts.Spec.Template.Spec}); got != "qualified-runtime" {
		t.Fatalf("template image = %q", got)
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatal("lost fenced rollout hold")
	}
	if instance.Spec.Image != "requested-but-unqualified" {
		t.Fatal("changed requested intent")
	}
	if sts.Spec.PersistentVolumeClaimRetentionPolicy.WhenDeleted != appsv1.RetainPersistentVolumeClaimRetentionPolicyType {
		t.Fatal("lost fenced volume retention")
	}

	instance.Annotations["kura.tuist.dev/fenced-runtime-image"] = instance.Spec.Image
	if err := workload.reconcileStatefulSet(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), sts); err != nil {
		t.Fatal(err)
	}
	if got := podKuraImage(&corev1.Pod{Spec: sts.Spec.Template.Spec}); got != instance.Spec.Image {
		t.Fatalf("qualified image was not adopted: %q", got)
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatal("qualification enabled automatic replacement")
	}
}

func TestRolloutStatusReportsOperatorImageHolds(t *testing.T) {
	for _, tt := range []struct {
		name     string
		fenced   bool
		mutate   func(*appsv1.StatefulSet)
		wantHold string
	}{
		{name: "fenced instance with an old-revision pod", fenced: true, wantHold: imageHoldFencedReplacement},
		{name: "recovery hold with an old-revision pod", mutate: func(s *appsv1.StatefulSet) { s.Annotations = map[string]string{recoveryRolloutHold: "true"} }, wantHold: imageHoldRecoveryRollout},
		{name: "unannotated operator OnDelete stays visible as a stuck rollout"},
		{name: "fenced instance fully updated but not ready is a failing image", fenced: true, mutate: func(s *appsv1.StatefulSet) { s.Status.UpdatedReplicas = 2; s.Status.ReadyReplicas = 1 }},
		{name: "fenced instance on a stale template", fenced: true, mutate: func(s *appsv1.StatefulSet) { s.Spec.Template.Spec.Containers[0].Image = "ghcr.io/tuist/kura:old" }},
		{name: "fenced instance under rolling update", fenced: true, mutate: func(s *appsv1.StatefulSet) { s.Spec.UpdateStrategy.Type = appsv1.RollingUpdateStatefulSetStrategyType }},
	} {
		t.Run(tt.name, func(t *testing.T) {
			instance := &kurav1alpha1.KuraInstance{
				ObjectMeta: metav1.ObjectMeta{Annotations: map[string]string{}},
				Spec:       kurav1alpha1.KuraInstanceSpec{Image: "ghcr.io/tuist/kura:new", Replicas: ptr(int32(2))},
				Status:     kurav1alpha1.KuraInstanceStatus{ObservedImage: "ghcr.io/tuist/kura:old"},
			}
			if tt.fenced {
				instance.Annotations[servingRollbackFloor] = servingMode
				instance.Annotations["kura.tuist.dev/fenced-runtime-image"] = instance.Spec.Image
			}
			sts := &appsv1.StatefulSet{
				ObjectMeta: metav1.ObjectMeta{Generation: 2},
				Spec:       statefulSetSpecWithImage(instance.Spec.Image, appsv1.OnDeleteStatefulSetStrategyType),
				Status:     appsv1.StatefulSetStatus{ObservedGeneration: 2, Replicas: 2, ReadyReplicas: 2, UpdatedReplicas: 1, CurrentRevision: "old", UpdateRevision: "new"},
			}
			if tt.mutate != nil {
				tt.mutate(sts)
			}
			status := rolloutStatusFromStatefulSet(instance, sts)
			if status.phase != "Pending" || status.imageHold != tt.wantHold {
				t.Fatalf("got phase=%q hold=%q; want Pending hold=%q", status.phase, status.imageHold, tt.wantHold)
			}
		})
	}
}

func TestRolloutStatusReportsNoHoldOnceManuallyReplaced(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Annotations: map[string]string{servingRollbackFloor: servingMode}},
		Spec:       kurav1alpha1.KuraInstanceSpec{Image: "ghcr.io/tuist/kura:new", Replicas: ptr(int32(2))},
	}
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Generation: 2},
		Spec:       statefulSetSpecWithImage(instance.Spec.Image, appsv1.OnDeleteStatefulSetStrategyType),
		Status:     appsv1.StatefulSetStatus{ObservedGeneration: 2, Replicas: 2, ReadyReplicas: 2, UpdatedReplicas: 2, CurrentRevision: "old", UpdateRevision: "new"},
	}
	if status := rolloutStatusFromStatefulSet(instance, sts); status.phase != "Ready" || status.imageHold != "" {
		t.Fatalf("got phase=%q hold=%q", status.phase, status.imageHold)
	}
}
