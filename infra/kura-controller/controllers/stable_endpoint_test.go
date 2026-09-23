package controllers

import (
	"context"
	"errors"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

type fakeStableDNS struct {
	record  *StableDNSRecord
	err     error
	ensures int
}

func TestStableWithdrawalFailureStillRepairsWorkload(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, dns, _ := stableFixture(t)
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	instance.Spec.StableAdvertise = false
	instance.Spec.Image = "ghcr.io/tuist/kura:repair"
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	dns.err = errors.New("AWS unavailable")
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal("withdrawal failure prevented workload repair:", err)
	}
	if sts.Spec.Template.Spec.Containers[0].Image != instance.Spec.Image {
		t.Fatal("withdrawal failure prevented image convergence")
	}
	ingress := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, ingress); err != nil {
		t.Fatal(err)
	}
	if len(ingress.Spec.Rules) != 2 || ingress.Spec.Rules[1].Host != "acme.cache.tuist.dev" {
		t.Fatal("repair dropped retained stable routing")
	}
}

func TestStableWithdrawalBeforePublicationNeedsNoProviderOrDrain(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, _, probe := stableFixture(t)
	probe.err = errors.New("certificate not ready")
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	if instance.Status.StableEndpoint == nil || instance.Status.StableEndpoint.Target != "" {
		t.Fatal("expected persisted identity without publication")
	}
	r.StableDNS = nil
	done, err := r.withdrawStableEndpoint(ctx, instance)
	if err != nil || !done || instance.Status.StableEndpoint != nil {
		t.Fatalf("unpublished identity should withdraw immediately: done=%v err=%v", done, err)
	}
}

func (f *fakeStableDNS) EnsureHealthCheck(context.Context, string) (string, error) {
	f.ensures++
	return "health-box", f.err
}
func (f *fakeStableDNS) Record(context.Context, string, string) (*StableDNSRecord, error) {
	return f.record, f.err
}

type fakeStableProbe struct {
	err          error
	host, target string
	during       func()
}

func (p *fakeStableProbe) Probe(_ context.Context, host, target string) error {
	p.host, p.target = host, target
	if p.during != nil {
		p.during()
	}
	return p.err
}

func TestStableReadinessPublishesCompletedObservations(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, dns, probe := stableFixture(t)
	dns.record = &StableDNSRecord{Target: "203.0.113.20", AWSRegion: "eu-west-3", HealthCheckID: "health-box"}
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	checkedAt := instance.Status.StableEndpoint.LastCheckedAt
	probe.during = func() {
		observed := &kurav1alpha1.KuraInstance{}
		if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, observed); err != nil {
			t.Fatal(err)
		}
		if !observed.Status.StableEndpoint.Ready || observed.Status.StableEndpoint.LastCheckedAt != checkedAt {
			t.Fatal("published an incomplete readiness observation while probing a serving endpoint")
		}
	}
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	checkedAt = instance.Status.StableEndpoint.LastCheckedAt
	probe.err = errors.New("gateway unavailable")
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	observed := &kurav1alpha1.KuraInstance{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, observed); err != nil {
		t.Fatal(err)
	}
	if observed.Status.StableEndpoint.Ready {
		t.Fatal("completed gateway failure did not clear readiness")
	}
	probe.during, probe.err = nil, nil
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	dns.err = context.DeadlineExceeded
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("lost provider error: %v", err)
	}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, observed); err != nil {
		t.Fatal(err)
	}
	if observed.Status.StableEndpoint.Ready {
		t.Fatal("completed provider failure did not clear readiness")
	}
}

func stableFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, []corev1.Pod, map[string]runtimeStatus, *fakeStableDNS, *fakeStableProbe) {
	t.Helper()
	scheme, mapper := dnsEndpointScheme(t)
	scheme.AddKnownTypeWithName(certificateGVK(), &unstructured.Unstructured{})
	instance := hostNetworkPublicInstance("kura-acme-eu-west", "eu-west", "acme-eu-west.kura.tuist.dev")
	instance.UID = "instance-uid"
	instance.Generation = 7
	instance.Spec.StableHost = "acme.cache.tuist.dev"
	instance.Spec.StableAWSRegion = "eu-west-3"
	instance.Spec.StableAdvertise = true
	instance.Spec.IngressClassName = "kura-eu-west"
	pod := corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: labels(instance)}, Spec: corev1.PodSpec{NodeName: "box"}, Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box"}, Status: corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.20"}}}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithStatusSubresource(instance).WithObjects(instance, &pod, node).Build()
	dns, probe := &fakeStableDNS{}, &fakeStableProbe{}
	r := &KuraInstanceReconciler{Client: c, APIReader: c, Scheme: scheme, StableDNS: dns, StableProbe: probe, GRPCClusterIssuer: "issuer"}
	return r, instance, []corev1.Pod{pod}, map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true}}, dns, probe
}

func TestStableAdvertisingWaitsForGatewayAndProvider(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, dns, probe := stableFixture(t)
	probe.err = errors.New("certificate not ready")
	reconcile := func() {
		t.Helper()
		if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
			t.Fatal(err)
		}
	}
	reconcile()
	if dns.ensures != 0 {
		t.Fatal("created health check before gateway readiness")
	}
	endpoint := stableDNSEndpoint(instance)
	if err := r.Get(ctx, types.NamespacedName{Name: endpoint.GetName(), Namespace: instance.Namespace}, endpoint); !apierrors.IsNotFound(err) {
		t.Fatalf("published before ready: %v", err)
	}
	probe.err = nil
	reconcile()
	if instance.Status.StableEndpoint.Ready {
		t.Fatal("Kubernetes intent alone cannot make endpoint ready")
	}
	if probe.host != instance.Spec.StableHost || probe.target != "203.0.113.20" {
		t.Fatal("did not probe stable SNI directly on the primary's box")
	}
	if err := r.Get(ctx, types.NamespacedName{Name: endpoint.GetName(), Namespace: instance.Namespace}, endpoint); err != nil {
		t.Fatal(err)
	}
	records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	record := records[0].(map[string]interface{})
	if record["setIdentifier"] != "eu-west" || record["dnsName"] != instance.Spec.StableHost || record["recordTTL"] != int64(60) {
		t.Fatalf("wrong regional latency record: %v", record)
	}
	provider, _, _ := unstructured.NestedSlice(record, "providerSpecific")
	if provider[0].(map[string]interface{})["value"] != "eu-west-3" || provider[1].(map[string]interface{})["value"] != "health-box" {
		t.Fatalf("wrong Route53 metadata: %v", provider)
	}
	rv := endpoint.GetResourceVersion()
	dns.record = &StableDNSRecord{Target: "203.0.113.20", AWSRegion: "eu-west-3", HealthCheckID: "health-box"}
	reconcile()
	if !instance.Status.StableEndpoint.Ready {
		t.Fatal("published and serving endpoint did not become ready")
	}
	// Primary/secondary role is not a controller input. The same serving intent
	// after a role reassignment must not rewrite the DNS source or health check.
	reconcile()
	if err := r.Get(ctx, types.NamespacedName{Name: endpoint.GetName(), Namespace: instance.Namespace}, endpoint); err != nil {
		t.Fatal(err)
	}
	if endpoint.GetResourceVersion() != rv || dns.ensures != 1 {
		t.Fatal("steady serving intent mutated its advertisement")
	}
}

