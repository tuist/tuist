package controllers

import (
	"context"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	policyv1 "k8s.io/api/policy/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestClientGatewaySharesRolloutAndPrimaryHandover(t *testing.T) {
	for _, private := range []bool{false, true} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			scheme := meshTestScheme(t)
			instance := meshInstance("kura-tuist-test", "tuist")
			instance.Spec.Replicas = ptr(int32(2))
			instance.Spec.Private = private
			instance.Spec.PublicHost = "tuist.example.com"
			instance.Spec.PrivateHost = "tuist.private.example.com"
			instance.Spec.PublicHostNetwork = true
			instance.Spec.IngressClassName = "kura-runners"
			instance.Spec.ClientCIDRs = []string{"172.16.0.0/22"}
			instance.Spec.ExposeNodePort = private
			primary := corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: selectorLabels(instance)}, Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
			standby := *primary.DeepCopy()
			standby.Name = instance.Name + "-1"
			r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build(), Scheme: scheme, GRPCClusterIssuer: "letsencrypt"}
			if err := r.reconcileStatefulSet(ctx, instance); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcilePodDisruptionBudget(ctx, instance); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcilePublicIngress(ctx, instance); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcileGRPCIngress(ctx, instance); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcilePublicCertificate(ctx, instance); err != nil {
				t.Fatal(err)
			}
			sts := &appsv1.StatefulSet{}
			key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
			if err := r.Get(ctx, key, sts); err != nil {
				t.Fatal(err)
			}
			if (sts.Spec.UpdateStrategy.Type != "" && sts.Spec.UpdateStrategy.Type != appsv1.RollingUpdateStatefulSetStrategyType) || *sts.Spec.Replicas != 2 {
				t.Fatalf("expected standard two-replica rollout: %+v", sts.Spec.UpdateStrategy)
			}
			if len(sts.Spec.Template.Spec.Affinity.PodAffinity.RequiredDuringSchedulingIgnoredDuringExecution) != 0 {
				t.Fatal("co-location must remain preferred")
			}
			pdb := &policyv1.PodDisruptionBudget{}
			if err := r.Get(ctx, key, pdb); err != nil {
				t.Fatal(err)
			}
			if pdb.Spec.MinAvailable.IntVal != 1 {
				t.Fatal("expected one available replica")
			}
			for _, ingressName := range []string{instance.Name, grpcServiceName(instance)} {
				ingress := &networkingv1.Ingress{}
				if err := r.Get(ctx, types.NamespacedName{Name: ingressName, Namespace: instance.Namespace}, ingress); err != nil {
					t.Fatal(err)
				}
				if ingress.Spec.Rules[0].Host != clientHost(instance) || ingress.Spec.Rules[0].HTTP.Paths[0].Backend.Service.Name != instance.Name {
					t.Fatal("gateway must route through the common primary service")
				}
				if private && ingress.Annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] != "172.16.0.0/22" {
					t.Fatal("HTTP and gRPC must enforce the private network allowlist")
				}
			}
			// A draining primary yields to the ready mesh member through the same
			// selector. Neither client hostname nor the retained NodePort changes.
			if err := r.reconcileService(ctx, instance, primary.Name); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcileExternalService(ctx, instance, primary.Name); err != nil {
				t.Fatal(err)
			}
			if private {
				legacy := &corev1.Service{}
				if err := r.Get(ctx, types.NamespacedName{Name: instance.Name + "-external", Namespace: instance.Namespace}, legacy); err != nil {
					t.Fatal(err)
				}
				legacy.Spec.Ports[0].NodePort = 30080
				if err := r.Update(ctx, legacy); err != nil {
					t.Fatal(err)
				}
			}
			now := metav1.Now()
			primary.DeletionTimestamp = &now
			status := runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1, BackfillInitialCycle: backfillCycleComplete}
			selected, _, err := r.selectPrimaryPod(ctx, instance, []corev1.Pod{primary, standby}, map[string]runtimeStatus{standby.Name: status})
			if err != nil {
				t.Fatal(err)
			}
			if selected != standby.Name {
				t.Fatalf("expected standby, got %s", selected)
			}
			if err := r.reconcileService(ctx, instance, selected); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcileExternalService(ctx, instance, selected); err != nil {
				t.Fatal(err)
			}
			if private {
				legacy := &corev1.Service{}
				if err := r.Get(ctx, types.NamespacedName{Name: instance.Name + "-external", Namespace: instance.Namespace}, legacy); err != nil {
					t.Fatal(err)
				}
				if legacy.Spec.Ports[0].NodePort != 30080 || legacy.Spec.Selector[podNameLabel] != standby.Name {
					t.Fatal("legacy NodePort must survive the primary handover")
				}
			}
		})
	}
}

