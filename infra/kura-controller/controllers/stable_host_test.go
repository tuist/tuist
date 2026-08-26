package controllers

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

const (
	stableHostRegional = "tuist-eu-central-1.kura.tuist.dev"
	stableHostStable   = "tuist.kura.tuist.dev"
)

func stableHostInstance(name string, region string, ingressClass string, stable string) *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           region,
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-" + region + ".kura.tuist.dev",
			StableHost:       stable,
			IngressClassName: ingressClass,
			StorageClassName: "hcloud-volumes",
		},
	}
}

func stableHostReconciler(t *testing.T, objects ...client.Object) (*KuraInstanceReconciler, *runtime.Scheme) {
	t.Helper()

	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	scheme.AddKnownTypeWithName(certificateGVK(), &unstructured.Unstructured{})

	builder := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...)
	for _, object := range objects {
		if instance, ok := object.(*kurav1alpha1.KuraInstance); ok {
			builder = builder.WithStatusSubresource(instance)
		}
	}

	return &KuraInstanceReconciler{Client: builder.Build(), Scheme: scheme, GRPCClusterIssuer: "letsencrypt-prod"}, scheme
}

func ingressHosts(t *testing.T, reconciler *KuraInstanceReconciler, name string) []string {
	t.Helper()

	ingress := &networkingv1.Ingress{}
	if err := reconciler.Get(context.Background(), types.NamespacedName{Name: name, Namespace: "kura"}, ingress); err != nil {
		t.Fatalf("get ingress %s: %v", name, err)
	}

	hosts := make([]string, 0, len(ingress.Spec.Rules))
	for _, rule := range ingress.Spec.Rules {
		hosts = append(hosts, rule.Host)
	}
	return hosts
}

func reconcileStableHost(t *testing.T, reconciler *KuraInstanceReconciler, name string) {
	t.Helper()

	request := ctrl.Request{NamespacedName: types.NamespacedName{Name: name, Namespace: "kura"}}
	if _, err := reconciler.Reconcile(context.Background(), request); err != nil {
		t.Fatalf("reconcile %s: %v", name, err)
	}
}

// The name a client wrote down has to answer alongside the regional one, not
// instead of it: existing .bazelrc.tuist files and published endpoint rows
// still carry the regional host.
func TestStableHostIsServedAlongsideTheRegionalHost(t *testing.T) {
	instance := stableHostInstance("kura-tuist-eu-central-1", "eu-central-1", "kura-eu-central", stableHostStable)
	reconciler, _ := stableHostReconciler(t, instance)

	reconcileStableHost(t, reconciler, instance.Name)

	hosts := ingressHosts(t, reconciler, instance.Name)
	if len(hosts) != 2 || hosts[0] != stableHostRegional || hosts[1] != stableHostStable {
		t.Fatalf("public ingress hosts = %v, want [%s %s]", hosts, stableHostRegional, stableHostStable)
	}

	grpcHosts := ingressHosts(t, reconciler, instance.Name+"-grpc")
	if len(grpcHosts) != 2 || grpcHosts[1] != stableHostStable {
		t.Fatalf("grpc ingress hosts = %v, want the stable host too", grpcHosts)
	}
}

// TLS has to cover it, or the name resolves and then fails the handshake.
func TestStableHostIsCoveredByTheCertificate(t *testing.T) {
	instance := stableHostInstance("kura-tuist-eu-central-1", "eu-central-1", "kura-eu-central", stableHostStable)
	reconciler, _ := stableHostReconciler(t, instance)

	reconcileStableHost(t, reconciler, instance.Name)

	certificate := &unstructured.Unstructured{}
	certificate.SetGroupVersionKind(certificateGVK())
	name := types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: "kura"}
	if err := reconciler.Get(context.Background(), name, certificate); err != nil {
		t.Fatalf("get certificate: %v", err)
	}

	names, _, err := unstructured.NestedStringSlice(certificate.Object, "spec", "dnsNames")
	if err != nil {
		t.Fatal(err)
	}
	if len(names) != 2 || names[0] != stableHostRegional || names[1] != stableHostStable {
		t.Fatalf("dnsNames = %v, want both hosts", names)
	}

	tls := &networkingv1.Ingress{}
	if err := reconciler.Get(context.Background(), types.NamespacedName{Name: instance.Name, Namespace: "kura"}, tls); err != nil {
		t.Fatal(err)
	}
	if len(tls.Spec.TLS) != 1 || len(tls.Spec.TLS[0].Hosts) != 2 {
		t.Fatalf("ingress TLS = %+v, want one block covering both hosts", tls.Spec.TLS)
	}
}

