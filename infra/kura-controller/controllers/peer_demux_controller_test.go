package controllers

import (
	"context"
	"strings"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func hostNetworkPeerInstance(name, region, host string) *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:       strings.TrimPrefix(name, "kura-"),
			Region:              region,
			Mesh:                true,
			MeshPublicPeerHost:  host,
			MeshPeerHostNetwork: true,
			MeshPeerFailoverIP:  "203.0.113.10",
			NodeSelector:        map[string]string{"node.cluster.x-k8s.io/pool": "kura-dedibox"},
			Tolerations: []corev1.Toleration{
				{Key: "tuist.dev/kura-cache", Operator: corev1.TolerationOpExists, Effect: corev1.TaintEffectNoSchedule},
			},
		},
	}
}

func TestPeerDemuxDesiredStateFiltersHostNetworkInstances(t *testing.T) {
	instances := []kurav1alpha1.KuraInstance{
		*hostNetworkPeerInstance("kura-acme", "eu-central", "peer.acme-eu-central.kura.tuist.dev"),
		// Different region.
		*hostNetworkPeerInstance("kura-globex", "ca-east", "peer.globex-ca-east.kura.tuist.dev"),
		// Same region but LoadBalancer-fronted (not host network).
		{
			ObjectMeta: metav1.ObjectMeta{Name: "kura-initech", Namespace: "kura"},
			Spec: kurav1alpha1.KuraInstanceSpec{
				Region: "eu-central", Mesh: true,
				MeshPublicPeerHost: "peer.initech-eu-central.kura.tuist.dev",
			},
		},
		// Same region, host network, but no public peer host.
		{
			ObjectMeta: metav1.ObjectMeta{Name: "kura-hooli", Namespace: "kura"},
			Spec:       kurav1alpha1.KuraInstanceSpec{Region: "eu-central", Mesh: true, MeshPeerHostNetwork: true},
		},
	}

	routes, nodeSelector, tolerations := peerDemuxDesiredState("eu-central", "kura", instances)

	if len(routes) != 1 {
		t.Fatalf("expected exactly the one host-network eu-central route, got %d: %+v", len(routes), routes)
	}
	if routes[0].host != "peer.acme-eu-central.kura.tuist.dev" {
		t.Fatalf("unexpected route host %q", routes[0].host)
	}
	if routes[0].backend != "kura-acme-peers-public.kura.svc.cluster.local:7443" {
		t.Fatalf("unexpected route backend %q", routes[0].backend)
	}
	if nodeSelector["node.cluster.x-k8s.io/pool"] != "kura-dedibox" {
		t.Fatalf("expected the pool nodeSelector to carry through, got %+v", nodeSelector)
	}
	if len(tolerations) != 1 || tolerations[0].Key != "tuist.dev/kura-cache" {
		t.Fatalf("expected the cache taint toleration to carry through, got %+v", tolerations)
	}
}

func TestPeerDemuxNginxConfRoutesBySNI(t *testing.T) {
	conf := peerDemuxNginxConf([]peerDemuxRoute{
		{host: "peer.acme-eu-central.kura.tuist.dev", backend: "kura-acme-peers-public.kura.svc.cluster.local:7443"},
	}, "10.96.0.10")

	for _, want := range []string{
		// A resolver is mandatory for the variable proxy_pass to resolve the
		// .svc.cluster.local backends at request time.
		"resolver 10.96.0.10 valid=10s;",
		"map $ssl_preread_server_name $kura_peer_backend {",
		"ssl_preread on;",
		"listen 7443;",
		"peer.acme-eu-central.kura.tuist.dev kura-acme-peers-public.kura.svc.cluster.local:7443;",
		"proxy_pass $kura_peer_backend;",
	} {
		if !strings.Contains(conf, want) {
			t.Fatalf("nginx conf missing %q:\n%s", want, conf)
		}
	}
	// No TLS termination directives — the demux is L4 SNI passthrough.
	if strings.Contains(conf, "ssl_certificate") {
		t.Fatalf("demux must not terminate TLS:\n%s", conf)
	}
}