// An ACME wildcard spans exactly one label, so a gateway host in another zone
// keeps ordering for itself.
func TestPrivateGatewayKeepsItsCertificateForHostOutsideWildcard(t *testing.T) {
	ctx := context.Background()
	instance := sharedWildcardTLSTestInstance()
	instance.Spec.Private = true
	instance.Spec.PrivateHost = "runner.private.example.com"
	instance.Spec.PublicHostNetwork = true
	instance.Spec.ClientCIDRs = []string{"172.16.0.0/22"}
	wildcard := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-public-wildcard-tls", Namespace: instance.Namespace},
		Data:       map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev")},
	}
	scheme := meshTestScheme(t)
	r := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, wildcard).Build(),
		Scheme: scheme, GRPCClusterIssuer: "letsencrypt", PublicTLSSecretName: wildcard.Name,
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
	if ingress.Spec.TLS[0].SecretName != publicTLSSecretName(instance) || ingress.Spec.TLS[0].Hosts[0] != instance.Spec.PrivateHost {
		t.Fatalf("private gateway must use its own hostname and certificate: %v", ingress.Spec.TLS)
	}
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); err != nil {
		t.Fatal(err)
	}
	hosts, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames")
	if len(hosts) != 1 || hosts[0] != instance.Spec.PrivateHost {
		t.Fatalf("private certificate must cover privateHost: %v", hosts)
	}
}

