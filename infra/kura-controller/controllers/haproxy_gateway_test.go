package controllers

import (
	"context"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func haproxyTestInstance() *kurav1alpha1.KuraInstance {
	instance := meshInstance("kura-acme-sa-west-1", "acme")
	instance.Spec.PublicHost = "acme-sa-west-1.kura.tuist.dev"
	instance.Spec.PublicHostNetwork = true
	instance.Spec.IngressClassName = "kura-sa-west"
	instance.Spec.HAProxyIngressClassName = "kura-sa-west-haproxy"
	return instance
}

func haproxyTestReconciler(t *testing.T, objects ...client.Object) *KuraInstanceReconciler {
	t.Helper()
	scheme := meshTestScheme(t)
	return &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build(), Scheme: scheme}
}

func getHAProxyObjects(t *testing.T, r *KuraInstanceReconciler, instance *kurav1alpha1.KuraInstance) (*corev1.Service, *networkingv1.Ingress, *networkingv1.Ingress) {
	t.Helper()
	ctx := context.Background()
	service := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Name: haproxyServiceName(instance), Namespace: instance.Namespace}, service); err != nil {
		t.Fatal(err)
	}
	public := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: haproxyIngressName(instance), Namespace: instance.Namespace}, public); err != nil {
		t.Fatal(err)
	}
	grpc := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: haproxyGRPCIngressName(instance), Namespace: instance.Namespace}, grpc); err != nil {
		t.Fatal(err)
	}
	return service, public, grpc
}

func TestHAProxyGatewayServicePublishesThePrimaryWhateverItsReadiness(t *testing.T) {
	ctx := context.Background()
	instance := haproxyTestInstance()
	r := haproxyTestReconciler(t, instance)

	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-1"); err != nil {
		t.Fatal(err)
	}

	service, _, _ := getHAProxyObjects(t, r, instance)
	if !service.Spec.PublishNotReadyAddresses {
		t.Fatal("the gateway Service must keep a primary Kubernetes marked NotReady")
	}
	if service.Spec.Selector[podNameLabel] != instance.Name+"-1" {
		t.Fatalf("expected the Service pinned to the primary, got %v", service.Spec.Selector)
	}
	if len(service.Spec.Ports) != 2 {
		t.Fatalf("expected an HTTP and a gRPC port, got %v", service.Spec.Ports)
	}
	for _, port := range service.Spec.Ports {
		if port.TargetPort.StrVal != "http" {
			t.Fatalf("port %s must target the co-hosted listener that serves /ready, got %v", port.Name, port.TargetPort)
		}
	}
	if len(service.OwnerReferences) != 1 || service.OwnerReferences[0].Name != instance.Name {
		t.Fatal("the gateway Service must be owned by its instance")
	}
}

func TestHAProxyGatewayIngressesHealthCheckAndSplitGRPC(t *testing.T) {
	ctx := context.Background()
	instance := haproxyTestInstance()
	r := haproxyTestReconciler(t, instance)

	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}

	_, public, grpc := getHAProxyObjects(t, r, instance)
	for _, ingress := range []*networkingv1.Ingress{public, grpc} {
		if *ingress.Spec.IngressClassName != "kura-sa-west-haproxy" {
			t.Fatalf("%s: wrong class %q", ingress.Name, *ingress.Spec.IngressClassName)
		}
		for key, value := range map[string]string{
			"haproxy.org/check":                                        "true",
			"haproxy.org/check-http":                                   "/ready",
			"haproxy.org/check-interval":                               "1s",
			"haproxy.org/timeout-server":                               "3600s",
			"external-dns.alpha.kubernetes.io/ingress-hostname-source": "annotation-only",
		} {
			if ingress.Annotations[key] != value {
				t.Fatalf("%s: expected %s=%s, got %q", ingress.Name, key, value, ingress.Annotations[key])
			}
		}
		if _, ok := ingress.Annotations["haproxy.org/allow-list"]; ok {
			t.Fatalf("%s: a public instance must not restrict clients", ingress.Name)
		}
	}

	if public.Annotations["haproxy.org/server-proto"] != "" {
		t.Fatal("HTTP must stay on HTTP/1.1 for Kura's sendfile path")
	}
	backend := public.Spec.Rules[0].HTTP.Paths[0].Backend.Service
	if backend.Name != haproxyServiceName(instance) || backend.Port.Name != "http" {
		t.Fatalf("public Ingress must route to the gateway Service's http port, got %+v", backend)
	}
	if len(public.Spec.TLS) != 1 || public.Spec.TLS[0].SecretName != publicTLSSecretName(instance) {
		t.Fatalf("expected the per-instance certificate without a wildcard, got %+v", public.Spec.TLS)
	}

	if grpc.Annotations["haproxy.org/server-proto"] != "h2" {
		t.Fatal("gRPC must reach Kura over h2c")
	}
	if len(grpc.Spec.TLS) != 0 {
		t.Fatal("the public Ingress terminates TLS for the shared host")
	}
	var prefixes []string
	for _, path := range grpc.Spec.Rules[0].HTTP.Paths {
		prefixes = append(prefixes, path.Path)
		if *path.PathType != networkingv1.PathTypeImplementationSpecific {
			t.Fatalf("expected begins-with matching for %s", path.Path)
		}
		if path.Backend.Service.Name != haproxyServiceName(instance) || path.Backend.Service.Port.Name != haproxyGRPCServicePort {
			t.Fatalf("gRPC must route to its own backend, got %+v", path.Backend.Service)
		}
	}
	expected := []string{
		"/build.bazel.remote.asset.v1.",
		"/build.bazel.remote.execution.v2.",
		"/google.bytestream.",
		"/google.devtools.build.v1.",
	}
	if !reflect.DeepEqual(prefixes, expected) {
		t.Fatalf("expected unescaped prefixes %v, got %v", expected, prefixes)
	}
}

