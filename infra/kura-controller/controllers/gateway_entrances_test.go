package controllers

import (
	"context"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type hostResolver map[string][]string

func (resolver hostResolver) LookupHost(_ context.Context, host string) ([]string, error) {
	return resolver[host], nil
}

// gatewayEntranceFixture is a private instance at one site (gateway on node-a,
// 172.16.0.2) with an entrance on another site's gateway (node-b, 10.20.0.11),
// both covered by the shared wildcard.
func gatewayEntranceFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, *corev1.Pod, *corev1.Node) {
	t.Helper()
	r, instance, pod := privateGatewayFixture(t)
	ctx := context.Background()
	instance.Spec.PrivateHost = "tuist-alder-runners.kura.tuist.dev"
	instance.Spec.NodeSelector = map[string]string{"pool": "alder"}
	instance.Spec.GatewayEntrances = []kurav1alpha1.GatewayEntrance{{
		Site:             "larch",
		Host:             "tuist-alder-runners-via-larch.kura.tuist.dev",
		IngressClassName: "kura-larch-runners",
		ClientCIDRs:      []string{"10.20.0.0/24"},
		NodeSelector:     map[string]string{"pool": "larch"},
		RateLimitKBps:    25600,
		ConnectionLimit:  64,
	}}
	nodeA := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: "node-a"}, nodeA); err != nil {
		t.Fatal(err)
	}
	nodeA.Labels["pool"] = "alder"
	if err := r.Update(ctx, nodeA); err != nil {
		t.Fatal(err)
	}
	nodeB := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "node-b", Labels: map[string]string{"tuist.dev/pn-ipv4": "10.20.0.11", "pool": "larch"}}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	gatewayB := pod.DeepCopy()
	gatewayB.Name = "gateway-b"
	gatewayB.Namespace = "platform"
	gatewayB.ResourceVersion = ""
	gatewayB.Spec.NodeName = "node-b"
	gatewayB.Spec.HostNetwork = true
	gatewayB.Labels = map[string]string{gatewayClassLabel: "kura-larch-runners"}
	wildcard := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-public-wildcard-tls", Namespace: instance.Namespace},
		Data:       map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev")},
	}
	for _, object := range []client.Object{nodeB, gatewayB, wildcard} {
		if err := r.Create(ctx, object); err != nil {
			t.Fatal(err)
		}
	}
	r.PublicTLSSecretName = wildcard.Name
	r.PeerDNSResolver = hostResolver{
		instance.Spec.PrivateHost:              {"172.16.0.2"},
		instance.Spec.GatewayEntrances[0].Host: {"10.20.0.11"},
	}
	return r, instance, pod, nodeB
}