func TestPrivateGatewayPublicationReadiness(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	instance := meshInstance("kura-tuist-test", "tuist")
	instance.Generation = 2
	instance.Spec.Private = true
	instance.Spec.PrivateHost = "private.example.com"
	instance.Spec.PublicHostNetwork = true
	instance.Spec.IngressClassName = "kura-runners"
	instance.Spec.ClientCIDRs = []string{"172.16.0.0/22"}
	instance.Spec.Replicas = ptr(int32(2))
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: selectorLabels(instance), CreationTimestamp: metav1.NewTime(time.Now().Add(-time.Hour))}, Spec: corev1.PodSpec{NodeName: "node"}, Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "node", Labels: map[string]string{"tuist.dev/pn-ipv4": "172.16.0.2"}}, Status: corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.2"}}, Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	gateway := pod.DeepCopy()
	gateway.Name = "gateway"
	gateway.Namespace = "platform"
	gateway.Labels = map[string]string{gatewayClassLabel: "kura-runners"}
	gateway.Spec.HostNetwork = true
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	cert.SetName(publicTLSSecretName(instance))
	cert.SetNamespace(instance.Namespace)
	cert.SetGeneration(1)
	unstructured.SetNestedStringSlice(cert.Object, []string{instance.Spec.PrivateHost}, "spec", "dnsNames")
	resolver := &fakePeerDNSResolver{addresses: []string{"172.16.0.2"}}
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, pod, node, gateway, cert).Build(), Scheme: scheme, PeerDNSResolver: resolver}
	samples := map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2}}
	check := func(want string) {
		t.Helper()
		r.clientDNSCache = nil
		r.gatewayCache = nil
		observation, err := r.privateGatewayStatus(ctx, instance, pod.Name, []corev1.Pod{*pod}, samples)
		if err != nil || observation.URL != want {
			t.Fatalf("got %+v, %v; want %q", observation, err, want)
		}
		if observation.Reason == "" || observation.Message == "" {
			t.Fatal("every observation must explain its outcome")
		}
	}
	check("")
	unstructured.SetNestedSlice(cert.Object, []interface{}{map[string]interface{}{"type": "Ready", "status": "True", "observedGeneration": int64(1)}}, "status", "conditions")
	if err := r.Update(ctx, cert); err != nil {
		t.Fatal(err)
	}
	check("https://private.example.com")
	status := samples[pod.Name]
	status.RingMembers = 1
	samples[pod.Name] = status
	check("https://private.example.com") // The sibling is restarting; the primary still serves.

	delete(samples, pod.Name)
	check("") // An old Ready pod is insufficient to renew endpoint freshness.
	samples[pod.Name] = status
	cert.SetGeneration(2)
	if err := r.Update(ctx, cert); err != nil {
		t.Fatal(err)
	}
	check("")
	cert.SetGeneration(1)
	if err := r.Update(ctx, cert); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-public-dns"}, endpoint); err != nil {
		t.Fatal(err)
	}
	records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	record := records[0].(map[string]interface{})
	if record["dnsName"] != instance.Spec.PrivateHost || record["targets"].([]interface{})[0] != "172.16.0.2" {
		t.Fatalf("unexpected private DNS: %v", record)
	}

	resolver.addresses = []string{"203.0.113.2"}
	check("")
	resolver.addresses = []string{"172.16.0.2", "203.0.113.2"}
	check("")
	resolver.addresses = []string{"172.16.0.2"}
	samples[pod.Name] = runtimeStatus{Ready: false}
	check("")
	samples[pod.Name] = runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2}
	if err := r.Delete(ctx, gateway); err != nil {
		t.Fatal(err)
	}
	check("")
	if got, err := r.privateGatewayTarget(ctx, instance); err != nil || got != "" {
		t.Fatalf("private DNS: %q %v", got, err)
	}
	if got, err := r.instanceNodeIP(ctx, instance, ""); err != nil || got != "203.0.113.2" {
		t.Fatalf("public peer DNS must stay public: %q %v", got, err)
	}
	instance.Spec.PublicHost = "leftover.example.com"
	instance.Spec.PrivateHost = ""
	if clientHost(instance) != "" {
		t.Fatal("legacy private instances must not expose leftover public hosts")
	}
	instance.Spec.PrivateHost = "private.example.com"
	instance.Spec.ClientCIDRs = nil
	if clientHost(instance) != "" {
		t.Fatal("empty allowlist must fail closed")
	}
	instance.Spec.ClientCIDRs = []string{"invalid"}
	if clientHost(instance) != "" {
		t.Fatal("invalid allowlist must fail closed")
	}
}

func privateGatewayFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, *corev1.Pod) {
	t.Helper()
	instance := meshInstance("kura-gateway", "tuist")
	instance.Spec.Private = true
	instance.Spec.PrivateHost = "private.example.com"
	instance.Spec.PublicHostNetwork = true
	instance.Spec.IngressClassName = "kura-runners"
	instance.Spec.ClientCIDRs = []string{"172.16.0.0/22"}
	instance.Spec.Replicas = ptr(int32(2))
	instance.Spec.StorageSize = "40Gi"
	instance.Generation = 2
	instance.Finalizers = []string{KuraInstanceFinalizer}
	pod := kuraPod(instance.Name, instance.Namespace, 0, true)
	pod.Spec.NodeName = "node-a"
	pod.Labels = selectorLabels(instance)
	gateway := pod.DeepCopy()
	gateway.Name = "gateway-a"
	gateway.Namespace = "platform"
	gateway.Spec.HostNetwork = true
	gateway.Labels = map[string]string{gatewayClassLabel: instance.Spec.IngressClassName}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "node-a", Labels: map[string]string{"tuist.dev/pn-ipv4": "172.16.0.2"}}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	scheme := meshTestScheme(t)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, pod, gateway, node).WithStatusSubresource(instance).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme, GRPCClusterIssuer: "letsencrypt", PeerDNSResolver: &fakePeerDNSResolver{addresses: []string{"172.16.0.2"}}, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1}}}}
	if err := r.reconcilePublicCertificate(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := c.Get(context.Background(), types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); err != nil {
		t.Fatal(err)
	}
	// An omitted observedGeneration is valid in cert-manager's Ready condition.
	unstructured.SetNestedSlice(cert.Object, []interface{}{map[string]interface{}{"type": "Ready", "status": "True"}}, "status", "conditions")
	if err := c.Update(context.Background(), cert); err != nil {
		t.Fatal(err)
	}
	return r, instance, pod
}

