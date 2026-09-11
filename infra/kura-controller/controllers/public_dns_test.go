package controllers

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func hostNetworkPublicInstance(name, region, host string) *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:     name,
			Region:            region,
			PublicHost:        host,
			PublicHostNetwork: true,
		},
	}
}

func dnsEndpointScheme(t *testing.T) (*runtime.Scheme, meta.RESTMapper) {
	t.Helper()
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
	return scheme, mapper
}

// On a host-network (bare-metal) region the account's customer host is published
// by a per-account DNSEndpoint pointing at the box the account's pods run on, so
// each account resolves to its own box across a multi-box region.
func TestPublicDNSEndpointPublishesBoxIP(t *testing.T) {
	ctx := context.Background()
	scheme, mapper := dnsEndpointScheme(t)

	instance := hostNetworkPublicInstance("kura-acme", "eu-west", "acme-eu-west.kura.tuist.dev")

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

	if err := reconciler.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-0"); err != nil {
		t.Fatal(err)
	}

	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: "kura-acme-public-dns", Namespace: "kura"}, endpoint); err != nil {
		t.Fatal(err)
	}
	endpoints, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if len(endpoints) != 1 {
		t.Fatalf("expected one DNS endpoint, got %v", endpoints)
	}
	record := endpoints[0].(map[string]interface{})
	if record["dnsName"] != "acme-eu-west.kura.tuist.dev" {
		t.Fatalf("expected the account's customer host as dnsName, got %v", record["dnsName"])
	}
	targets := record["targets"].([]interface{})
	if len(targets) != 1 || targets[0] != "203.0.113.50" {
		t.Fatalf("expected the account's box IP as the DNS target, got %v", targets)
	}
	// Short TTL so client re-resolution is quick when the account moves boxes.
	if ttl, _ := record["recordTTL"].(int64); ttl != 60 {
		t.Fatalf("expected a short (60s) TTL for fast re-resolution on a move, got %v", record["recordTTL"])
	}
}

// LoadBalancer regions publish the customer host off the gateway Service/Ingress,
// so the controller must never emit a per-account public DNSEndpoint there.
func TestPublicDNSEndpointSkippedOnLoadBalancerRegion(t *testing.T) {
	ctx := context.Background()
	scheme, mapper := dnsEndpointScheme(t)

	instance := hostNetworkPublicInstance("kura-acme", "eu", "acme-eu.kura.tuist.dev")
	instance.Spec.PublicHostNetwork = false

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

	if err := reconciler.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-0"); err != nil {
		t.Fatal(err)
	}

	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: "kura-acme-public-dns", Namespace: "kura"}, got); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no public DNSEndpoint on an LB region, got %v", err)
	}
}

// Until a pod is scheduled there is no box to point at; a stale DNSEndpoint from
// a prior placement must be torn down so external-dns stops publishing a dead
// record.
func TestPublicDNSEndpointDeletedWhenNoBox(t *testing.T) {
	ctx := context.Background()
	scheme, mapper := dnsEndpointScheme(t)

	existing := &unstructured.Unstructured{}
	existing.SetGroupVersionKind(dnsEndpointGVK)
	existing.SetNamespace("kura")
	existing.SetName("kura-acme-public-dns")

	instance := hostNetworkPublicInstance("kura-acme", "eu-west", "acme-eu-west.kura.tuist.dev")
	// No pods in the fake client, so instanceNodeIP finds no box -> teardown.

	client := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance, existing).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	if err := reconciler.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-0"); err != nil {
		t.Fatal(err)
	}

	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: "kura-acme-public-dns", Namespace: "kura"}, got); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the stale public DNSEndpoint to be deleted, got %v", err)
	}
}

// An account's replicas are only preferentially co-located, so they can straddle
// two boxes of a multi-box region. The public Service pins the primary, so the
// customer record has to name the primary's box: naming the other one sends
// every request across boxes, where the per-instance NetworkPolicy drops it and
// the gateway answers 504. Regression for a split account whose record named the
// box holding the non-primary replica.
func TestPublicDNSEndpointFollowsPrimaryWhenReplicasSplitBoxes(t *testing.T) {
	ctx := context.Background()
	scheme, mapper := dnsEndpointScheme(t)

	instance := hostNetworkPublicInstance("kura-acme", "us-east", "acme-us-east.kura.tuist.dev")

	labels := map[string]string{"app.kubernetes.io/name": "kura", "app.kubernetes.io/instance": "kura-acme"}
	podOn := func(name, node string) *corev1.Pod {
		return &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura", Labels: labels},
			Spec:       corev1.PodSpec{NodeName: node},
		}
	}
	nodeWith := func(name, ip string) *corev1.Node {
		return &corev1.Node{
			ObjectMeta: metav1.ObjectMeta{Name: name},
			Status:     corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: ip}}},
		}
	}

	client := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(
		instance,
		podOn("kura-acme-0", "box-1"),
		podOn("kura-acme-1", "box-2"),
		nodeWith("box-1", "203.0.113.50"),
		nodeWith("box-2", "203.0.113.51"),
	).Build()
	reconciler := &KuraInstanceReconciler{Client: client, Scheme: scheme}

	// The primary is the replica on box-2, not the first pod by name.
	if err := reconciler.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-1"); err != nil {
		t.Fatal(err)
	}

	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := client.Get(ctx, types.NamespacedName{Name: "kura-acme-public-dns", Namespace: "kura"}, endpoint); err != nil {
		t.Fatal(err)
	}
	endpoints, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if len(endpoints) != 1 {
		t.Fatalf("expected one DNS endpoint, got %v", endpoints)
	}
	targets := endpoints[0].(map[string]interface{})["targets"].([]interface{})
	if len(targets) != 1 || targets[0] != "203.0.113.51" {
		t.Fatalf("expected the primary's box IP (203.0.113.51) as the DNS target, got %v", targets)
	}
}

// Without a primary to follow the target still has to be stable: returning
// whichever pod the API server listed first let a split account's record flip
// between boxes on every reconcile, which is churn external-dns republishes.
func TestInstanceNodeIPIsStableWithoutAPreferredPod(t *testing.T) {
	ctx := context.Background()
	scheme, mapper := dnsEndpointScheme(t)

	instance := hostNetworkPublicInstance("kura-acme", "us-east", "acme-us-east.kura.tuist.dev")
	labels := map[string]string{"app.kubernetes.io/name": "kura", "app.kubernetes.io/instance": "kura-acme"}
	// Listed out of name order on purpose: the answer must not depend on it.
	c := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(
		instance,
		&corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "kura-acme-1", Namespace: "kura", Labels: labels}, Spec: corev1.PodSpec{NodeName: "box-2"}},
		&corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "kura-acme-0", Namespace: "kura", Labels: labels}, Spec: corev1.PodSpec{NodeName: "box-1"}},
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box-1"}, Status: corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.50"}}}},
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box-2"}, Status: corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.51"}}}},
	).Build()
	reconciler := &KuraInstanceReconciler{Client: c, Scheme: scheme}

	for i := 0; i < 3; i++ {
		ip, err := reconciler.instanceNodeIP(ctx, instance, "")
		if err != nil {
			t.Fatal(err)
		}
		if ip != "203.0.113.50" {
			t.Fatalf("expected the lowest-named pod's box (203.0.113.50) every time, got %v on pass %d", ip, i)
		}
	}
}