func TestGatewayEntranceRendersOnTheOtherSitesGateway(t *testing.T) {
	r, instance, pod, _ := gatewayEntranceFixture(t)
	ctx := context.Background()
	entrance := instance.Spec.GatewayEntrances[0]
	if err := r.reconcileGatewayEntrances(ctx, instance, []corev1.Pod{*pod}, nil, pod.Name); err != nil {
		t.Fatal(err)
	}

	ingress := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayEntranceName(instance, "larch"), Namespace: instance.Namespace}, ingress); err != nil {
		t.Fatal(err)
	}
	if *ingress.Spec.IngressClassName != "kura-larch-runners" || ingress.Spec.Rules[0].Host != entrance.Host ||
		ingress.Spec.Rules[0].HTTP.Paths[0].Backend.Service.Name != instance.Name {
		t.Fatalf("entrance must route the other site's class and host to the instance's primary Service: %+v", ingress.Spec)
	}
	if ingress.Spec.TLS[0].SecretName != "kura-public-wildcard-tls" || ingress.Spec.TLS[0].Hosts[0] != entrance.Host {
		t.Fatalf("entrance must terminate on the shared wildcard: %v", ingress.Spec.TLS)
	}
	annotations := ingress.Annotations
	// The entrance admits the other site's runners, not the instance's own.
	if annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] != "10.20.0.0/24" {
		t.Fatalf("entrance source range: %v", annotations)
	}
	// limit-rate is a no-op unless proxy buffering is on; buffers stay in memory.
	if annotations["nginx.ingress.kubernetes.io/limit-rate"] != "25600" ||
		annotations["nginx.ingress.kubernetes.io/proxy-buffering"] != "on" ||
		annotations["nginx.ingress.kubernetes.io/proxy-max-temp-file-size"] != "0" ||
		annotations["nginx.ingress.kubernetes.io/limit-connections"] != "64" {
		t.Fatalf("entrance limits: %v", annotations)
	}
	grpc := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayEntranceGRPCName(instance, "larch"), Namespace: instance.Namespace}, grpc); err != nil {
		t.Fatal(err)
	}
	if *grpc.Spec.IngressClassName != "kura-larch-runners" || grpc.Spec.Rules[0].Host != entrance.Host ||
		grpc.Annotations["nginx.ingress.kubernetes.io/backend-protocol"] != "GRPC" {
		t.Fatalf("entrance gRPC Ingress: %+v %v", grpc.Spec, grpc.Annotations)
	}

	dns := &unstructured.Unstructured{}
	dns.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayEntranceDNSName(instance, "larch"), Namespace: instance.Namespace}, dns); err != nil {
		t.Fatal(err)
	}
	if targets := r.gatewayEntranceDNSTargets(ctx, instance, entrance); len(targets) != 1 || targets[0] != "10.20.0.11" {
		t.Fatalf("entrance DNS must name the other site's gateway, not the instance's own: %v", targets)
	}

	// The instance's own Ingress keeps its own class and source range.
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	own := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, own); err != nil {
		t.Fatal(err)
	}
	if *own.Spec.IngressClassName != "kura-runners" || own.Annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] != "172.16.0.0/22" ||
		own.Annotations["nginx.ingress.kubernetes.io/limit-rate"] != "" || own.Annotations["nginx.ingress.kubernetes.io/proxy-buffering"] != "off" {
		t.Fatalf("instance's own Ingress must be unchanged by an entrance: %v %v", *own.Spec.IngressClassName, own.Annotations)
	}
}

func TestGatewayEntranceStatusFollowsItsOwnSite(t *testing.T) {
	r, instance, pod, nodeB := gatewayEntranceFixture(t)
	ctx := context.Background()
	pods := []corev1.Pod{*pod}
	samples := map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1}}
	if err := r.reconcileGatewayEntrances(ctx, instance, pods, samples, pod.Name); err != nil {
		t.Fatal(err)
	}
	now := metav1.Now()
	statuses := r.gatewayEntranceStatuses(ctx, instance, pod.Name, pods, samples, now)
	if len(statuses) != 1 || statuses[0].URL != "https://tuist-alder-runners-via-larch.kura.tuist.dev" || statuses[0].Reason != "Ready" {
		t.Fatalf("ready entrance must publish its URL: %+v", statuses)
	}

	// A primary that is not serving takes every entrance down with it.
	if statuses := r.gatewayEntranceStatuses(ctx, instance, pod.Name, pods, map[string]runtimeStatus{}, now); statuses[0].URL != "" || statuses[0].Reason != "PrimaryStatusUnavailable" {
		t.Fatalf("entrance without a serving primary must not publish: %+v", statuses)
	}

	// The other site going dark withdraws its entrance but not the instance's
	// own host.
	nodeB.Status.Conditions = []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionFalse}}
	if err := r.Status().Update(ctx, nodeB); err != nil {
		t.Fatal(err)
	}
	statuses = r.gatewayEntranceStatuses(ctx, instance, pod.Name, pods, samples, now)
	if statuses[0].URL != "" || statuses[0].Reason != "GatewayUnavailable" {
		t.Fatalf("entrance of a dark site must not publish: %+v", statuses)
	}
	if observation, err := r.privateGatewayStatus(ctx, instance, pod.Name, pods, samples); err != nil || observation.URL == "" {
		t.Fatalf("a dark entrance site must not affect the instance's own host: %+v %v", observation, err)
	}
	// Its DNS keeps the last target rather than unpublishing a held host.
	if err := r.reconcileGatewayEntrances(ctx, instance, pods, samples, pod.Name); err != nil {
		t.Fatal(err)
	}
	if targets := r.gatewayEntranceDNSTargets(ctx, instance, instance.Spec.GatewayEntrances[0]); len(targets) != 1 || targets[0] != "10.20.0.11" {
		t.Fatalf("entrance DNS must keep its target while its gateway is down: %v", targets)
	}
}