func TestPrivateEndpointIsObservedWhileStorageResizeYields(t *testing.T) {
	r, instance, pod := privateGatewayFixture(t)
	ctx := context.Background()
	old := metav1.NewTime(time.Now().Add(-10 * time.Minute).Truncate(time.Second))
	instance.Status.LastReconciledAt = &old
	instance.Status.EndpointLastCheckedAt = &old
	if err := r.Status().Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	if err := r.Get(ctx, key, sts); err != nil {
		t.Fatal(err)
	}
	sts.Spec.VolumeClaimTemplates[0].Spec.Resources.Requests[corev1.ResourceStorage] = resource.MustParse("20Gi")
	if err := r.Update(ctx, sts); err != nil {
		t.Fatal(err)
	}
	result, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: key})
	if err != nil {
		t.Fatal(err)
	}
	if result.RequeueAfter != 10*time.Second {
		t.Fatalf("expected resize early return: %+v", result)
	}
	observed := instance.DeepCopy()
	if err := r.Get(ctx, key, observed); err != nil {
		t.Fatal(err)
	}
	if observed.Status.PrivateURL != "https://private.example.com" || observed.Status.EndpointReason != "Ready" {
		t.Fatalf("serving sibling must remain available: %+v", observed.Status)
	}
	if !observed.Status.LastReconciledAt.Equal(&old) {
		t.Fatal("workload timestamp must still describe the unfinished pass")
	}
	if observed.Status.EndpointLastCheckedAt == nil || !observed.Status.EndpointLastCheckedAt.After(old.Time) {
		t.Fatal("endpoint observation was not refreshed")
	}
	service := &corev1.Service{}
	if err := r.Get(ctx, key, service); err != nil {
		t.Fatal(err)
	}
	if service.Spec.Selector[podNameLabel] != pod.Name {
		t.Fatal("client routing must be reconciled before maintenance yields")
	}
}

func TestPrivateGatewayTargetIsStickyAndSkipsOrphanedGateway(t *testing.T) {
	r, instance, pod := privateGatewayFixture(t)
	ctx := context.Background()
	nodeB := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "node-b", Labels: map[string]string{"tuist.dev/pn-ipv4": "172.16.0.3"}}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	podB := pod.DeepCopy()
	podB.Name = instance.Name + "-1"
	podB.ResourceVersion = ""
	podB.Spec.NodeName = "node-b"
	gatewayB := podB.DeepCopy()
	gatewayB.Name = "gateway-b"
	gatewayB.Namespace = "platform"
	gatewayB.Spec.HostNetwork = true
	gatewayB.Labels = map[string]string{gatewayClassLabel: instance.Spec.IngressClassName}
	for _, object := range []client.Object{nodeB, podB, gatewayB} {
		if err := r.Create(ctx, object); err != nil {
			t.Fatal(err)
		}
	}
	if err := r.reconcileService(ctx, instance, podB.Name); err != nil {
		t.Fatal(err)
	}
	target, err := r.privateGatewayTarget(ctx, instance)
	if err != nil || target != "172.16.0.3" {
		t.Fatalf("initial target must prefer selected primary's node: %q %v", target, err)
	}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, instance.Name+"-0"); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileService(ctx, instance, pod.Name); err != nil {
		t.Fatal(err)
	}
	snapshot := r.gatewayCache[instance.Spec.IngressClassName]
	orphan := gatewayB.DeepCopy()
	orphan.Name = "orphan"
	orphan.Spec.NodeName = "deleted-node"
	// Put the orphan first, then reverse the healthy pod order. Neither should
	// suppress the target or change DNS when the selected primary moves.
	snapshot.pods = append([]corev1.Pod{*orphan}, snapshot.pods...)
	for i, j := 1, len(snapshot.pods)-1; i < j; i, j = i+1, j-1 {
		snapshot.pods[i], snapshot.pods[j] = snapshot.pods[j], snapshot.pods[i]
	}
	r.gatewayCache[instance.Spec.IngressClassName] = snapshot
	target, err = r.privateGatewayTarget(ctx, instance)
	if err != nil || target != "172.16.0.3" {
		t.Fatalf("healthy published target must stay stable: %q %v", target, err)
	}
	if err := r.Delete(ctx, nodeB); err != nil {
		t.Fatal(err)
	}
	target, err = r.privateGatewayTarget(ctx, instance)
	if err != nil || target != "172.16.0.2" {
		t.Fatalf("removed target must fail over to healthy gateway: %q %v", target, err)
	}
}

