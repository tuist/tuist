package controllers

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"strings"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const testEgressNamespace = "tailscale-operator"

func nodeLocalMeshInstance(name, handle string) *kurav1alpha1.KuraInstance {
	instance := nodeLocalTestInstance()
	instance.Name = name
	instance.Spec.AccountHandle = handle
	instance.Spec.TenantID = handle
	instance.Spec.Region = "ber1-runners"
	instance.Spec.Mesh = true
	instance.Spec.NodeSelector = map[string]string{"node.cluster.x-k8s.io/pool": "rack-storage-ber1"}
	instance.Spec.Tolerations = []corev1.Toleration{
		{Key: "tuist.dev/rack-storage", Operator: corev1.TolerationOpExists, Effect: corev1.TaintEffectNoSchedule},
	}
	instance.Spec.NodeLocalNetwork.PeerHost = name + "-peer." + testEgressNamespace + ".svc.cluster.local"
	return instance
}

func nodeLocalPod(instance *kurav1alpha1.KuraInstance, ordinal, node, ip string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      instance.Name + "-" + ordinal,
			Namespace: instance.Namespace,
			Labels:    labels(instance),
		},
		Spec:   corev1.PodSpec{NodeName: node},
		Status: corev1.PodStatus{PodIP: ip},
	}
}

func TestNodeLocalMeshInstanceAdvertisesItsEgressNameAndLooksUpNoPeerService(t *testing.T) {
	instance := nodeLocalMeshInstance("kura-acme-ber1", "acme")
	env := baseEnv(instance, "", "production")

	if value, _ := envValue(env, "KURA_DISCOVERY_DNS_NAME"); value != "" {
		t.Fatalf("KURA_DISCOVERY_DNS_NAME = %q, want none: a rack pod resolves no cluster name", value)
	}
	want := "https://kura-acme-ber1-peer.tailscale-operator.svc.cluster.local:7443"
	if value, _ := envValue(env, "KURA_PEER_GATEWAY_URL"); value != want {
		t.Fatalf("KURA_PEER_GATEWAY_URL = %q, want %q", value, want)
	}

	instance.Spec.Mesh = false
	if value, ok := envValue(baseEnv(instance, "", "production"), "KURA_PEER_GATEWAY_URL"); ok {
		t.Fatalf("an instance outside the mesh advertised %q", value)
	}
}

func TestNodeLocalMeshLeafCoversItsEgressName(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	instance := nodeLocalMeshInstance("kura-acme-ber1", "acme")
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build(),
		Scheme: scheme,
	}
	if err := reconciler.reconcilePeerTLSSecret(ctx, instance); err != nil {
		t.Fatal(err)
	}

	leaf := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, leaf); err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(leaf.Data[peerTLSCertFile])
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	if !containsString(cert.DNSNames, instance.Spec.NodeLocalNetwork.PeerHost) {
		t.Fatalf("expected the leaf to cover %s, got %v", instance.Spec.NodeLocalNetwork.PeerHost, cert.DNSNames)
	}

	caSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerCASecretName(instance), Namespace: instance.Namespace}, caSecret); err != nil {
		t.Fatal(err)
	}
	moved := instance.DeepCopy()
	moved.Spec.NodeLocalNetwork.PeerHost = "kura-acme-ber1-other." + testEgressNamespace + ".svc.cluster.local"
	if peerTLSSecretDataValid(leaf.Data, moved, caSecret.Data[peerCACertFile]) {
		t.Fatal("expected a leaf that does not cover the peer host to be reissued")
	}
}

