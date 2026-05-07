package controllers

import (
	"context"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	policyv1 "k8s.io/api/policy/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
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
			StorageClassName: "hcloud-volumes",
			ExtensionScript:  "return true",
		},
	}
	legacyIngress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}

	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, legacyIngress).WithStatusSubresource(instance).Build(),
		Scheme: scheme,
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, service); err != nil {
		t.Fatal(err)
	}
	if service.Spec.Type != corev1.ServiceTypeLoadBalancer {
		t.Fatalf("expected public service to be a LoadBalancer, got %q", service.Spec.Type)
	}
	if service.Spec.ExternalTrafficPolicy != corev1.ServiceExternalTrafficPolicyLocal {
		t.Fatalf("expected local external traffic policy, got %q", service.Spec.ExternalTrafficPolicy)
	}
	if got := service.Spec.Ports[0].Port; got != httpsPort {
		t.Fatalf("expected public service port %d, got %d", httpsPort, got)
	}
	if got := service.Spec.Ports[0].TargetPort.StrVal; got != "http" {
		t.Fatalf("expected public service to target http, got %q", got)
	}
	if got := service.Annotations["external-dns.alpha.kubernetes.io/hostname"]; got != "tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected external-dns hostname, got %q", got)
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/protocol"]; got != "https" {
		t.Fatalf("expected Hetzner HTTPS load balancer, got %q", got)
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/http-managed-certificate-domains"]; got != "tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected Hetzner managed cert domain, got %q", got)
	}

	ingress := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, ingress); !apierrors.IsNotFound(err) {
		t.Fatalf("expected legacy ingress to be deleted, got %v", err)
	}

	pdb := &policyv1.PodDisruptionBudget{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, pdb); err != nil {
		t.Fatal(err)
	}
	if got := pdb.Spec.MinAvailable.IntVal; got != 2 {
		t.Fatalf("expected PDB minAvailable 2, got %d", got)
	}
	if got := pdb.Spec.Selector.MatchLabels["app.kubernetes.io/instance"]; got != instance.Name {
		t.Fatalf("expected PDB selector to match instance, got %q", got)
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
	if _, ok := sts.Spec.Template.Annotations["kubernetes.io/ingress-bandwidth"]; ok {
		t.Fatal("expected no default ingress bandwidth annotation")
	}
	if got := sts.Spec.Template.Spec.NodeSelector["node.cluster.x-k8s.io/pool"]; got != "kura" {
		t.Fatalf("expected kura node pool selector, got %q", got)
	}
	if got := len(sts.Spec.Template.Spec.TopologySpreadConstraints); got != 1 {
		t.Fatalf("expected one topology spread constraint, got %d", got)
	}
	if got := sts.Spec.Template.Spec.TopologySpreadConstraints[0].TopologyKey; got != "kubernetes.io/hostname" {
		t.Fatalf("expected hostname topology spread, got %q", got)
	}
	if got := sts.Spec.Template.Labels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected pod template account label, got %q", got)
	}
	if got := sts.Spec.Template.Labels["tuist.dev/region"]; got != "eu" {
		t.Fatalf("expected pod template region label, got %q", got)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Labels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected PVC account label, got %q", got)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Labels["tuist.dev/region"]; got != "eu" {
		t.Fatalf("expected PVC region label, got %q", got)
	}
	if got := *sts.Spec.VolumeClaimTemplates[0].Spec.StorageClassName; got != "hcloud-volumes" {
		t.Fatalf("expected storage class, got %q", got)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Spec.Resources.Requests.Storage().String(); got != "200Gi" {
		t.Fatalf("expected PVC size, got %q", got)
	}
}

func TestKuraInstanceSpecSupportsLocalWorkloadOverrides(t *testing.T) {
	replicas := int32(1)
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-local-controller", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "local-controller",
			Image:         "ghcr.io/tuist/kura:0.5.2",
			Replicas:      &replicas,
			NodeSelector:  map[string]string{"kubernetes.io/os": "linux"},
			StorageSize:   "10Gi",
		},
	}

	stsTemplate := podTemplate(instance)
	if got := stsTemplate.Spec.NodeSelector["kubernetes.io/os"]; got != "linux" {
		t.Fatalf("expected local node selector, got %q", got)
	}
	if _, ok := stsTemplate.Spec.NodeSelector["node.cluster.x-k8s.io/pool"]; ok {
		t.Fatalf("expected custom node selector to replace managed default")
	}

	pvc := dataVolumeClaim(instance)
	if got := pvc.Spec.Resources.Requests.Storage().String(); got != "10Gi" {
		t.Fatalf("expected local PVC size, got %q", got)
	}
}

func TestRolloutStatusRequiresUpdatedReadyReplicas(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-central-1", Generation: 2},
		Spec: kurav1alpha1.KuraInstanceSpec{
			Image: "ghcr.io/tuist/kura:0.5.3",
		},
		Status: kurav1alpha1.KuraInstanceStatus{
			ObservedImage: "ghcr.io/tuist/kura:0.5.2",
		},
	}
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Generation: 2},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: 2,
			ReadyReplicas:      3,
			UpdatedReplicas:    1,
			CurrentRevision:    "kura-abc",
			UpdateRevision:     "kura-def",
		},
	}

	status := rolloutStatusFromStatefulSet(instance, sts)

	if status.phase != "Pending" {
		t.Fatalf("expected rollout to remain pending, got %q", status.phase)
	}
	if status.observedImage != "ghcr.io/tuist/kura:0.5.2" {
		t.Fatalf("expected observed image to stay on previous image, got %q", status.observedImage)
	}
}

func TestRolloutStatusMarksReadyOnlyForCurrentRevision(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-central-1", Generation: 2},
		Spec: kurav1alpha1.KuraInstanceSpec{
			Image: "ghcr.io/tuist/kura:0.5.3",
		},
		Status: kurav1alpha1.KuraInstanceStatus{
			ObservedImage: "ghcr.io/tuist/kura:0.5.2",
		},
	}
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Generation: 2},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: 2,
			ReadyReplicas:      3,
			UpdatedReplicas:    3,
			CurrentRevision:    "kura-def",
			UpdateRevision:     "kura-def",
		},
	}

	status := rolloutStatusFromStatefulSet(instance, sts)

	if status.phase != "Ready" {
		t.Fatalf("expected rollout to be ready, got %q", status.phase)
	}
	if status.observedImage != "ghcr.io/tuist/kura:0.5.3" {
		t.Fatalf("expected observed image to advance, got %q", status.observedImage)
	}
}