type gatewayCountingReader struct {
	client.Reader
	lists int
}

func (r *gatewayCountingReader) List(ctx context.Context, list client.ObjectList, options ...client.ListOption) error {
	r.lists++
	return r.Reader.List(ctx, list, options...)
}

type gatewayCountingResolver struct{ calls int }

func (r *gatewayCountingResolver) LookupHost(context.Context, string) ([]string, error) {
	r.calls++
	return []string{"172.16.0.2"}, nil
}

func TestPrivateGatewayDiscoveryAndDNSUseBoundedCaches(t *testing.T) {
	r, instance, _ := privateGatewayFixture(t)
	ctx := context.Background()
	reader := &gatewayCountingReader{Reader: r.Client}
	r.APIReader = reader
	resolver := &gatewayCountingResolver{}
	r.PeerDNSResolver = resolver
	for i := 0; i < 5; i++ {
		if _, err := r.gatewayPods(ctx, instance.Spec.IngressClassName); err != nil {
			t.Fatal(err)
		}
		r.privateDNSAddresses(ctx, instance.Spec.PrivateHost, "172.16.0.2")
	}
	if reader.lists != 1 || resolver.calls != 1 {
		t.Fatalf("expected one shared LIST and one DNS lookup: %d %d", reader.lists, resolver.calls)
	}
	snapshot := r.gatewayCache[instance.Spec.IngressClassName]
	snapshot.expires = time.Now().Add(-time.Second)
	r.gatewayCache[instance.Spec.IngressClassName] = snapshot
	observation := r.clientDNSCache[instance.Spec.PrivateHost]
	observation.expires = time.Now().Add(-time.Second)
	r.clientDNSCache[instance.Spec.PrivateHost] = observation
	if _, err := r.gatewayPods(ctx, instance.Spec.IngressClassName); err != nil {
		t.Fatal(err)
	}
	r.privateDNSAddresses(ctx, instance.Spec.PrivateHost, "172.16.0.2")
	if reader.lists != 2 || resolver.calls != 2 {
		t.Fatal("expired observations must refresh")
	}
	r.privateDNSAddresses(ctx, instance.Spec.PrivateHost, "172.16.0.3")
	if resolver.calls != 3 {
		t.Fatal("a new target must invalidate the old DNS observation")
	}
	if time.Until(r.clientDNSCache[instance.Spec.PrivateHost].expires) > 5*time.Second {
		t.Fatal("a mismatched DNS answer must retry before the full positive TTL")
	}

}

func TestReconcileStatefulSetPreservesOperatorRolloutPause(t *testing.T) {
	r, instance, _ := privateGatewayFixture(t)
	ctx := context.Background()
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	if err := r.Get(ctx, key, sts); err != nil {
		t.Fatal(err)
	}
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
	if err := r.Update(ctx, sts); err != nil {
		t.Fatal(err)
	}
	instance.Spec.Image = "ghcr.io/tuist/kura:new"
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, key, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatal("reconcile resumed an operator-paused rollout")
	}
	if sts.Spec.Template.Labels["tuist.dev/host-network-gateway"] != "true" {
		t.Fatal("gateway backend must be selected by the Cilium node-identity policy")
	}
}