func TestHAProxyGatewayServesTheSameHostsAsTheNginxGateway(t *testing.T) {
	ctx := context.Background()
	instance := haproxyTestInstance()
	instance.Spec.ClientHostAliases = []string{"acme-old-sa-west-1.kura.tuist.dev"}
	wildcard := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-public-wildcard-tls", Namespace: instance.Namespace},
		Data:       map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev")},
	}
	r := haproxyTestReconciler(t, instance, wildcard)
	r.PublicTLSSecretName = wildcard.Name

	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileGRPCIngress(ctx, instance, nil, nil, ""); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}

	nginx := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, nginx); err != nil {
		t.Fatal(err)
	}
	nginxGRPC := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: grpcServiceName(instance), Namespace: instance.Namespace}, nginxGRPC); err != nil {
		t.Fatal(err)
	}
	_, public, grpc := getHAProxyObjects(t, r, instance)

	if !reflect.DeepEqual(public.Spec.TLS, nginx.Spec.TLS) {
		t.Fatalf("TLS diverges between gateways: haproxy %+v, nginx %+v", public.Spec.TLS, nginx.Spec.TLS)
	}
	if public.Spec.TLS[0].SecretName != wildcard.Name {
		t.Fatalf("expected the shared wildcard, got %q", public.Spec.TLS[0].SecretName)
	}
	for _, pair := range [][2]*networkingv1.Ingress{{public, nginx}, {grpc, nginxGRPC}} {
		var haproxyHosts, nginxHosts []string
		for _, rule := range pair[0].Spec.Rules {
			haproxyHosts = append(haproxyHosts, rule.Host)
		}
		for _, rule := range pair[1].Spec.Rules {
			nginxHosts = append(nginxHosts, rule.Host)
		}
		if !reflect.DeepEqual(haproxyHosts, nginxHosts) || len(haproxyHosts) != 2 {
			t.Fatalf("%s routes %v, %s routes %v", pair[0].Name, haproxyHosts, pair[1].Name, nginxHosts)
		}
	}
}

func TestHAProxyGatewayRestrictsPrivateInstancesToTheirClients(t *testing.T) {
	ctx := context.Background()
	instance := haproxyTestInstance()
	instance.Spec.Private = true
	instance.Spec.PrivateHost = "acme-scw-fr-par-runners.kura.tuist.dev"
	instance.Spec.IngressClassName = "kura-runners"
	instance.Spec.HAProxyIngressClassName = "kura-runners-haproxy"
	instance.Spec.ClientCIDRs = []string{"172.16.0.0/22", "10.0.0.0/8"}
	r := haproxyTestReconciler(t, instance)

	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}

	_, public, grpc := getHAProxyObjects(t, r, instance)
	for _, ingress := range []*networkingv1.Ingress{public, grpc} {
		if ingress.Annotations["haproxy.org/allow-list"] != "172.16.0.0/22,10.0.0.0/8" {
			t.Fatalf("%s: HTTP and gRPC must enforce the private allowlist, got %q", ingress.Name, ingress.Annotations["haproxy.org/allow-list"])
		}
		if ingress.Spec.Rules[0].Host != instance.Spec.PrivateHost {
			t.Fatalf("%s: expected the private host, got %q", ingress.Name, ingress.Spec.Rules[0].Host)
		}
	}
}

func TestHAProxyGatewayIsRemovedWhenTheRegionLeavesIt(t *testing.T) {
	ctx := context.Background()
	instance := haproxyTestInstance()
	r := haproxyTestReconciler(t, instance)
	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}

	instance.Spec.HAProxyIngressClassName = ""
	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}

	for _, object := range []client.Object{&corev1.Service{}, &networkingv1.Ingress{}} {
		for _, name := range []string{haproxyServiceName(instance), haproxyGRPCIngressName(instance)} {
			err := r.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, object)
			if !apierrors.IsNotFound(err) {
				t.Fatalf("expected %T %s to be deleted, got %v", object, name, err)
			}
		}
	}
}

func TestHAProxyGatewayIsNotRenderedWithoutAClientHost(t *testing.T) {
	ctx := context.Background()
	instance := haproxyTestInstance()
	instance.Spec.PublicHost = ""
	r := haproxyTestReconciler(t, instance)

	if err := r.reconcileHAProxyGateway(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}

	err := r.Get(ctx, types.NamespacedName{Name: haproxyServiceName(instance), Namespace: instance.Namespace}, &corev1.Service{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("expected no gateway Service, got %v", err)
	}
}