func TestNodeLocalPeerDesiredStateRoutesEachInstanceToItsGatewayPodOnItsNode(t *testing.T) {
	acme := nodeLocalMeshInstance("kura-acme-ber1", "acme")
	acme.Status.PeerRoles = []kurav1alpha1.KuraInstancePeerRole{
		{NodeURL: podNodeURL(acme, "kura-acme-ber1-0")},
		{NodeURL: podNodeURL(acme, "kura-acme-ber1-1"), Gateway: true},
	}
	globex := nodeLocalMeshInstance("kura-globex-ber1", "globex")
	pending := nodeLocalMeshInstance("kura-initech-ber1", "initech")
	elsewhere := nodeLocalMeshInstance("kura-hooli-ber2", "hooli")
	elsewhere.Spec.Region = "ber2-runners"
	outsideMesh := nodeLocalMeshInstance("kura-umbrella-ber1", "umbrella")
	outsideMesh.Spec.Mesh = false
	wrongNamespace := nodeLocalMeshInstance("kura-stark-ber1", "stark")
	wrongNamespace.Spec.NodeLocalNetwork.PeerHost = "kura-stark-ber1-peer.kura.svc.cluster.local"

	pods := []corev1.Pod{
		*nodeLocalPod(acme, "0", "ber1-store-a", "10.254.254.10"),
		*nodeLocalPod(acme, "1", "ber1-store-b", "10.254.254.11"),
		*nodeLocalPod(globex, "0", "ber1-store-a", "10.254.254.12"),
		// Scheduled, no address yet.
		*nodeLocalPod(pending, "0", "ber1-store-a", ""),
	}
	instances := []kurav1alpha1.KuraInstance{*acme, *globex, *pending, *elsewhere, *outsideMesh, *wrongNamespace}

	state := nodeLocalPeerDesiredState("ber1-runners", testEgressNamespace, instances, pods)

	wantRoutes := []nodeLocalPeerRoute{
		{host: globex.Spec.NodeLocalNetwork.PeerHost, node: "ber1-store-a", backend: "10.254.254.12:7443"},
		{host: acme.Spec.NodeLocalNetwork.PeerHost, node: "ber1-store-b", backend: "10.254.254.11:7443"},
	}
	if len(state.routes) != len(wantRoutes) {
		t.Fatalf("routes = %+v, want %+v", state.routes, wantRoutes)
	}
	for i, route := range wantRoutes {
		if state.routes[i] != route {
			t.Fatalf("route %d = %+v, want %+v", i, state.routes[i], route)
		}
	}

	egressNodes := map[string]string{}
	for _, egress := range state.egresses {
		egressNodes[egress.name] = egress.node
	}
	wantEgress := map[string]string{
		"kura-acme-ber1-peer":    "ber1-store-b",
		"kura-globex-ber1-peer":  "ber1-store-a",
		"kura-initech-ber1-peer": "",
	}
	if len(egressNodes) != len(wantEgress) {
		t.Fatalf("egresses = %+v, want %+v", egressNodes, wantEgress)
	}
	for name, node := range wantEgress {
		if got, ok := egressNodes[name]; !ok || got != node {
			t.Fatalf("egress %s targets %q (present: %v), want %q", name, got, ok, node)
		}
	}
	if len(state.issues) != 1 || !strings.Contains(state.issues[0], "kura-stark-ber1") {
		t.Fatalf("expected the peer host outside the egress namespace to be reported, got %v", state.issues)
	}
	if state.nodeSelector["node.cluster.x-k8s.io/pool"] != "rack-storage-ber1" || len(state.tolerations) != 1 {
		t.Fatalf("expected the region's pool placement, got %v and %v", state.nodeSelector, state.tolerations)
	}
}

func TestNodeLocalPeerDemuxForwardsOnlyToTheNodesOwnPods(t *testing.T) {
	files := nodeLocalPeerDemuxConfigs([]nodeLocalPeerRoute{
		{host: "kura-acme-ber1-peer.tailscale-operator.svc.cluster.local", node: "ber1-store-a", backend: "10.254.254.10:7443"},
		{host: "kura-globex-ber1-peer.tailscale-operator.svc.cluster.local", node: "ber1-store-b", backend: "10.254.254.10:7443"},
	})

	if len(files) != 3 {
		t.Fatalf("expected a config per node plus the default, got %v", keys(files))
	}
	storeA := files["ber1-store-a.conf"]
	if !strings.Contains(storeA, "kura-acme-ber1-peer.tailscale-operator.svc.cluster.local 10.254.254.10:7443;") ||
		strings.Contains(storeA, "kura-globex") {
		t.Fatalf("store-a must route only its own pod:\n%s", storeA)
	}
	if strings.Contains(files[nodeLocalPeerDefaultConfig], "10.254.254.") {
		t.Fatalf("the default config must route nothing:\n%s", files[nodeLocalPeerDefaultConfig])
	}
	for name, conf := range files {
		if strings.Contains(conf, "resolver") {
			t.Fatalf("%s needs no resolver, the backends are addresses:\n%s", name, conf)
		}
		if !strings.Contains(conf, "listen 7443;") || !strings.Contains(conf, "ssl_preread on;") {
			t.Fatalf("%s must pass TLS through on the peer port:\n%s", name, conf)
		}
	}
}