// privateWildcardGatewayFixture is a converged private gateway whose host sits
// one label under the wildcard's zone, with the shared Secret already issued.
func privateWildcardGatewayFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, *corev1.Pod) {
	t.Helper()
	instance := meshInstance("kura-tuist-scw-fr-par", "tuist")
	instance.Generation = 2
	instance.Spec.Private = true
	instance.Spec.PrivateHost = "tuist-scw-fr-par-runners.kura.tuist.dev"
	instance.Spec.PublicHostNetwork = true
	instance.Spec.IngressClassName = "kura-runners"
	instance.Spec.ClientCIDRs = []string{"172.16.0.0/22"}
	instance.Spec.Replicas = ptr(int32(2))
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: selectorLabels(instance), CreationTimestamp: metav1.NewTime(time.Now().Add(-time.Hour))},
		Spec:       corev1.PodSpec{NodeName: "node"},
		Status:     corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}},
	}
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "node", Labels: map[string]string{"tuist.dev/pn-ipv4": "172.16.0.2"}},
		Status:     corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}},
	}
	gateway := pod.DeepCopy()
	gateway.Name = "gateway"
	gateway.Namespace = "platform"
	gateway.Labels = map[string]string{gatewayClassLabel: instance.Spec.IngressClassName}
	gateway.Spec.HostNetwork = true
	wildcard := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-public-wildcard-tls", Namespace: instance.Namespace},
		Data:       map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev")},
	}
	scheme := meshTestScheme(t)
	r := &KuraInstanceReconciler{
		Client:              fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, pod, node, gateway, wildcard).WithStatusSubresource(instance).Build(),
		Scheme:              scheme,
		GRPCClusterIssuer:   "letsencrypt-cloudflare",
		PublicTLSSecretName: wildcard.Name,
		PeerDNSResolver:     &fakePeerDNSResolver{addresses: []string{"172.16.0.2"}},
	}
	return r, instance, pod
}

// The whole point of the cutover: an onboarding private gateway serves from the
// wildcard without placing an order, so growth stops consuming the ACME
// per-registered-domain budget that wedged the scw-fr-par fleet.
func TestPrivateGatewayCutsOverToSharedWildcard(t *testing.T) {
	ctx := context.Background()
	r, instance, _ := privateWildcardGatewayFixture(t)

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
	if got := ingress.Spec.TLS[0].SecretName; got != r.PublicTLSSecretName {
		t.Fatalf("expected the private gateway to terminate on the shared wildcard, got %q", got)
	}
	if got := ingress.Spec.TLS[0].Hosts[0]; got != instance.Spec.PrivateHost {
		t.Fatalf("expected the gateway to keep serving its own hostname, got %q", got)
	}
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no ACME order for a gateway host the wildcard covers, got %v", err)
	}
}

// A private gateway already holding its own certificate retires it, which is
// what stops the renewal it would otherwise spend every 60 days. Its leaf
// Secret stays behind as the rollback path.
func TestPrivateGatewayRetiresItsCertificateOnCutover(t *testing.T) {
	ctx := context.Background()
	r, instance, _ := privateWildcardGatewayFixture(t)
	legacyCert := &unstructured.Unstructured{}
	legacyCert.SetGroupVersionKind(certificateGVK())
	legacyCert.SetName(publicTLSSecretName(instance))
	legacyCert.SetNamespace(instance.Namespace)
	if err := r.Create(ctx, legacyCert); err != nil {
		t.Fatal(err)
	}
	legacySecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: publicTLSSecretName(instance), Namespace: instance.Namespace},
		Data:       map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, instance.Spec.PrivateHost)},
	}
	if err := r.Create(ctx, legacySecret); err != nil {
		t.Fatal(err)
	}

	// The retire reads the live Ingress, which the creating pass has not
	// published yet, so the cutover completes on the following one.
	for i := 0; i < 2; i++ {
		if err := r.reconcilePublicIngress(ctx, instance); err != nil {
			t.Fatal(err)
		}
		if err := r.reconcilePublicCertificate(ctx, instance); err != nil {
			t.Fatal(err)
		}
	}

	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the per-instance Certificate to be retired, got %v", err)
	}
	if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, &corev1.Secret{}); err != nil {
		t.Fatalf("expected the retained leaf Secret to survive the retire as the rollback path, got %v", err)
	}
}

// Retiring the Certificate must not take the endpoint down with it: the
// readiness gate reads the same wildcard the Ingress terminates on, so an
// instance with no Certificate at all still publishes.
func TestPrivateGatewayPublishesWithoutItsOwnCertificate(t *testing.T) {
	ctx := context.Background()
	r, instance, pod := privateWildcardGatewayFixture(t)
	samples := map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2}}

	observation, err := r.privateGatewayStatus(ctx, instance, pod.Name, []corev1.Pod{*pod}, samples)
	if err != nil {
		t.Fatal(err)
	}
	if observation.URL != "https://"+instance.Spec.PrivateHost {
		t.Fatalf("expected the wildcard to satisfy the gateway TLS gate, got %+v", observation)
	}
}

