package controllers

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func haproxyPilotInstance() *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-ca-east-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:           "tuist",
			TenantID:                "tuist",
			Region:                  "ca-east",
			Image:                   "ghcr.io/tuist/kura:0.5.2",
			PublicHost:              "tuist-ca-east-1.kura.tuist.dev",
			IngressClassName:        "kura-ca-east",
			HAProxyIngressClassName: "kura-ca-east-haproxy",
			StorageClassName:        "scw-local-nvme",
		},
	}
}

func newHAProxyTestReconciler(t *testing.T, instance *kurav1alpha1.KuraInstance) *KuraInstanceReconciler {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	return &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).
			WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme:            scheme,
		GRPCClusterIssuer: "letsencrypt-prod",
	}
}

func TestKuraInstanceReconcileRendersHAProxyIngressPair(t *testing.T) {
	ctx := context.Background()
	instance := haproxyPilotInstance()
	reconciler := newHAProxyTestReconciler(t, instance)

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	public := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: haproxyPublicIngressName(instance), Namespace: instance.Namespace}, public); err != nil {
		t.Fatalf("expected the HAProxy public ingress to be created: %v", err)
	}
	if public.Spec.IngressClassName == nil || *public.Spec.IngressClassName != "kura-ca-east-haproxy" {
		t.Fatalf("expected the HAProxy class, got %v", public.Spec.IngressClassName)
	}
	// Same cert Secret as the nginx pair: both gateways terminate TLS for
	// the host during the side-by-side phase.
	if len(public.Spec.TLS) != 1 || public.Spec.TLS[0].SecretName != publicTLSSecretName(instance) {
		t.Fatalf("expected the HAProxy public ingress to reuse the public TLS secret, got %v", public.Spec.TLS)
	}
	if got := public.Annotations["haproxy.org/timeout-server"]; got != "3600s" {
		t.Fatalf("expected the streaming server timeout, got %q", got)
	}
	publicBackend := public.Spec.Rules[0].HTTP.Paths[0].Backend.Service
	if publicBackend == nil || publicBackend.Name != instance.Name || publicBackend.Port.Name != "http" {
		t.Fatalf("expected the public path to route to %s:http, got %#v", instance.Name, publicBackend)
	}

	grpc := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: haproxyGRPCIngressName(instance), Namespace: instance.Namespace}, grpc); err != nil {
		t.Fatalf("expected the HAProxy gRPC ingress to be created: %v", err)
	}
	if grpc.Spec.IngressClassName == nil || *grpc.Spec.IngressClassName != "kura-ca-east-haproxy" {
		t.Fatalf("expected the HAProxy class, got %v", grpc.Spec.IngressClassName)
	}
	if len(grpc.Spec.TLS) != 0 {
		t.Fatalf("expected the HAProxy gRPC ingress to declare no TLS (public covers the host), got %v", grpc.Spec.TLS)
	}
	if got := grpc.Annotations["haproxy.org/server-proto"]; got != "h2" {
		t.Fatalf("expected h2c to the co-hosted listener, got %q", got)
	}
	if got := grpc.Spec.Rules[0].Host; got != instance.Spec.PublicHost {
		t.Fatalf("expected gRPC to co-host on the public host, got %q", got)
	}
	// Unescaped begins-with prefixes: haproxytech has no regex routing and
	// would match the nginx regex escapes byte-for-byte.
	gotPaths := []string{}
	for _, p := range grpc.Spec.Rules[0].HTTP.Paths {
		gotPaths = append(gotPaths, p.Path)
		if p.PathType == nil || *p.PathType != networkingv1.PathTypeImplementationSpecific {
			t.Fatalf("expected ImplementationSpecific paths, got %v", p.PathType)
		}
		backend := p.Backend.Service
		if backend == nil || backend.Name != instance.Name || backend.Port.Name != "grpc" {
			t.Fatalf("expected the gRPC paths to route to the dedicated grpc port, got %#v", backend)
		}
	}
	wantPaths := []string{"/build.bazel.remote.execution.v2.", "/google.bytestream."}
	if len(gotPaths) != len(wantPaths) {
		t.Fatalf("expected the REAPI/ByteStream prefixes, got %v", gotPaths)
	}
	for i, want := range wantPaths {
		if gotPaths[i] != want {
			t.Fatalf("expected path %d to be %q, got %q", i, want, gotPaths[i])
		}
	}

	// The grpc Service port gives haproxytech a separate backend for the
	// h2c proto so plain HTTP keeps HTTP/1.1 (Kura's sendfile fast path).
	service := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, service); err != nil {
		t.Fatal(err)
	}
	foundGRPCPort := false
	for _, port := range service.Spec.Ports {
		if port.Name == "grpc" {
			foundGRPCPort = true
			if port.Port != grpcServicePort || port.TargetPort.String() != "http" {
				t.Fatalf("expected grpc port %d to target the co-hosted http listener, got %#v", grpcServicePort, port)
			}
		}
	}
	if !foundGRPCPort {
		t.Fatalf("expected the Service to expose a grpc port, got %#v", service.Spec.Ports)
	}
}

func TestKuraInstanceReconcileSkipsHAProxyIngressesWhenClassUnset(t *testing.T) {
	ctx := context.Background()
	instance := haproxyPilotInstance()
	instance.Spec.HAProxyIngressClassName = ""
	reconciler := newHAProxyTestReconciler(t, instance)

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	for _, name := range []string{haproxyPublicIngressName(instance), haproxyGRPCIngressName(instance)} {
		ingress := &networkingv1.Ingress{}
		if err := reconciler.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, ingress); !apierrors.IsNotFound(err) {
			t.Fatalf("expected %s to be absent without haproxyIngressClassName, got %v", name, err)
		}
	}
}

func TestKuraInstanceReconcileClearingHAProxyClassDeletesPair(t *testing.T) {
	ctx := context.Background()
	instance := haproxyPilotInstance()
	reconciler := newHAProxyTestReconciler(t, instance)
	request := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}

	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}

	updated := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(ctx, request.NamespacedName, updated); err != nil {
		t.Fatal(err)
	}
	updated.Spec.HAProxyIngressClassName = ""
	if err := reconciler.Update(ctx, updated); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}

	for _, name := range []string{haproxyPublicIngressName(instance), haproxyGRPCIngressName(instance)} {
		ingress := &networkingv1.Ingress{}
		if err := reconciler.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, ingress); !apierrors.IsNotFound(err) {
			t.Fatalf("expected %s to be deleted after clearing haproxyIngressClassName, got %v", name, err)
		}
	}
}
