package controllers

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	discoveryv1 "k8s.io/api/discovery/v1"
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

	routes, nodeSelector, tolerations, issues := peerDemuxDesiredState("eu-central", "kura", instances)

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
	if len(issues) != 0 {
		t.Fatalf("expected no route issues, got %+v", issues)
	}
}

func TestPeerDemuxDesiredStatePublishesOneSafeRoutePerHost(t *testing.T) {
	host := "peer.acme-eu-central.kura.tuist.dev"
	legacy := hostNetworkPeerInstance("kura-acme-old", "eu-central", host)
	legacy.CreationTimestamp = metav1.NewTime(time.Date(2026, time.July, 1, 0, 0, 0, 0, time.UTC))
	explicit := hostNetworkPeerInstance("kura-acme-current", "eu-central", host)
	explicit.CreationTimestamp = metav1.NewTime(time.Date(2026, time.July, 2, 0, 0, 0, 0, time.UTC))
	explicit.Spec.MeshPublicPeerPublished = ptr(true)
	warming := hostNetworkPeerInstance("kura-acme-warming", "eu-central", host)
	warming.Spec.MeshPublicPeerPublished = ptr(false)
	invalid := hostNetworkPeerInstance("kura-invalid", "eu-central", "not a host; include /tmp/file")

	routes, _, _, issues := peerDemuxDesiredState(
		"eu-central",
		"kura",
		[]kurav1alpha1.KuraInstance{*warming, *legacy, *invalid, *explicit},
	)

	if len(routes) != 1 {
		t.Fatalf("expected one deduplicated route, got %+v", routes)
	}
	wantBackend := instancePublicPeerServiceName(explicit) + ".kura.svc.cluster.local:7443"
	if routes[0].host != host || routes[0].backend != wantBackend {
		t.Fatalf("expected the explicit owner route %s -> %s, got %+v", host, wantBackend, routes[0])
	}
	if len(issues) != 2 {
		t.Fatalf("expected duplicate and invalid-host diagnostics, got %+v", issues)
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
		"map_hash_bucket_size 512;",
		"map_hash_max_size 8192;",
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

func TestPeerDemuxNginxConfSupportsMaximumAccountHandle(t *testing.T) {
	host := "peer." + strings.Repeat("a", 32) + "-eu-central-1-staging.kura.tuist.dev"
	conf := peerDemuxNginxConf([]peerDemuxRoute{{
		host:    host,
		backend: "kura-account-eu-central-1-peers-public.kura.svc.cluster.local:7443",
	}}, "10.96.0.10")

	if !strings.Contains(conf, "map_hash_bucket_size 512;") {
		t.Fatalf("nginx conf must enlarge the map hash bucket for %d-byte peer hosts:\n%s", len(host), conf)
	}
	if !strings.Contains(conf, host+" ") {
		t.Fatalf("nginx conf missing the maximum-length account host %q:\n%s", host, conf)
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
	reconciler := &PeerDemuxReconciler{Client: client, APIReader: client, Scheme: scheme}

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

func TestUnpublishedHostNetworkPeerKeepsWarmBackendWithoutAdvertising(t *testing.T) {
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
	instance.Spec.MeshPublicPeerPublished = ptr(false)
	staleEndpoint := &unstructured.Unstructured{}
	staleEndpoint.SetGroupVersionKind(dnsEndpointGVK)
	staleEndpoint.SetName(instance.Name + "-peer-dns")
	staleEndpoint.SetNamespace(instance.Namespace)
	client := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance, staleEndpoint).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	if err := reconciler.reconcileInstancePublicPeerService(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := client.Get(ctx, types.NamespacedName{Name: instancePublicPeerServiceName(instance), Namespace: instance.Namespace}, service); err != nil {
		t.Fatalf("expected the unpublished instance to retain a warm peer backend: %v", err)
	}
	if service.Spec.Type != corev1.ServiceTypeClusterIP {
		t.Fatalf("expected a ClusterIP warm backend, got %q", service.Spec.Type)
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: staleEndpoint.GetName(), Namespace: instance.Namespace}, endpoint); !apierrors.IsNotFound(err) {
		t.Fatalf("expected public peer DNS to be absent while unpublished, got %v", err)
	}
	routes, _, _, _ := peerDemuxDesiredState(instance.Spec.Region, instance.Namespace, []kurav1alpha1.KuraInstance{*instance})
	if len(routes) != 0 {
		t.Fatalf("expected no demultiplexer route while unpublished, got %+v", routes)
	}
	for _, env := range baseEnv(instance, "", "test") {
		if env.Name == "KURA_PEER_GATEWAY_URL" {
			t.Fatalf("expected an unpublished warm instance not to advertise itself, got %q", env.Value)
		}
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

func TestLegacyAccountPublicPeerServiceRetiresAfterReadyCutover(t *testing.T) {
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

	instance := hostNetworkPeerInstance(
		"kura-acme-eu-central-1",
		"eu-central",
		"peer.acme-eu-central-1.kura.tuist.dev",
	)
	instance.Spec.AccountHandle = "acme"
	oldAddress := "198.51.100.20"
	targetAddress := instance.Spec.MeshPeerFailoverIP
	legacy := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      legacyAccountPublicPeerServiceName(instance),
			Namespace: instance.Namespace,
			Labels: map[string]string{
				"app.kubernetes.io/name":       "kura",
				"app.kubernetes.io/managed-by": "kura-controller",
				"tuist.dev/account":            instance.Spec.AccountHandle,
			},
			Annotations: map[string]string{
				externalDNSHostnameAnnotation:          instance.Spec.MeshPublicPeerHost,
				hetznerNodeSelectorAnnotation:          "node.cluster.x-k8s.io/pool=kura",
				"load-balancer.hetzner.cloud/location": "fsn1",
			},
		},
		Spec: corev1.ServiceSpec{
			Type:                  corev1.ServiceTypeLoadBalancer,
			ExternalTrafficPolicy: corev1.ServiceExternalTrafficPolicyTypeLocal,
			HealthCheckNodePort:   30123,
			Selector: map[string]string{
				"app.kubernetes.io/name": "kura",
				"tuist.dev/account":      instance.Spec.AccountHandle,
			},
		},
		Status: corev1.ServiceStatus{LoadBalancer: corev1.LoadBalancerStatus{Ingress: []corev1.LoadBalancerIngress{{IP: oldAddress}}}},
	}
	peerServiceName := instancePublicPeerServiceName(instance)
	peerService := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: peerServiceName, Namespace: instance.Namespace},
		Spec: corev1.ServiceSpec{
			Type:     corev1.ServiceTypeClusterIP,
			Selector: selectorLabels(instance),
		},
	}
	ready := true
	peerPortValue := peerPort
	peerEndpoints := &discoveryv1.EndpointSlice{
		ObjectMeta: metav1.ObjectMeta{
			Name:      peerServiceName + "-ready",
			Namespace: instance.Namespace,
			Labels:    map[string]string{discoveryv1.LabelServiceName: peerServiceName},
		},
		AddressType: discoveryv1.AddressTypeIPv4,
		Ports:       []discoveryv1.EndpointPort{{Name: ptr("peer"), Port: &peerPortValue}},
		Endpoints: []discoveryv1.Endpoint{{
			Addresses:  []string{"10.0.0.20"},
			Conditions: discoveryv1.EndpointConditions{Ready: &ready},
		}},
	}
	dnsEndpoint := &unstructured.Unstructured{}
	dnsEndpoint.SetGroupVersionKind(dnsEndpointGVK)
	dnsEndpoint.SetName(instance.Name + "-peer-dns")
	dnsEndpoint.SetNamespace(instance.Namespace)
	dnsEndpoint.SetGeneration(3)
	if err := unstructured.SetNestedSlice(dnsEndpoint.Object, []interface{}{
		map[string]interface{}{
			"dnsName":    instance.Spec.MeshPublicPeerHost,
			"recordType": "A",
			"recordTTL":  peerDNSRecordTTLSeconds,
			"targets":    []interface{}{targetAddress},
		},
	}, "spec", "endpoints"); err != nil {
		t.Fatal(err)
	}
	if err := unstructured.SetNestedField(dnsEndpoint.Object, int64(3), "status", "observedGeneration"); err != nil {
		t.Fatal(err)
	}
	config := peerDemuxNginxConf([]peerDemuxRoute{{
		host:    instance.Spec.MeshPublicPeerHost,
		backend: peerServiceName + "." + instance.Namespace + ".svc.cluster.local:7443",
	}}, "10.96.0.10")
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{Name: peerDemuxName(instance.Spec.Region), Namespace: instance.Namespace},
		Data:       map[string]string{"nginx.conf": config},
	}
	configHash := fmt.Sprintf("%x", sha256.Sum256([]byte(config)))
	demux := &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{Name: peerDemuxName(instance.Spec.Region), Namespace: instance.Namespace, Generation: 2},
		Spec: appsv1.DaemonSetSpec{Template: corev1.PodTemplateSpec{ObjectMeta: metav1.ObjectMeta{
			Annotations: map[string]string{peerDemuxConfigHashAnnotation: configHash},
		}}},
		Status: appsv1.DaemonSetStatus{
			ObservedGeneration:     2,
			DesiredNumberScheduled: 1,
			UpdatedNumberScheduled: 1,
			NumberReady:            1,
			NumberAvailable:        1,
		},
	}
	peerSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace},
		Data:       map[string][]byte{peerTLSCAFile: []byte("fake"), peerTLSCertFile: []byte("fake"), peerTLSKeyFile: []byte("fake")},
	}
	client := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRESTMapper(mapper).
		WithObjects(instance, legacy, peerService, peerEndpoints, dnsEndpoint, configMap, demux, peerSecret).
		Build()
	resolver := &fakePeerDNSResolver{addresses: []string{oldAddress}}
	prober := &fakePeerPathProber{}
	reconciler := &KuraInstanceReconciler{
		Client: client, Scheme: scheme, PeerDNSResolver: resolver, PeerPathProber: prober,
	}

	cutoverStartedAt := time.Date(2026, time.July, 19, 12, 0, 0, 0, time.UTC)
	// A ready DaemonSet running a stale ConfigMap revision must not start the
	// migration. Readiness is tied to the exact rendered route hash.
	if err := client.Get(ctx, types.NamespacedName{Name: demux.Name, Namespace: demux.Namespace}, demux); err != nil {
		t.Fatal(err)
	}
	demux.Spec.Template.Annotations[peerDemuxConfigHashAnnotation] = "stale"
	if err := client.Update(ctx, demux); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, cutoverStartedAt); err != nil {
		t.Fatal(err)
	}
	got := &corev1.Service{}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatal(err)
	}
	if got.Annotations[legacyPeerMigrationAnnotation] != "" {
		t.Fatalf("expected stale demultiplexer configuration to block migration, got %v", got.Annotations)
	}
	demux.Spec.Template.Annotations[peerDemuxConfigHashAnnotation] = configHash
	if err := client.Update(ctx, demux); err != nil {
		t.Fatal(err)
	}

	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, cutoverStartedAt); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatal(err)
	}
	if got.Annotations[legacyPeerMigrationAnnotation] != legacyPeerPhaseRepairing {
		t.Fatalf("expected the fallback-repair phase, got %v", got.Annotations)
	}
	if got.Annotations[externalDNSHostnameAnnotation] == "" {
		t.Fatal("fallback repair must keep legacy DNS publication")
	}
	if _, found := got.Annotations[hetznerNodeSelectorAnnotation]; found {
		t.Fatalf("expected the stale Hetzner node selector to be removed, got %v", got.Annotations)
	}
	if got.Spec.ExternalTrafficPolicy != corev1.ServiceExternalTrafficPolicyTypeCluster || got.Spec.HealthCheckNodePort != 0 {
		t.Fatalf("expected a Cluster-routed fallback, got policy=%q healthPort=%d", got.Spec.ExternalTrafficPolicy, got.Spec.HealthCheckNodePort)
	}
	// Recreate the reconciler to prove that no in-memory state is needed to
	// resume after a controller restart.
	reconciler = &KuraInstanceReconciler{
		Client: client, Scheme: scheme, PeerDNSResolver: resolver, PeerPathProber: prober,
	}

	// A separate reconciliation verifies both public paths before it requests
	// the DNS cutover.
	prober.fail = map[string]error{oldAddress: fmt.Errorf("legacy load balancer has not converged")}
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, cutoverStartedAt); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatal(err)
	}
	if got.Annotations[externalDNSHostnameAnnotation] == "" {
		t.Fatal("a failed fallback probe must keep legacy DNS publication")
	}
	prober.fail = nil
	prober.addresses = nil
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, cutoverStartedAt); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatal(err)
	}
	if _, ok := got.Annotations[externalDNSHostnameAnnotation]; ok {
		t.Fatal("legacy service must stop publishing only after both public paths are ready")
	}
	if got.Annotations[legacyPeerMigrationAnnotation] != legacyPeerPhaseCutoverRequested {
		t.Fatalf("expected a requested DNS cutover, got %v", got.Annotations)
	}
	if got.Annotations[legacyPeerRetireAfterAnnotation] != "" {
		t.Fatal("the retirement timer must not start before public DNS changes")
	}
	if len(prober.addresses) != 2 || prober.addresses[0] != oldAddress || prober.addresses[1] != targetAddress {
		t.Fatalf("expected both public paths to be probed, got %v", prober.addresses)
	}

	// Seeing only the old address must not start the drain.
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, cutoverStartedAt); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatal(err)
	}
	if got.Annotations[legacyPeerRetireAfterAnnotation] != "" {
		t.Fatal("old DNS must keep the retirement timer unset")
	}

	resolver.addresses = []string{targetAddress}
	dnsObservedAt := cutoverStartedAt.Add(time.Minute)
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, dnsObservedAt); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatal(err)
	}
	wantRetireAfter := dnsObservedAt.Add(legacyPeerRetirementDelay).Format(time.RFC3339)
	if got.Annotations[legacyPeerMigrationAnnotation] != legacyPeerPhaseDraining ||
		got.Annotations[legacyPeerRetireAfterAnnotation] != wantRetireAfter {
		t.Fatalf("expected a post-observation drain until %s, got %v", wantRetireAfter, got.Annotations)
	}

	// A DNS regression cancels the deadline and keeps the fallback.
	resolver.addresses = []string{oldAddress}
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, dnsObservedAt.Add(legacyPeerRetirementDelay)); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); err != nil {
		t.Fatalf("expected the fallback to survive a DNS regression: %v", err)
	}
	if got.Annotations[legacyPeerMigrationAnnotation] != legacyPeerPhaseCutoverRequested ||
		got.Annotations[legacyPeerRetireAfterAnnotation] != "" {
		t.Fatalf("expected the drain to reset after regression, got %v", got.Annotations)
	}

	resolver.addresses = []string{targetAddress}
	reobservedAt := dnsObservedAt.Add(legacyPeerRetirementDelay + time.Minute)
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, reobservedAt); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.retireLegacyAccountPublicPeerService(ctx, instance, reobservedAt.Add(legacyPeerRetirementDelay)); err != nil {
		t.Fatal(err)
	}
	if err := client.Get(ctx, types.NamespacedName{Name: legacy.Name, Namespace: legacy.Namespace}, got); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the drained legacy service to be deleted, got %v", err)
	}
}