// Without a leaf spanning the host there is nothing for ingress-nginx to serve
// but its self-signed default, so the gate must hold rather than publish a URL
// the client cannot verify.
func TestPrivateGatewayWaitsWhileWildcardIsUnissued(t *testing.T) {
	ctx := context.Background()
	r, instance, pod := privateWildcardGatewayFixture(t)
	pending := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: r.PublicTLSSecretName, Namespace: instance.Namespace}}
	if err := r.Update(ctx, pending); err != nil {
		t.Fatal(err)
	}
	samples := map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2}}

	observation, err := r.privateGatewayStatus(ctx, instance, pod.Name, []corev1.Pod{*pod}, samples)
	if err != nil {
		t.Fatal(err)
	}
	if observation.URL != "" || observation.Reason != "CertificatePending" {
		t.Fatalf("expected the gate to hold on an unissued wildcard, got %+v", observation)
	}
}

// A private instance that never opted into a gateway has no client host, so a
// leftover publicHost must not reach the wildcard and mint an endpoint for it.
func TestPrivateInstanceWithoutGatewayStaysOffTheWildcard(t *testing.T) {
	ctx := context.Background()
	r, instance, _ := privateWildcardGatewayFixture(t)
	instance.Spec.PublicHost = "tuist-scw-fr-par.kura.tuist.dev"
	instance.Spec.ClientCIDRs = nil

	if r.sharedPublicTLSCovers(ctx, instance) {
		t.Fatal("a private instance without a gateway must not select the shared wildcard")
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, &networkingv1.Ingress{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no client Ingress for a leftover publicHost, got %v", err)
	}
}

// The incident this cutover exists for: a gateway whose own Certificate is
// wedged on the ACME per-registered-domain limit (created, never Ready, no
// Secret) must recover on its own, and withdraw the order it can never fill.
func TestPrivateGatewayRecoversFromRateLimitedCertificate(t *testing.T) {
	ctx := context.Background()
	r, instance, _ := privateWildcardGatewayFixture(t)
	stuck := &unstructured.Unstructured{}
	stuck.SetGroupVersionKind(certificateGVK())
	stuck.SetName(publicTLSSecretName(instance))
	stuck.SetNamespace(instance.Namespace)
	stuck.SetGeneration(1)
	unstructured.SetNestedStringSlice(stuck.Object, []string{instance.Spec.PrivateHost}, "spec", "dnsNames")
	unstructured.SetNestedSlice(stuck.Object, []interface{}{map[string]interface{}{"type": "Ready", "status": "False", "reason": "Failed"}}, "status", "conditions")
	if err := r.Create(ctx, stuck); err != nil {
		t.Fatal(err)
	}
	instance.Finalizers = []string{KuraInstanceFinalizer}
	instance.Spec.Replicas = ptr(int32(1))
	instance.Spec.StorageSize = "40Gi"
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	r.RuntimeStatusClient = fakeRuntimeStatusClient{statuses: map[string]runtimeStatus{instance.Name + "-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1, BackfillInitialCycle: backfillCycleComplete}}}
	req := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}
	for i := 0; i < 3; i++ {
		r.clientDNSCache = nil
		r.gatewayCache = nil
		if _, err := r.Reconcile(ctx, req); err != nil {
			t.Fatalf("pass %d: %v", i, err)
		}
	}
	fresh := &kurav1alpha1.KuraInstance{}
	if err := r.Get(ctx, req.NamespacedName, fresh); err != nil {
		t.Fatal(err)
	}
	if fresh.Status.PrivateURL != "https://"+instance.Spec.PrivateHost {
		t.Fatalf("stuck gateway did not recover: url=%q reason=%q message=%q", fresh.Status.PrivateURL, fresh.Status.EndpointReason, fresh.Status.EndpointMessage)
	}
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the rate-limited Certificate withdrawn, got %v", err)
	}
}