func TestGatewayEntranceWithoutWildcardCoverageIsPending(t *testing.T) {
	r, instance, pod, _ := gatewayEntranceFixture(t)
	ctx := context.Background()
	instance.Spec.GatewayEntrances[0].Host = "tuist.via.larch.example.com"
	if err := r.reconcileGatewayEntrances(ctx, instance, []corev1.Pod{*pod}, nil, pod.Name); err != nil {
		t.Fatal(err)
	}
	ingress := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayEntranceName(instance, "larch"), Namespace: instance.Namespace}, ingress); err != nil {
		t.Fatal(err)
	}
	if len(ingress.Spec.TLS) != 0 {
		t.Fatalf("an uncovered entrance must not name a secret that does not cover it: %v", ingress.Spec.TLS)
	}
	samples := map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1}}
	statuses := r.gatewayEntranceStatuses(ctx, instance, pod.Name, []corev1.Pod{*pod}, samples, metav1.Now())
	if statuses[0].URL != "" || statuses[0].Reason != "CertificatePending" {
		t.Fatalf("uncovered entrance must not publish: %+v", statuses)
	}
}

func TestGatewayEntranceRejectsItsOwnSiteAndIsPrunedWhenRemoved(t *testing.T) {
	r, instance, pod, _ := gatewayEntranceFixture(t)
	ctx := context.Background()
	pods := []corev1.Pod{*pod}
	if err := r.reconcileGatewayEntrances(ctx, instance, pods, nil, pod.Name); err != nil {
		t.Fatal(err)
	}
	// An entrance on the instance's own gateway class is a misconfiguration:
	// it would serve the same site twice.
	own := instance.Spec.GatewayEntrances[0]
	own.Site = "self"
	own.Host = "tuist-self.kura.tuist.dev"
	own.IngressClassName = instance.Spec.IngressClassName
	instance.Spec.GatewayEntrances = append(instance.Spec.GatewayEntrances, own)
	if err := r.reconcileGatewayEntrances(ctx, instance, pods, nil, pod.Name); err != nil {
		t.Fatal(err)
	}
	err := r.Get(ctx, types.NamespacedName{Name: gatewayEntranceName(instance, "self"), Namespace: instance.Namespace}, &networkingv1.Ingress{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("an entrance on the instance's own class must not render: %v", err)
	}
	statuses := r.gatewayEntranceStatuses(ctx, instance, pod.Name, pods, nil, metav1.Now())
	if statuses[1].Reason != "InvalidConfiguration" {
		t.Fatalf("invalid entrance must say why: %+v", statuses[1])
	}

	instance.Spec.GatewayEntrances = nil
	if err := r.reconcileGatewayEntrances(ctx, instance, pods, nil, pod.Name); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{gatewayEntranceName(instance, "larch"), gatewayEntranceGRPCName(instance, "larch")} {
		if err := r.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, &networkingv1.Ingress{}); !apierrors.IsNotFound(err) {
			t.Fatalf("removed entrance Ingress %s must be deleted: %v", name, err)
		}
	}
	dns := &unstructured.Unstructured{}
	dns.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayEntranceDNSName(instance, "larch"), Namespace: instance.Namespace}, dns); !apierrors.IsNotFound(err) {
		t.Fatalf("removed entrance DNS must be deleted: %v", err)
	}
}