type fakePeerDNSResolver struct {
	addresses []string
	err       error
}

func (resolver *fakePeerDNSResolver) LookupHost(context.Context, string) ([]string, error) {
	return resolver.addresses, resolver.err
}

type fakePeerPathProber struct {
	addresses []string
	fail      map[string]error
}

func (prober *fakePeerPathProber) Probe(_ context.Context, address string, _ string, _ map[string][]byte) error {
	prober.addresses = append(prober.addresses, address)
	return prober.fail[address]
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
	// No failover IP, and the fake client has no pods, so there is no node-IP
	// fallback target either -> the stale DNSEndpoint must be torn down.
	instance.Spec.MeshPeerFailoverIP = ""

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

func TestPeerDNSEndpointFallsBackToBoxIPWithoutFailoverIP(t *testing.T) {
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
	instance.Spec.MeshPeerFailoverIP = "" // no region failover IP provisioned yet

	// The account's pod is scheduled on box-1, whose InternalIP is the box's
	// public IP on a bare-metal region.
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "kura-acme-0",
			Namespace: "kura",
			Labels:    map[string]string{"app.kubernetes.io/name": "kura", "app.kubernetes.io/instance": "kura-acme"},
		},
		Spec: corev1.PodSpec{NodeName: "box-1"},
	}
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "box-1"},
		Status:     corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.50"}}},
	}

	client := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance, pod, node).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	if err := reconciler.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}

	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: "kura-acme-peer-dns", Namespace: "kura"}, endpoint); err != nil {
		t.Fatal(err)
	}
	endpoints, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if len(endpoints) != 1 {
		t.Fatalf("expected one DNS endpoint, got %v", endpoints)
	}
	targets := endpoints[0].(map[string]interface{})["targets"].([]interface{})
	if len(targets) != 1 || targets[0] != "203.0.113.50" {
		t.Fatalf("expected the box node IP as the DNS target, got %v", targets)
	}
}