func TestPeerDemuxReconcileCreatesAndTearsDown(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := hostNetworkPeerInstance("kura-acme", "eu-central", "peer.acme-eu-central.kura.tuist.dev")
	dns := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "kube-dns", Namespace: "kube-system"},
		Spec:       corev1.ServiceSpec{ClusterIP: "10.96.0.10"},
	}
	client := fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, dns).Build()
	reconciler := &PeerDemuxReconciler{Client: client, Scheme: scheme}

	req := ctrl.Request{NamespacedName: types.NamespacedName{Name: "eu-central", Namespace: "kura"}}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}

	name := peerDemuxName("eu-central")
	configMap := &corev1.ConfigMap{}
	if err := client.Get(ctx, types.NamespacedName{Name: name, Namespace: "kura"}, configMap); err != nil {
		t.Fatalf("expected demux ConfigMap: %v", err)
	}
	if !strings.Contains(configMap.Data["nginx.conf"], "peer.acme-eu-central.kura.tuist.dev") {
		t.Fatalf("demux config missing the account route:\n%s", configMap.Data["nginx.conf"])
	}

	daemonSet := &appsv1.DaemonSet{}
	if err := client.Get(ctx, types.NamespacedName{Name: name, Namespace: "kura"}, daemonSet); err != nil {
		t.Fatalf("expected demux DaemonSet: %v", err)
	}
	if !daemonSet.Spec.Template.Spec.HostNetwork {
		t.Fatal("demux DaemonSet must be host-network")
	}
	if daemonSet.Spec.Template.Spec.NodeSelector["node.cluster.x-k8s.io/pool"] != "kura-dedibox" {
		t.Fatalf("demux must pin to the region pool, got %+v", daemonSet.Spec.Template.Spec.NodeSelector)
	}
	if daemonSet.Spec.Template.Annotations[peerDemuxConfigHashAnnotation] == "" {
		t.Fatal("demux pod template must carry a config-hash annotation for rollout-on-change")
	}

	// Drop the only host-network instance: the demux is torn down.
	if err := client.Delete(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: name, Namespace: "kura"}, &corev1.ConfigMap{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected demux ConfigMap to be deleted, got %v", err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: name, Namespace: "kura"}, &appsv1.DaemonSet{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected demux DaemonSet to be deleted, got %v", err)
	}
}

func TestInstancePublicPeerServiceUsesClusterIPOnHostNetwork(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := hostNetworkPeerInstance("kura-acme", "eu-central", "peer.acme-eu-central.kura.tuist.dev")
	client := fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	if err := reconciler.reconcileInstancePublicPeerService(ctx, instance); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := client.Get(ctx, types.NamespacedName{Name: instancePublicPeerServiceName(instance), Namespace: "kura"}, service); err != nil {
		t.Fatal(err)
	}
	if service.Spec.Type != corev1.ServiceTypeClusterIP {
		t.Fatalf("expected ClusterIP backend on host-network region, got %q", service.Spec.Type)
	}
	if _, ok := service.Annotations["external-dns.alpha.kubernetes.io/hostname"]; ok {
		t.Fatal("host-network peer service must not carry an LB external-dns annotation")
	}
}

func TestPeerDNSEndpointPublishesFailoverIP(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	scheme.AddKnownTypeWithName(dnsEndpointGVK, &unstructured.Unstructured{})

	mapper := meta.NewDefaultRESTMapper([]schema.GroupVersion{dnsEndpointGVK.GroupVersion()})
	mapper.Add(dnsEndpointGVK, meta.RESTScopeNamespace)

	instance := hostNetworkPeerInstance("kura-acme", "eu-central", "peer.acme-eu-central.kura.tuist.dev")
	client := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	if err := reconciler.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}

	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: instance.Name + "-peer-dns", Namespace: "kura"}, endpoint); err != nil {
		t.Fatal(err)
	}
	endpoints, found, err := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if err != nil || !found || len(endpoints) != 1 {
		t.Fatalf("expected one DNS endpoint, found=%v err=%v: %+v", found, err, endpoints)
	}
	record := endpoints[0].(map[string]interface{})
	if record["dnsName"] != "peer.acme-eu-central.kura.tuist.dev" {
		t.Fatalf("unexpected dnsName %v", record["dnsName"])
	}
	targets := record["targets"].([]interface{})
	if len(targets) != 1 || targets[0] != "203.0.113.10" {
		t.Fatalf("expected the failover IP target, got %v", targets)
	}
}

func TestPeerDNSEndpointDeletedWhenFailoverIPMissing(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	scheme.AddKnownTypeWithName(dnsEndpointGVK, &unstructured.Unstructured{})
	mapper := meta.NewDefaultRESTMapper([]schema.GroupVersion{dnsEndpointGVK.GroupVersion()})
	mapper.Add(dnsEndpointGVK, meta.RESTScopeNamespace)

	// A DNSEndpoint left over from when the region's failover IP was configured.
	existing := &unstructured.Unstructured{}
	existing.SetGroupVersionKind(dnsEndpointGVK)
	existing.SetNamespace("kura")
	existing.SetName("kura-acme-peer-dns")

	instance := hostNetworkPeerInstance("kura-acme", "eu-central", "peer.acme-eu-central.kura.tuist.dev")
	instance.Spec.MeshPeerFailoverIP = "" // failover IP removed / not yet provisioned

	client := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance, existing).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	if err := reconciler.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}

	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: "kura-acme-peer-dns", Namespace: "kura"}, got); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the stale DNSEndpoint to be deleted, got %v", err)
	}
}
