package controllers

import (
	"context"
	"reflect"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestAccountRenameRetainsClientAliasesWithoutRollingWorkload(t *testing.T) {
	for _, private := range []bool{false, true} {
		t.Run(map[bool]string{false: "public", true: "private"}[private], func(t *testing.T) {
			ctx := context.Background()
			scheme := meshTestScheme(t)
			instance := meshInstance("kura-original-eu-west", "original")
			instance.Spec.PublicHost = "original.example.com"
			instance.Spec.PrivateHost = "original.example.com"
			instance.Spec.Private = private
			instance.Spec.PublicHostNetwork = true
			instance.Spec.IngressClassName = "kura"
			instance.Spec.ClientCIDRs = []string{"172.16.0.0/22"}
			r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build(), Scheme: scheme, GRPCClusterIssuer: "letsencrypt"}
			if err := r.reconcileStatefulSet(ctx, instance); err != nil {
				t.Fatal(err)
			}
			key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
			before := &appsv1.StatefulSet{}
			if err := r.Get(ctx, key, before); err != nil {
				t.Fatal(err)
			}
			before.Spec.UpdateStrategy.Type = appsv1.OnDeleteStatefulSetStrategyType
			if err := r.Update(ctx, before); err != nil {
				t.Fatal(err)
			}
			instance.Spec.PublicHost = "latest.example.com"
			instance.Spec.PrivateHost = "latest.example.com"
			instance.Spec.ClientHostAliases = []string{"original.example.com", "middle.example.com", "original.example.com"}
			if err := r.reconcileStatefulSet(ctx, instance); err != nil {
				t.Fatal(err)
			}
			after := &appsv1.StatefulSet{}
			if err := r.Get(ctx, key, after); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(before.Spec, after.Spec) {
				t.Fatal("rename changed the StatefulSet, volume claims, or operator rollout pause")
			}
			if err := r.reconcilePublicIngress(ctx, instance); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcileGRPCIngress(ctx, instance, nil, nil, ""); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcilePublicCertificate(ctx, instance); err != nil {
				t.Fatal(err)
			}
			want := []string{"latest.example.com", "middle.example.com", "original.example.com"}
			for _, name := range []string{instance.Name, grpcServiceName(instance)} {
				ingress := &networkingv1.Ingress{}
				if err := r.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, ingress); err != nil {
					t.Fatal(err)
				}
				var hosts []string
				for _, rule := range ingress.Spec.Rules {
					hosts = append(hosts, rule.Host)
					if rule.HTTP.Paths[0].Backend.Service.Name != instance.Name {
						t.Fatal("alias changed backend")
					}
				}
				if !reflect.DeepEqual(hosts, want) {
					t.Fatalf("missing alias routes: %v", hosts)
				}
				if private && ingress.Annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] != "172.16.0.0/22" {
					t.Fatal("alias lost the network allowlist")
				}
				if name == instance.Name && !reflect.DeepEqual(ingress.Spec.TLS[0].Hosts, want) {
					t.Fatal("alias not covered by TLS")
				}
			}
			cert := &unstructured.Unstructured{}
			cert.SetGroupVersionKind(certificateGVK())
			if err := r.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, cert); err != nil {
				t.Fatal(err)
			}
			names, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames")
			if !reflect.DeepEqual(names, want) {
				t.Fatalf("missing certificate names: %v", names)
			}
			cloned := instance.DeepCopy()
			cloned.Spec.ClientHostAliases[0] = "changed.example.com"
			if instance.Spec.ClientHostAliases[0] != "original.example.com" {
				t.Fatal("deep copy shared aliases")
			}
		})
	}
}

func TestAccountRenamePublishesAllAliasesAtTheSameGateway(t *testing.T) {
	ctx := context.Background()
	scheme, mapper := dnsEndpointScheme(t)
	instance := hostNetworkPublicInstance("kura-original", "eu-west", "latest.example.com")
	instance.Spec.ClientHostAliases = []string{"original.example.com", "middle.example.com"}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: selectorLabels(instance)}, Spec: corev1.PodSpec{NodeName: "box"}}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box"}, Status: corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "203.0.113.50"}}}}
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(instance, pod, node).Build(), Scheme: scheme}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, pod.Name); err != nil {
		t.Fatal(err)
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name + "-public-dns", Namespace: instance.Namespace}, endpoint); err != nil {
		t.Fatal(err)
	}
	records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if len(records) != 3 {
		t.Fatalf("missing aliases: %v", records)
	}
	for i, record := range records {
		fields := record.(map[string]interface{})
		if fields["dnsName"] != clientHosts(instance)[i] || !reflect.DeepEqual(fields["targets"], []interface{}{"203.0.113.50"}) {
			t.Fatalf("wrong alias target: %v", fields)
		}
	}
}

func TestSharedTLSMustCoverRetainedAliases(t *testing.T) {
	ctx := context.Background()
	instance := sharedWildcardTLSTestInstance()
	instance.Spec.ClientHostAliases = []string{"old.other.example.com"}
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: "wildcard", Namespace: instance.Namespace}, Data: map[string][]byte{corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev")}}
	scheme := meshTestScheme(t)
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, secret).Build(), Scheme: scheme, PublicTLSSecretName: secret.Name}
	if r.sharedPublicTLSCovers(ctx, instance) {
		t.Fatal("wildcard would strand the old hostname without TLS")
	}
	instance.Spec.ClientHostAliases = []string{"old.kura.tuist.dev"}
	if !r.sharedPublicTLSCovers(ctx, instance) {
		t.Fatal("one wildcard should cover the canonical hostname and aliases")
	}
}
