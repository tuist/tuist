package controllers

import (
	"context"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
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