// The move: the control plane clears the field on the region being left and
// sets it on the destination. external-dns sees the host leave one Ingress and
// arrive at another, and repoints the record.
func TestStableHostMovesBetweenRegionsWithoutTouchingTheRegionalHosts(t *testing.T) {
	source := stableHostInstance("kura-tuist-eu-central-1", "eu-central-1", "kura-eu-central", stableHostStable)
	destination := stableHostInstance("kura-tuist-us-east-1", "us-east-1", "kura-us-east", "")
	reconciler, _ := stableHostReconciler(t, source, destination)

	reconcileStableHost(t, reconciler, source.Name)
	reconcileStableHost(t, reconciler, destination.Name)

	if hosts := ingressHosts(t, reconciler, destination.Name); len(hosts) != 1 {
		t.Fatalf("destination hosts before the move = %v, want only its regional host", hosts)
	}

	// Placement moves the name.
	moved := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(context.Background(), types.NamespacedName{Name: source.Name, Namespace: "kura"}, moved); err != nil {
		t.Fatal(err)
	}
	moved.Spec.StableHost = ""
	if err := reconciler.Update(context.Background(), moved); err != nil {
		t.Fatal(err)
	}

	arriving := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(context.Background(), types.NamespacedName{Name: destination.Name, Namespace: "kura"}, arriving); err != nil {
		t.Fatal(err)
	}
	arriving.Spec.StableHost = stableHostStable
	if err := reconciler.Update(context.Background(), arriving); err != nil {
		t.Fatal(err)
	}

	reconcileStableHost(t, reconciler, source.Name)
	reconcileStableHost(t, reconciler, destination.Name)

	sourceHosts := ingressHosts(t, reconciler, source.Name)
	if len(sourceHosts) != 1 || sourceHosts[0] != stableHostRegional {
		t.Fatalf("source hosts after the move = %v, want only its regional host", sourceHosts)
	}

	destinationHosts := ingressHosts(t, reconciler, destination.Name)
	if len(destinationHosts) != 2 || destinationHosts[1] != stableHostStable {
		t.Fatalf("destination hosts after the move = %v, want the stable host too", destinationHosts)
	}

	// The regional names are what existing clients and the mesh still use, so
	// a move must not disturb either instance's own host.
	if destinationHosts[0] != "tuist-us-east-1.kura.tuist.dev" {
		t.Fatalf("destination regional host = %s, changed by the move", destinationHosts[0])
	}
}

// An account with instances in several regions has exactly one of them
// answering on the name, so the record has one target rather than a set that
// would split its cache across regions.
func TestStableHostIsCarriedByOneInstanceOfAMultiRegionAccount(t *testing.T) {
	primary := stableHostInstance("kura-tuist-eu-central-1", "eu-central-1", "kura-eu-central", stableHostStable)
	secondary := stableHostInstance("kura-tuist-us-east-1", "us-east-1", "kura-us-east", "")
	reconciler, _ := stableHostReconciler(t, primary, secondary)

	reconcileStableHost(t, reconciler, primary.Name)
	reconcileStableHost(t, reconciler, secondary.Name)

	carrying := 0
	for _, name := range []string{primary.Name, secondary.Name} {
		for _, host := range ingressHosts(t, reconciler, name) {
			if host == stableHostStable {
				carrying++
			}
		}
	}

	if carrying != 1 {
		t.Fatalf("%d instances carry the stable host, want exactly 1", carrying)
	}
}

// On the bare-metal regions every managed region is, the per-account record is
// what pins an account to its box. Without it the region-independent name only
// has the Ingress-sourced record, which targets every cache node, so a client
// lands on an arbitrary box and is proxied cross-box outside the egress shaping.
func TestStableHostGetsItsOwnPerAccountDNSRecord(t *testing.T) {
	instance := stableHostInstance("kura-tuist-eu-central-1", "eu-central-1", "kura-eu-central", stableHostStable)
	instance.Spec.PublicHostNetwork = true

	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "box-1"},
		Status:     corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.7"}}},
	}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "kura-tuist-eu-central-1-0",
			Namespace: "kura",
			Labels:    map[string]string{"app.kubernetes.io/name": "kura", "app.kubernetes.io/instance": instance.Name},
		},
		Spec: corev1.PodSpec{NodeName: "box-1"},
	}

	scheme, mapper := dnsEndpointScheme(t)

	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance, node, pod).Build(),
		Scheme: scheme,
	}

	if err := reconciler.reconcilePublicDNSEndpoint(context.Background(), instance); err != nil {
		t.Fatalf("reconcile dns endpoint: %v", err)
	}

	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	name := types.NamespacedName{Name: instance.Name + "-public-dns", Namespace: "kura"}
	if err := reconciler.Get(context.Background(), name, endpoint); err != nil {
		t.Fatalf("get dns endpoint: %v", err)
	}

	records, _, err := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 2 {
		t.Fatalf("%d records, want one per customer host", len(records))
	}

	hosts := make([]string, 0, 2)
	for _, record := range records {
		entry, _ := record.(map[string]interface{})
		hosts = append(hosts, entry["dnsName"].(string))
		targets, _ := entry["targets"].([]interface{})
		if len(targets) != 1 || targets[0].(string) != "203.0.113.7" {
			t.Fatalf("record %v does not point at the account's box", entry["dnsName"])
		}
	}
	if hosts[0] != stableHostRegional || hosts[1] != stableHostStable {
		t.Fatalf("records = %v, want both customer hosts", hosts)
	}
}

// Clearing the regional host still deletes everything, so the stable host
// cannot keep an Ingress alive for an instance that has none.
func TestStableHostDoesNotOutliveThePublicHost(t *testing.T) {
	instance := stableHostInstance("kura-tuist-eu-central-1", "eu-central-1", "kura-eu-central", stableHostStable)
	reconciler, _ := stableHostReconciler(t, instance)

	reconcileStableHost(t, reconciler, instance.Name)

	cleared := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(context.Background(), types.NamespacedName{Name: instance.Name, Namespace: "kura"}, cleared); err != nil {
		t.Fatal(err)
	}
	cleared.Spec.PublicHost = ""
	if err := reconciler.Update(context.Background(), cleared); err != nil {
		t.Fatal(err)
	}

	reconcileStableHost(t, reconciler, instance.Name)

	ingress := &networkingv1.Ingress{}
	err := reconciler.Get(context.Background(), types.NamespacedName{Name: instance.Name, Namespace: "kura"}, ingress)
	if err == nil || !apierrors.IsNotFound(err) {
		t.Fatalf("public ingress still present with no public host: %v", err)
	}
}
