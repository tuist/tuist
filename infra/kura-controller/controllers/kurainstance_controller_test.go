package controllers

import (
	"context"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func TestKuraInstanceReconcileCreatesWorkloadResources(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "eu",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-eu-1.kura.tuist.dev",
			TLSSecretName:    "tuist-tls-cloudflare-origin-kura",
			StorageClassName: "hcloud-volumes",
			VolumeSizeGi:     100,
			ExtensionScript:  "return true",
		},
	}

	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme: scheme,
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, service); err != nil {
		t.Fatal(err)
	}
	if service.Spec.Ports[0].Port != httpPort {
		t.Fatalf("expected http port %d, got %d", httpPort, service.Spec.Ports[0].Port)
	}

	ingress := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, ingress); err != nil {
		t.Fatal(err)
	}
	if got := ingress.Spec.Rules[0].Host; got != "tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected ingress host, got %q", got)
	}
	if got := ingress.Spec.TLS[0].SecretName; got != "tuist-tls-cloudflare-origin-kura" {
		t.Fatalf("expected TLS secret, got %q", got)
	}

	configMap := &corev1.ConfigMap{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: "kura-tuist-eu-1-extension", Namespace: instance.Namespace}, configMap); err != nil {
		t.Fatal(err)
	}
	if got := configMap.Data["hooks.lua"]; got != "return true" {
		t.Fatalf("expected extension script, got %q", got)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	if got := *sts.Spec.Replicas; got != 3 {
		t.Fatalf("expected default replicas, got %d", got)
	}
	container := sts.Spec.Template.Spec.Containers[0]
	env := map[string]string{}
	for _, envVar := range container.Env {
		env[envVar.Name] = envVar.Value
	}
	if got := env["KURA_EXTENSION_ENABLED"]; got != "true" {
		t.Fatalf("expected controller to enable the extension, got %q", got)
	}
	if got := container.Resources.Requests.Cpu().String(); got != "500m" {
		t.Fatalf("expected default CPU request, got %q", got)
	}
	if got := sts.Spec.Template.Annotations["kubernetes.io/ingress-bandwidth"]; got != "250M" {
		t.Fatalf("expected default ingress bandwidth, got %q", got)
	}
	if got := sts.Spec.Template.Spec.NodeSelector["node.cluster.x-k8s.io/pool"]; got != "kura" {
		t.Fatalf("expected kura node pool selector, got %q", got)
	}
	if got := *sts.Spec.VolumeClaimTemplates[0].Spec.StorageClassName; got != "hcloud-volumes" {
		t.Fatalf("expected storage class, got %q", got)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Spec.Resources.Requests.Storage().String(); got != "100Gi" {
		t.Fatalf("expected PVC size, got %q", got)
	}
}