func keys(files map[string]string) []string {
	result := make([]string, 0, len(files))
	for key := range files {
		result = append(result, key)
	}
	return result
}

func nodeLocalPeerTestReconciler(t *testing.T, objects ...client.Object) (*NodeLocalPeerReconciler, client.Client) {
	t.Helper()
	scheme := meshTestScheme(t)
	cluster := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
	return &NodeLocalPeerReconciler{
		Client:           cluster,
		EgressClient:     cluster,
		Scheme:           scheme,
		EgressNamespace:  testEgressNamespace,
		EgressProxyGroup: "macmini-egress",
		TailnetDomain:    "tail1234.ts.net",
	}, cluster
}

func TestNodeLocalPeerReconcileBacksThePeerHostWithAnEgressServiceAndADemux(t *testing.T) {
	ctx := context.Background()
	instance := nodeLocalMeshInstance("kura-acme-ber1", "acme")
	pod := nodeLocalPod(instance, "0", "ber1-store-a", "10.254.254.10")
	reconciler, cluster := nodeLocalPeerTestReconciler(t, instance, pod)
	request := ctrl.Request{NamespacedName: types.NamespacedName{Name: "ber1-runners", Namespace: "kura"}}

	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}

	egress := &corev1.Service{}
	if err := cluster.Get(ctx, types.NamespacedName{Namespace: testEgressNamespace, Name: "kura-acme-ber1-peer"}, egress); err != nil {
		t.Fatalf("expected the egress Service: %v", err)
	}
	if egress.Spec.Type != corev1.ServiceTypeExternalName {
		t.Fatalf("egress type = %s", egress.Spec.Type)
	}
	if got := egress.Annotations["tailscale.com/tailnet-fqdn"]; got != "ber1-store-a.tail1234.ts.net" {
		t.Fatalf("tailnet-fqdn = %q", got)
	}
	if got := egress.Annotations["tailscale.com/proxy-group"]; got != "macmini-egress" {
		t.Fatalf("proxy-group = %q", got)
	}
	if len(egress.Spec.Ports) != 1 || egress.Spec.Ports[0].Port != peerPort {
		t.Fatalf("ports = %+v", egress.Spec.Ports)
	}

	daemonSet := &appsv1.DaemonSet{}
	if err := cluster.Get(ctx, types.NamespacedName{Namespace: "kura", Name: "kura-node-local-peer-ber1-runners"}, daemonSet); err != nil {
		t.Fatalf("expected the demux DaemonSet: %v", err)
	}
	spec := daemonSet.Spec.Template.Spec
	if !spec.HostNetwork || spec.DNSPolicy != corev1.DNSDefault {
		t.Fatalf("expected a host-network demux on the node's resolver, got hostNetwork=%v dns=%s", spec.HostNetwork, spec.DNSPolicy)
	}
	if spec.NodeSelector["node.cluster.x-k8s.io/pool"] != "rack-storage-ber1" || len(spec.Tolerations) != 1 {
		t.Fatalf("expected the demux on the region's pool, got %v / %v", spec.NodeSelector, spec.Tolerations)
	}
	configMap := &corev1.ConfigMap{}
	if err := cluster.Get(ctx, types.NamespacedName{Namespace: "kura", Name: "kura-node-local-peer-ber1-runners"}, configMap); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(configMap.Data["ber1-store-a.conf"], "10.254.254.10:7443") {
		t.Fatalf("expected store-a to route to the pod, got %v", configMap.Data)
	}
	hash := daemonSet.Spec.Template.Annotations[nodeLocalPeerConfigHashAnnotation]

	// The Tailscale operator points the Service at its proxies; a later pass
	// must leave that alone. The pod restarts with a new address and the
	// demux rolls onto it.
	egress.Spec.ExternalName = "ts-kura-acme-ber1-peer-abcde.tailscale-operator.svc.cluster.local"
	if err := cluster.Update(ctx, egress); err != nil {
		t.Fatal(err)
	}
	pod.Status.PodIP = "10.254.254.20"
	if err := cluster.Status().Update(ctx, pod); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	if err := cluster.Get(ctx, client.ObjectKeyFromObject(egress), egress); err != nil {
		t.Fatal(err)
	}
	if egress.Spec.ExternalName != "ts-kura-acme-ber1-peer-abcde.tailscale-operator.svc.cluster.local" {
		t.Fatalf("the operator's externalName was overwritten with %q", egress.Spec.ExternalName)
	}
	if err := cluster.Get(ctx, client.ObjectKeyFromObject(daemonSet), daemonSet); err != nil {
		t.Fatal(err)
	}
	if daemonSet.Spec.Template.Annotations[nodeLocalPeerConfigHashAnnotation] == hash {
		t.Fatal("expected the demux to roll onto the pod's new address")
	}

	// Once the instance is gone, so is its plane.
	if err := cluster.Delete(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	if err := cluster.Get(ctx, client.ObjectKeyFromObject(egress), egress); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the egress Service to be deleted, got %v", err)
	}
	if err := cluster.Get(ctx, client.ObjectKeyFromObject(daemonSet), daemonSet); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the demux to be deleted, got %v", err)
	}
}