func TestStableWithdrawalRetainsRenderingThroughStallAndDrain(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, dns, _ := stableFixture(t)
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	dns.record = &StableDNSRecord{Target: "203.0.113.20"}
	instance.Spec.StableHost = ""
	instance.Spec.StableAdvertise = false
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	done, err := r.withdrawStableEndpoint(ctx, instance)
	if err != nil || done {
		t.Fatalf("stalled writer released routing: %v %v", done, err)
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileGRPCIngress(ctx, instance, pods, samples, pods[0].Name); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{instance.Name, grpcServiceName(instance)} {
		ingress := &networkingv1.Ingress{}
		if err := r.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, ingress); err != nil {
			t.Fatal(err)
		}
		if len(ingress.Spec.Rules) != 2 || ingress.Spec.Rules[1].Host != "acme.cache.tuist.dev" {
			t.Fatal("withdrawal removed stable routing")
		}
		if ingress.Annotations["external-dns.alpha.kubernetes.io/ingress-hostname-source"] != "annotation-only" {
			t.Fatal("ingress remains a second DNS producer")
		}
	}
	dns.err = errors.New("AWS unavailable")
	if done, err := r.withdrawStableEndpoint(ctx, instance); done || err == nil {
		t.Fatal("failed provider read treated as absence")
	}
	dns.err, dns.record = nil, nil
	if done, err := r.withdrawStableEndpoint(ctx, instance); done || err != nil {
		t.Fatal("did not start post-withdrawal drain")
	}
	if instance.Status.StableEndpoint.WithdrawnAt == "" {
		t.Fatal("drain observation not persisted")
	}
	// A controller restart reconstructs the barrier solely from API status.
	restarted := &kurav1alpha1.KuraInstance{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, restarted); err != nil {
		t.Fatal(err)
	}
	if done, err := r.withdrawStableEndpoint(ctx, restarted); done || err != nil {
		t.Fatal("restart lost drain")
	}
	restarted.Status.StableEndpoint.WithdrawnAt = time.Now().Add(-3721 * time.Second).UTC().Format(time.RFC3339)
	if done, err := r.withdrawStableEndpoint(ctx, restarted); !done || err != nil {
		t.Fatalf("completed drain still blocked: %v %v", done, err)
	}
	if len(stableClientHosts(restarted)) != 1 {
		t.Fatal("retained removed hostname after completed drain")
	}
}

func TestStablePrivateAndUnreadyInstancesNeverAdvertise(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, dns, _ := stableFixture(t)
	instance.Spec.Private = true
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	if instance.Status.StableEndpoint != nil || dns.ensures != 0 {
		t.Fatal("private instance acquired stable DNS")
	}
	instance.Spec.Private = false
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, nil); err != nil {
		t.Fatal(err)
	}
	if dns.ensures != 0 {
		t.Fatal("stale runtime status allowed advertising")
	}
}

func TestStableFinalizerCannotRemoveAdvertisedInstance(t *testing.T) {
	ctx := context.Background()
	r, instance, pods, samples, dns, _ := stableFixture(t)
	instance.Finalizers = []string{KuraInstanceFinalizer}
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileStableEndpoint(ctx, instance, pods[0].Name, pods, samples); err != nil {
		t.Fatal(err)
	}
	dns.record = &StableDNSRecord{Target: "203.0.113.20"}
	if err := r.Delete(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, instance); err != nil {
		t.Fatal(err)
	}
	result, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}})
	if err != nil || result.RequeueAfter == 0 {
		t.Fatalf("deletion bypassed provider withdrawal: %v %v", result, err)
	}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, instance); err != nil {
		t.Fatal(err)
	}
	if len(instance.Finalizers) != 1 {
		t.Fatal("removed finalizer while DNS still points at instance")
	}
}

func TestStableTLSKeepsRegionalWildcardWhileIssuanceIsPending(t *testing.T) {
	ctx := context.Background()
	r, instance, _, _, _, _ := stableFixture(t)
	r.PublicTLSSecretName = "shared-wildcard"
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: r.PublicTLSSecretName, Namespace: instance.Namespace}, Data: map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev")}}
	if err := r.Create(ctx, secret); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicCertificate(ctx, instance); err != nil {
		t.Fatal(err)
	}
	ingress := &networkingv1.Ingress{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, ingress); err != nil {
		t.Fatal(err)
	}
	if len(ingress.Spec.TLS) != 2 || ingress.Spec.TLS[0].SecretName != r.PublicTLSSecretName || ingress.Spec.TLS[1].SecretName != publicTLSSecretName(instance) {
		t.Fatalf("regional TLS disrupted during stable issuance: %+v", ingress.Spec.TLS)
	}
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); err != nil {
		t.Fatal(err)
	}
	names, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames")
	if len(names) != 2 {
		t.Fatalf("certificate must cover both names: %v", names)
	}
}
