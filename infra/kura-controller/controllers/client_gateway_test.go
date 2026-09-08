package controllers

import (
	"context"
	"testing"
	"time"

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
			if sts.Spec.UpdateStrategy.Type != appsv1.RollingUpdateStatefulSetStrategyType || *sts.Spec.Replicas != 2 {
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
			status := runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2, BackfillInitialCycle: backfillCycleComplete}
			selected, err := r.selectPrimaryPod(ctx, instance, []corev1.Pod{primary, standby}, map[string]runtimeStatus{standby.Name: status})
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
	resolver := &fakePeerDNSResolver{addresses: []string{"172.16.0.2"}}
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, pod, node, gateway, cert).Build(), Scheme: scheme, PeerDNSResolver: resolver}
	samples := map[string]runtimeStatus{pod.Name: {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2}}
	check := func(want string) {
		t.Helper()
		url, err := r.privateGatewayURL(ctx, instance, pod.Name, []corev1.Pod{*pod}, samples)
		if err != nil || url != want {
			t.Fatalf("got %q, %v; want %q", url, err, want)
		}
	}
	check("")
	unstructured.SetNestedSlice(cert.Object, []interface{}{map[string]interface{}{"type": "Ready", "status": "True", "observedGeneration": int64(1)}}, "status", "conditions")
	if err := r.Update(ctx, cert); err != nil {
		t.Fatal(err)
	}
	check("https://private.example.com")
	status := samples[pod.Name]
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
	if err := r.reconcilePublicDNSEndpoint(ctx, instance); err != nil {
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
	if got, err := r.instanceNodeAddress(ctx, instance, true); err != nil || got != "172.16.0.2" {
		t.Fatalf("private DNS: %q %v", got, err)
	}
	if got, err := r.instanceNodeIP(ctx, instance); err != nil || got != "203.0.113.2" {
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