func TestNodeLocalPeerReconcileLeavesServicesItDoesNotOwn(t *testing.T) {
	ctx := context.Background()
	instance := nodeLocalMeshInstance("kura-acme-ber1", "acme")
	pod := nodeLocalPod(instance, "0", "ber1-store-a", "10.254.254.10")
	foreign := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Namespace: testEgressNamespace, Name: "kura-acme-ber1-peer"},
		Spec:       corev1.ServiceSpec{Type: corev1.ServiceTypeExternalName, ExternalName: "elsewhere.example.com"},
	}
	reconciler, cluster := nodeLocalPeerTestReconciler(t, instance, pod, foreign)

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: "ber1-runners", Namespace: "kura"}}); err == nil {
		t.Fatal("expected the reconcile to refuse to take over a Service it did not create")
	}
	if err := cluster.Get(ctx, client.ObjectKeyFromObject(foreign), foreign); err != nil {
		t.Fatal(err)
	}
	if foreign.Spec.ExternalName != "elsewhere.example.com" {
		t.Fatalf("the foreign Service was rewritten: %+v", foreign.Spec)
	}
}

func TestNodeLocalPeerReconcileWithoutEgressConfigurationStillRunsTheDemux(t *testing.T) {
	ctx := context.Background()
	instance := nodeLocalMeshInstance("kura-acme-ber1", "acme")
	pod := nodeLocalPod(instance, "0", "ber1-store-a", "10.254.254.10")
	reconciler, cluster := nodeLocalPeerTestReconciler(t, instance, pod)
	reconciler.EgressProxyGroup = ""

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: "ber1-runners", Namespace: "kura"}}); err != nil {
		t.Fatal(err)
	}
	if err := cluster.Get(ctx, types.NamespacedName{Namespace: testEgressNamespace, Name: "kura-acme-ber1-peer"}, &corev1.Service{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no egress Service without a ProxyGroup, got %v", err)
	}
	if err := cluster.Get(ctx, types.NamespacedName{Namespace: "kura", Name: "kura-node-local-peer-ber1-runners"}, &appsv1.DaemonSet{}); err != nil {
		t.Fatalf("expected the demux regardless: %v", err)
	}
}
