package controllers

import (
	"context"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/kura-controller/internal/runnerrelay"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestRunnerRelayServiceKeepsExistingPrimaryAndOwner(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = corev1.AddToScheme(scheme)
	_ = kurav1alpha1.AddToScheme(scheme)
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-ca-east-1-m", Namespace: "kura", UID: "test-instance"}}
	client := fake.NewClientBuilder().WithScheme(scheme).Build()
	r := &KuraInstanceReconciler{Client: client, Scheme: scheme, RunnerCacheRelay: true}
	ctx := context.Background()
	for _, primary := range []string{"cache-0", "cache-1"} {
		if err := r.reconcileService(ctx, instance, primary); err != nil {
			t.Fatal(err)
		}
		alias := &corev1.Service{}
		if err := client.Get(ctx, types.NamespacedName{Namespace: "kura", Name: runnerrelay.ServiceName(instance.Name)}, alias); err != nil {
			t.Fatal(err)
		}
		if alias.Annotations[runnerrelay.BackendAnnotation] != instance.Name || alias.Spec.Selector["app.kubernetes.io/name"] != runnerrelay.App || alias.OwnerReferences[0].UID != instance.UID {
			t.Fatal("relay alias lost its instance binding")
		}
		backend := &corev1.Service{}
		if err := client.Get(ctx, types.NamespacedName{Namespace: "kura", Name: instance.Name}, backend); err != nil {
			t.Fatal(err)
		}
		if backend.Spec.Selector[podNameLabel] != primary {
			t.Fatal("relay changed primary selection")
		}
	}
}

func TestRunnerRelaySkipsPrivateInstancesAndDisabledPreparation(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		scheme := runtime.NewScheme()
		_ = corev1.AddToScheme(scheme)
		_ = kurav1alpha1.AddToScheme(scheme)
		client := fake.NewClientBuilder().WithScheme(scheme).Build()
		r := &KuraInstanceReconciler{Client: client, Scheme: scheme, RunnerCacheRelay: enabled}
		instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "private", Namespace: "kura", UID: "private"}}
		instance.Spec.Private = enabled
		if err := r.reconcileRunnerCacheRelay(context.Background(), instance); err != nil {
			t.Fatal(err)
		}
		services := &corev1.ServiceList{}
		if err := client.List(context.Background(), services); err != nil {
			t.Fatal(err)
		}
		if len(services.Items) != 0 {
			t.Fatal("created an unwanted relay alias")
		}
	}
}
