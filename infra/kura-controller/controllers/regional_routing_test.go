package controllers

import (
	"context"
	"encoding/json"
	"reflect"
	ctrl "sigs.k8s.io/controller-runtime"
	"strings"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func regionalTestConfig() RegionalRouting {
	return RegionalRouting{Region: "eu-central", Domain: "eu-central.staging.kura.tuist.dev", IngressClass: "kura-eu-central", IngressNamespace: "platform", IngressDaemonSet: "eu-ingress"}
}

func TestRegionalPeerCertificateChangesRollPodsWithoutMetadataChurn(t *testing.T) {
	ctx := context.Background()
	instance := meshInstance("kura-regional-test", "test")
	instance.Annotations = map[string]string{regionalPeerHostAnnotation: "test.peer.eu-west.example.com"}
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, Data: map[string][]byte{peerTLSCertFile: []byte("original certificate")}}
	c := regionalTestClient(t, instance, secret)
	r := &KuraInstanceReconciler{Client: c, Scheme: c.Scheme()}
	readTemplate := func() corev1.PodTemplateSpec {
		t.Helper()
		if err := r.reconcileStatefulSet(ctx, instance); err != nil {
			t.Fatal(err)
		}
		sts := &appsv1.StatefulSet{}
		if err := c.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
			t.Fatal(err)
		}
		return sts.Spec.Template
	}
	initial := readTemplate()
	secret.Labels = map[string]string{"metadata": "changed"}
	if err := c.Update(ctx, secret); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(initial, readTemplate()) {
		t.Fatal("Secret metadata changes must not restart cache pods")
	}
	secret.Data[peerTLSCertFile] = []byte("certificate with regional SAN")
	if err := c.Update(ctx, secret); err != nil {
		t.Fatal(err)
	}
	if reflect.DeepEqual(initial, readTemplate()) {
		t.Fatal("a changed mounted certificate must restart pods to serve its regional SAN")
	}
}

func regionalTestClient(t *testing.T, objects ...client.Object) client.Client {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	return fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).WithStatusSubresource(&corev1.Pod{}, &corev1.Node{}).Build()
}

func regionalTestEndpoint(name string, records []interface{}) *unstructured.Unstructured {
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	endpoint.SetName(name)
	endpoint.SetNamespace("kura")
	_ = unstructured.SetNestedSlice(endpoint.Object, records, "spec", "endpoints")
	return endpoint
}

func regionalTestInstance(canonical bool) *kurav1alpha1.KuraInstance {
	instance := hostNetworkPeerInstance("kura-acme", "eu-central", "peer.acme-eu-central-1-staging.kura.tuist.dev")
	instance.UID = "acme-instance"
	instance.Spec.PublicHostNetwork = true
	instance.Spec.IngressClassName = "kura-eu-central"
	instance.Spec.PublicHost = "acme-eu-central-1-staging.kura.tuist.dev"
	if canonical {
		instance.Spec.PublicHost = "acme." + regionalTestConfig().Domain
		instance.Spec.MeshPublicPeerHost = "acme.peer." + regionalTestConfig().Domain
	}
	return instance
}

func regionalTestReconciler(t *testing.T, instance *kurav1alpha1.KuraInstance, objects ...client.Object) *KuraInstanceReconciler {
	t.Helper()
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: "wildcard", Namespace: "kura"}, Data: map[string][]byte{
		corev1.TLSCertKey: wildcardLeafPEM(t, "*.kura.tuist.dev", "*."+regionalTestConfig().Domain),
	}}
	objects = append(objects, instance, secret)
	c := regionalTestClient(t, objects...)
	return &KuraInstanceReconciler{Client: c, APIReader: c, Scheme: c.Scheme(), PublicTLSSecretName: "wildcard", RegionalRouting: []RegionalRouting{regionalTestConfig()}}
}

func TestRegionalRoutingNewAccountUsesOnlyWildcards(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(true)
	r := regionalTestReconciler(t, instance)
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, primary := range []string{"kura-acme-0", "kura-acme-1"} {
		if err := r.reconcileService(ctx, instance, primary); err != nil {
			t.Fatal(err)
		}
		if err := r.reconcilePublicDNSEndpoint(ctx, instance, primary); err != nil {
			t.Fatal(err)
		}
		if err := r.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
			t.Fatal(err)
		}
		var service corev1.Service
		if err := r.Get(ctx, client.ObjectKeyFromObject(instance), &service); err != nil {
			t.Fatal(err)
		}
		if service.Spec.Selector[podNameLabel] != primary {
			t.Fatal("service did not follow primary")
		}
	}
	for _, plane := range []string{"public", "peer"} {
		endpoint := regionalTestEndpoint(instance.Name+"-"+plane+"-dns", nil)
		if err := r.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); !apierrors.IsNotFound(err) {
			t.Fatalf("unexpected per-account %s DNS: %v", plane, err)
		}
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileGRPCIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{instance.Name, grpcServiceName(instance)} {
		var ingress networkingv1.Ingress
		if err := r.Get(ctx, types.NamespacedName{Namespace: "kura", Name: name}, &ingress); err != nil {
			t.Fatal(err)
		}
		if len(ingress.Spec.Rules) != 1 || ingress.Spec.Rules[0].Host != instance.Spec.PublicHost {
			t.Fatalf("wrong routes: %+v", ingress.Spec.Rules)
		}
		if ingress.Annotations["external-dns.alpha.kubernetes.io/controller"] != "kura-controller" {
			t.Fatal("ingress could create per-account DNS")
		}
	}
}

func TestRegionalRoutingPreservesLegacyNamesAcrossMigrationAndRestart(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(false)
	oldPublic, oldPeer := instance.Spec.PublicHost, instance.Spec.MeshPublicPeerHost
	config := regionalTestConfig()
	regional := regionalTestEndpoint(regionalDNSName(config.Region), append(addressRecords("*."+config.Domain, []string{"203.0.113.20", "203.0.113.21"}), addressRecords("*.peer."+config.Domain, []string{"203.0.113.21"})...))
	r := regionalTestReconciler(t, instance, regional)
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	instance.Spec.PublicHost = "acme." + config.Domain
	instance.Spec.MeshPublicPeerHost = "acme.peer." + config.Domain
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	// Read persisted metadata, as a new controller process would.
	instance = &kurav1alpha1.KuraInstance{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: "kura", Name: "kura-acme"}, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, primary := range []string{"kura-acme-0", "kura-acme-1"} {
		if err := r.reconcilePublicDNSEndpoint(ctx, instance, primary); err != nil {
			t.Fatal(err)
		}
		endpoint := regionalTestEndpoint("kura-acme-public-dns", nil)
		if err := r.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
			t.Fatal(err)
		}
		targets, ok := dnsEndpointTargets(endpoint, oldPublic)
		if !ok || !reflect.DeepEqual(targets, []string{"203.0.113.20", "203.0.113.21"}) {
			t.Fatalf("DNS followed cache placement: %v", targets)
		}
	}
	if err := r.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileGRPCIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{instance.Name, grpcServiceName(instance)} {
		var ingress networkingv1.Ingress
		if err := r.Get(ctx, types.NamespacedName{Namespace: "kura", Name: name}, &ingress); err != nil {
			t.Fatal(err)
		}
		hosts := []string{}
		for _, rule := range ingress.Spec.Rules {
			hosts = append(hosts, rule.Host)
		}
		if !reflect.DeepEqual(hosts, uniqueHosts([]string{oldPublic, instance.Spec.PublicHost})) {
			t.Fatalf("lost HTTP/gRPC alias: %v", hosts)
		}
	}
	routes, _, _, issues := peerDemuxDesiredState(config.Region, "kura", []kurav1alpha1.KuraInstance{*instance})
	if len(issues) != 0 || len(routes) != 2 {
		t.Fatalf("missing peer aliases: %v %v", routes, issues)
	}
	data, err := generateSelfSignedPeerTLSSecretData(instance)
	if err != nil {
		t.Fatal(err)
	}
	for _, host := range []string{oldPeer, instance.Spec.MeshPublicPeerHost} {
		probe := instance.DeepCopy()
		probe.Spec.MeshPublicPeerHost = host
		if !peerTLSSecretDataValid(data, probe, nil) {
			t.Fatalf("certificate does not preserve peer identity %s", host)
		}
	}
	// Explicit retirement is stable even while the old ingress/DNS still exist.
	instance.Annotations[legacyPublicHostsAnnotation] = "[]"
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if len(annotationHosts(instance, legacyPublicHostsAnnotation)) != 0 {
		t.Fatal("retired alias was rediscovered")
	}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-1"); err != nil {
		t.Fatal(err)
	}
}

func TestRegionalRoutingPublicationRollbackCreatesLegacyDNSForNewAccount(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(true)
	config := regionalTestConfig()
	regional := regionalTestEndpoint(regionalDNSName(config.Region), append(addressRecords("*."+config.Domain, []string{"203.0.113.20"}), addressRecords("*.peer."+config.Domain, []string{"203.0.113.21"})...))
	r := regionalTestReconciler(t, instance, regional)
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	legacy := regionalTestInstance(false)
	instance.Spec.PublicHost = legacy.Spec.PublicHost
	instance.Spec.MeshPublicPeerHost = legacy.Spec.MeshPublicPeerHost
	if err := r.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-0"); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, plane := range []struct{ suffix, host, address string }{
		{"public", legacy.Spec.PublicHost, "203.0.113.20"},
		{"peer", legacy.Spec.MeshPublicPeerHost, "203.0.113.21"},
	} {
		endpoint := regionalTestEndpoint(instance.Name+"-"+plane.suffix+"-dns", nil)
		if err := r.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
			t.Fatal(err)
		}
		if targets, _ := dnsEndpointTargets(endpoint, plane.host); !reflect.DeepEqual(targets, []string{plane.address}) {
			t.Fatalf("rollback DNS missing for %s: %v", plane.host, targets)
		}
	}
	if hosts := r.publicHosts(ctx, instance); !reflect.DeepEqual(hosts, uniqueHosts([]string{legacy.Spec.PublicHost, "acme." + config.Domain})) {
		t.Fatalf("rollback removed regional route: %v", hosts)
	}
	// Loss of all regional ingress must not erase compatibility records.
	_ = unstructured.SetNestedSlice(regional.Object, []interface{}{}, "spec", "endpoints")
	if err := r.Update(ctx, regional); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, "kura-acme-0"); err != nil {
		t.Fatal(err)
	}
	endpoint := regionalTestEndpoint(instance.Name+"-public-dns", nil)
	if err := r.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	if targets, _ := dnsEndpointTargets(endpoint, legacy.Spec.PublicHost); !reflect.DeepEqual(targets, []string{"203.0.113.20"}) {
		t.Fatalf("compatibility targets erased: %v", targets)
	}
}

func TestRegionalRoutingWaitsForWildcardBeforePublishingAlias(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(false)
	r := regionalTestReconciler(t, instance)
	var secret corev1.Secret
	if err := r.Get(ctx, types.NamespacedName{Namespace: "kura", Name: "wildcard"}, &secret); err != nil {
		t.Fatal(err)
	}
	secret.Data[corev1.TLSCertKey] = wildcardLeafPEM(t, "*.kura.tuist.dev")
	if err := r.Update(ctx, &secret); err != nil {
		t.Fatal(err)
	}
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if hosts := r.publicHosts(ctx, instance); !reflect.DeepEqual(hosts, []string{instance.Spec.PublicHost}) {
		t.Fatalf("published unissued regional TLS: %v", hosts)
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		t.Fatal(err)
	}
	instance.Spec.PublicHost = "acme." + regionalTestConfig().Domain
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal("TLS gap must not stop backend reconciliation:", err)
	}
	if !r.regionalPublicTLSMissing(ctx, instance) {
		t.Fatal("public mutations must wait for wildcard TLS")
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
	if err := r.reconcilePeerTLSSecret(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	var sts appsv1.StatefulSet
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), &sts); err != nil {
		t.Fatal("TLS gap prevented workload creation:", err)
	}
	var ingress networkingv1.Ingress
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), &ingress); err != nil {
		t.Fatal(err)
	}
	for _, rule := range ingress.Spec.Rules {
		if rule.Host == instance.Spec.PublicHost {
			t.Fatal("published an uncovered host")
		}
	}
}

func TestRegionalDNSUsesReadyIngressMachinesWithoutCachePods(t *testing.T) {
	ctx := context.Background()
	config := regionalTestConfig()
	ds := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: config.IngressDaemonSet, Namespace: "platform", UID: "public-ds"}, Spec: appsv1.DaemonSetSpec{Selector: &metav1.LabelSelector{MatchLabels: map[string]string{"app": "public"}}, Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{HostNetwork: true}}}}
	peerDS := ds.DeepCopy()
	peerDS.Name, peerDS.Namespace, peerDS.UID = peerDemuxName(config.Region), "kura", "peer-ds"
	objects := []client.Object{ds, peerDS}
	for i, address := range []string{"203.0.113.10", "203.0.113.11", "10.0.0.3"} {
		name := string(rune('a' + i))
		node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}, Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: address}}}}
		pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "platform", Labels: map[string]string{"app": "public"}, OwnerReferences: []metav1.OwnerReference{{UID: ds.UID, Controller: ptr(true)}}}, Spec: corev1.PodSpec{HostNetwork: true, NodeName: name}, Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
		objects = append(objects, node, pod)
	}
	c := regionalTestClient(t, objects...)
	r := &RegionalDNS{Client: c, APIReader: c, Namespace: "kura"}
	if err := r.Ensure(ctx, config); err != nil {
		t.Fatal(err)
	}
	endpoint := regionalTestEndpoint(regionalDNSName(config.Region), nil)
	if err := c.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	targets, _ := dnsEndpointTargets(endpoint, "*."+config.Domain)
	if !reflect.DeepEqual(targets, []string{"203.0.113.10", "203.0.113.11"}) {
		t.Fatalf("unexpected targets: %v", targets)
	}
	// A DNS node created by *.peer.<domain> cannot inherit *.domain's
	// wildcard answer. The shared exact record keeps account "peer" valid.
	peerAccountTargets, _ := dnsEndpointTargets(endpoint, "peer."+config.Domain)
	if !reflect.DeepEqual(peerAccountTargets, targets) {
		t.Fatalf("peer namespace shadows the account named peer: %v", peerAccountTargets)
	}
	var pod corev1.Pod
	if err := c.Get(ctx, types.NamespacedName{Namespace: "platform", Name: "a"}, &pod); err != nil {
		t.Fatal(err)
	}
	pod.Status.Conditions[0].Status = corev1.ConditionFalse
	if err := c.Status().Update(ctx, &pod); err != nil {
		t.Fatal(err)
	}
	if err := r.Ensure(ctx, config); err != nil {
		t.Fatal(err)
	}
	if err := c.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	targets, _ = dnsEndpointTargets(endpoint, "*."+config.Domain)
	if !reflect.DeepEqual(targets, []string{"203.0.113.11"}) {
		t.Fatalf("unready ingress still published: %v", targets)
	}
	var node corev1.Node
	if err := c.Get(ctx, types.NamespacedName{Name: "b"}, &node); err != nil {
		t.Fatal(err)
	}
	node.Spec.Unschedulable = true
	if err := c.Update(ctx, &node); err != nil {
		t.Fatal(err)
	}
	if err := r.Ensure(ctx, config); err != nil {
		t.Fatal(err)
	}
	if err := c.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	if len(records) != 0 {
		t.Fatalf("unhealthy region still published: %v", records)
	}
}

func TestRegionalRoutingRejectsConflictingDomains(t *testing.T) {
	config := regionalTestConfig()
	valid, _ := json.Marshal([]RegionalRouting{config})
	if _, err := ParseRegionalRouting(string(valid)); err != nil {
		t.Fatal(err)
	}
	for _, domain := range []string{config.Domain, "child." + config.Domain, "*.kura.tuist.dev", "bad;domain"} {
		other := config
		other.Region = "us-east"
		other.Domain = domain
		value, _ := json.Marshal([]RegionalRouting{config, other})
		if _, err := ParseRegionalRouting(string(value)); err == nil {
			t.Fatalf("accepted conflicting domain %s", domain)
		}
	}
	// The unknown SNI fallback stays closed after adding regional aliases.
	if !strings.Contains(peerDemuxNginxConf(nil, "10.0.0.10"), `default "";`) {
		t.Fatal("unknown peer SNI acquired a fallback")
	}
}

func TestRegionalDNSMissingDaemonSetPreservesPublishedRecords(t *testing.T) {
	ctx := context.Background()
	config := regionalTestConfig()
	for _, missing := range []string{"public", "peer"} {
		t.Run(missing, func(t *testing.T) {
			endpoint := regionalTestEndpoint(regionalDNSName(config.Region), addressRecords("*."+config.Domain, []string{"203.0.113.20"}))
			ds := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: config.IngressDaemonSet, Namespace: config.IngressNamespace}, Spec: appsv1.DaemonSetSpec{Selector: &metav1.LabelSelector{}, Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{HostNetwork: true}}}}
			if missing == "public" {
				ds.Name, ds.Namespace = peerDemuxName(config.Region), "kura"
			}
			c := regionalTestClient(t, endpoint, ds, regionalTestInstance(false))
			r := &RegionalDNS{Client: c, APIReader: c, Namespace: "kura"}
			if err := r.Ensure(ctx, config); !apierrors.IsNotFound(err) {
				t.Fatalf("expected observable missing DaemonSet: %v", err)
			}
			current := regionalTestEndpoint(endpoint.GetName(), nil)
			if err := c.Get(ctx, client.ObjectKeyFromObject(endpoint), current); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(endpoint.Object["spec"], current.Object["spec"]) {
				t.Fatal("missing DaemonSet erased DNS")
			}
		})
	}
}

func TestRegionalLegacyDNSWaitsForSingletonWithoutErasingFallback(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(false)
	endpoint := regionalTestEndpoint(instance.Name+"-public-dns", addressRecords(instance.Spec.PublicHost, []string{"203.0.113.20"}))
	r := regionalTestReconciler(t, instance, endpoint)
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePublicDNSEndpoint(ctx, instance, ""); err != nil {
		t.Fatal(err)
	}
	current := regionalTestEndpoint(endpoint.GetName(), nil)
	if err := r.Get(ctx, client.ObjectKeyFromObject(current), current); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(endpoint.Object["spec"], current.Object["spec"]) {
		t.Fatal("fallback changed before singleton exists")
	}
}

func TestMalformedLegacyHostsCannotRetireAliases(t *testing.T) {
	ctx := context.Background()
	for _, value := range []string{"", "null", `["truncated`, `{"host":"old.example"}`, `["bad_host"]`} {
		t.Run(value, func(t *testing.T) {
			instance := regionalTestInstance(true)
			instance.Annotations = map[string]string{legacyPublicHostsAnnotation: value, legacyPeerHostsAnnotation: value}
			endpoint := regionalTestEndpoint(instance.Name+"-public-dns", addressRecords("old.example", []string{"203.0.113.20"}))
			r := regionalTestReconciler(t, instance, endpoint)
			if err := r.prepareRegionalRouting(ctx, instance); err == nil {
				t.Fatal("accepted malformed annotation")
			}
			if err := r.reconcileRegionalLegacyDNS(ctx, instance, &r.RegionalRouting[0], false); err == nil {
				t.Fatal("accepted malformed DNS retirement")
			}
			current := regionalTestEndpoint(endpoint.GetName(), nil)
			if err := r.Get(ctx, client.ObjectKeyFromObject(current), current); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(endpoint.Object["spec"], current.Object["spec"]) {
				t.Fatal("lost legacy DNS")
			}
			live := &kurav1alpha1.KuraInstance{}
			if err := r.Get(ctx, client.ObjectKeyFromObject(instance), live); err != nil {
				t.Fatal(err)
			}
			if live.Annotations[legacyPublicHostsAnnotation] != value {
				t.Fatal("overwrote corrupt annotation")
			}
		})
	}
}

func TestRegionalAddressesPreferExternalPerFamilyAndExcludeCGNAT(t *testing.T) {
	ctx := context.Background()
	ds := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: "ingress", Namespace: "kura", UID: "ds"}, Spec: appsv1.DaemonSetSpec{Selector: &metav1.LabelSelector{}, Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{HostNetwork: true}}}}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "node"}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}, Addresses: []corev1.NodeAddress{
		{Type: corev1.NodeExternalIP, Address: "203.0.113.1"},
		{Type: corev1.NodeExternalIP, Address: "100.64.0.1"},
		{Type: corev1.NodeInternalIP, Address: "100.127.255.254"},
		{Type: corev1.NodeInternalIP, Address: "203.0.113.2"},
		{Type: corev1.NodeInternalIP, Address: "2001:db8::1"},
		{Type: corev1.NodeInternalIP, Address: "fd00::1"},
	}}}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "ingress", Namespace: "kura", OwnerReferences: []metav1.OwnerReference{{UID: "ds", Controller: ptr(true)}}}, Spec: corev1.PodSpec{HostNetwork: true, NodeName: "node"}, Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
	c := regionalTestClient(t, ds, node, pod)
	r := &RegionalDNS{Client: c, APIReader: c}
	addresses, err := r.readyDaemonSetAddresses(ctx, "kura", "ingress")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(addresses, []string{"2001:db8::1", "203.0.113.1"}) {
		t.Fatalf("unexpected dual-stack targets %v", addresses)
	}
}

type tlsCountingClient struct {
	client.Client
	reads int
}

func (c *tlsCountingClient) Get(ctx context.Context, key client.ObjectKey, obj client.Object, opts ...client.GetOption) error {
	if _, secret := obj.(*corev1.Secret); secret && key.Name == "wildcard" {
		c.reads++
	}
	return c.Client.Get(ctx, key, obj, opts...)
}

func TestPublicTLSLeafSnapshotIsScopedToOneReconcile(t *testing.T) {
	instance := regionalTestInstance(true)
	r := regionalTestReconciler(t, instance)
	c := &tlsCountingClient{Client: r.Client}
	r.Client = c
	ctx := withSharedPublicTLS(context.Background(), instance.Namespace)
	if err := r.prepareRegionalRouting(ctx, instance); err != nil {
		t.Fatal(err)
	}
	for _, reconcile := range []func(context.Context, *kurav1alpha1.KuraInstance) error{r.reconcilePublicIngress, r.reconcileGRPCIngress, r.reconcilePublicCertificate} {
		if err := reconcile(ctx, instance); err != nil {
			t.Fatal(err)
		}
	}
	if c.reads != 1 {
		t.Fatalf("read/parsed shared certificate %d times", c.reads)
	}
	next := withSharedPublicTLS(context.Background(), instance.Namespace)
	if !r.sharedPublicTLSCoversHost(next, instance.Namespace, instance.Spec.PublicHost) || c.reads != 2 {
		t.Fatal("new reconcile reused stale certificate snapshot")
	}
}

func TestRegionalTLSLossDoesNotBlockFullWorkloadReconciliation(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(true)
	c := regionalTestClient(t, instance)
	c = fake.NewClientBuilder().WithScheme(c.Scheme()).WithObjects(instance).WithStatusSubresource(&kurav1alpha1.KuraInstance{}, &appsv1.StatefulSet{}).Build()
	r := &KuraInstanceReconciler{Client: c, APIReader: c, Scheme: c.Scheme(), PublicTLSSecretName: "missing-wildcard", RegionalRouting: []RegionalRouting{regionalTestConfig()}}
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: client.ObjectKeyFromObject(instance)}); err != nil {
		t.Fatal(err)
	}
	var sts appsv1.StatefulSet
	if err := c.Get(ctx, client.ObjectKeyFromObject(instance), &sts); err != nil {
		t.Fatal("TLS prevented StatefulSet reconciliation:", err)
	}
	var live kurav1alpha1.KuraInstance
	if err := c.Get(ctx, client.ObjectKeyFromObject(instance), &live); err != nil {
		t.Fatal(err)
	}
	if live.Status.LastReconciledAt == nil {
		t.Fatal("TLS prevented status update")
	}
	if !strings.Contains(live.Status.Message, "Regional public TLS is unavailable") {
		t.Fatal("TLS gap absent from status")
	}
}

func TestInvalidPeerHostCannotChooseRegionalPlacement(t *testing.T) {
	for _, invalidHost := range []string{"invalid_host.example", strings.Repeat("x", 64) + ".example"} {
		invalid := regionalTestInstance(false)
		invalid.Spec.MeshPublicPeerHost = invalidHost
		invalid.Spec.NodeSelector = map[string]string{"pool": "wrong"}
		valid := regionalTestInstance(false)
		valid.Name = "newer-valid"
		valid.CreationTimestamp = metav1.NewTime(time.Now())
		valid.Spec.NodeSelector = map[string]string{"pool": "right"}
		routes, selector, _, issues := peerDemuxDesiredState(valid.Spec.Region, valid.Namespace, []kurav1alpha1.KuraInstance{*invalid, *valid})
		if len(routes) != 1 || len(issues) != 1 || selector["pool"] != "right" {
			t.Fatalf("invalid instance affected regional placement: %v %v %v", routes, selector, issues)
		}

	}
}

func TestMalformedPeerAnnotationsPreserveDemuxConfiguration(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(false)
	instance.Annotations = map[string]string{legacyPeerHostsAnnotation: `["broken`}
	config := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: peerDemuxName(instance.Spec.Region), Namespace: instance.Namespace}, Data: map[string]string{"nginx.conf": "existing live routes"}}
	c := regionalTestClient(t, instance, config)
	r := &PeerDemuxReconciler{Client: c, APIReader: c, Scheme: c.Scheme()}
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Namespace: instance.Namespace, Name: instance.Spec.Region}}); err == nil {
		t.Fatal("accepted malformed peer aliases")
	}
	var current corev1.ConfigMap
	if err := c.Get(ctx, client.ObjectKeyFromObject(config), &current); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(current.Data, config.Data) {
		t.Fatal("lost live demux routes")
	}
}

func TestRegionalPeerMigrationKeepsOriginalHostAndDNSTarget(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(true)
	old := "peer.acme-eu-central-1-staging.kura.tuist.dev"
	instance.Annotations = map[string]string{legacyPeerHostsAnnotation: `["` + old + `"]`}
	instance.Spec.MeshPeerFailoverIP = "203.0.113.8"
	legacy := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: legacyAccountPublicPeerServiceName(instance), Namespace: instance.Namespace,
		Labels:      map[string]string{"app.kubernetes.io/managed-by": "kura-controller", "tuist.dev/account": instance.Spec.AccountHandle},
		Annotations: map[string]string{externalDNSHostnameAnnotation: old}}, Spec: corev1.ServiceSpec{Type: corev1.ServiceTypeLoadBalancer}}
	regional := regionalTestEndpoint(regionalDNSName(instance.Spec.Region), addressRecords("*.peer."+regionalTestConfig().Domain, []string{"203.0.113.99"}))
	r := regionalTestReconciler(t, instance, legacy, regional)
	view, err := r.pendingLegacyPeerInstance(ctx, instance)
	if err != nil || view == nil || view.Spec.MeshPublicPeerHost != old {
		t.Fatalf("lost original migration host: %v %v", view, err)
	}
	if err := r.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}
	endpoint := regionalTestEndpoint(instance.Name+"-peer-dns", nil)
	if err := r.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	targets, _ := dnsEndpointTargets(endpoint, old)
	if !reflect.DeepEqual(targets, []string{"203.0.113.8"}) {
		t.Fatalf("regional targets interrupted unfinished LB retirement: %v", targets)
	}
	if err := r.Delete(ctx, legacy); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcilePeerDNSEndpoint(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	targets, _ = dnsEndpointTargets(endpoint, old)
	if !reflect.DeepEqual(targets, []string{"203.0.113.99"}) {
		t.Fatalf("regional targets not adopted after retirement: %v", targets)
	}
}

func TestRegionalLegacyPeerCleanupRespectsCanonicalMoveSibling(t *testing.T) {
	ctx := context.Background()
	instance := regionalTestInstance(true)
	old := "peer.acme-eu-central-1-staging.kura.tuist.dev"
	instance.Annotations = map[string]string{legacyPeerHostsAnnotation: `["` + old + `"]`}
	sibling := instance.DeepCopy()
	sibling.Name += "-move"
	sibling.UID = "sibling"
	legacy := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: legacyAccountPublicPeerServiceName(instance), Namespace: instance.Namespace,
		Labels:      map[string]string{"app.kubernetes.io/managed-by": "kura-controller", "tuist.dev/account": instance.Spec.AccountHandle},
		Annotations: map[string]string{externalDNSHostnameAnnotation: old}}}
	r := regionalTestReconciler(t, instance, sibling, legacy)
	if err := r.cleanupLegacyAccountPublicPeerService(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(legacy), &corev1.Service{}); err != nil {
		t.Fatal("deleted sibling's fallback:", err)
	}
	if err := r.Delete(ctx, sibling); err != nil {
		t.Fatal(err)
	}
	if err := r.cleanupLegacyAccountPublicPeerService(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(legacy), &corev1.Service{}); !apierrors.IsNotFound(err) {
		t.Fatalf("retained fallback after last canonical instance: %v", err)
	}
}

func TestEmptyRegionCanPublishPublicDNSBeforeFirstPeer(t *testing.T) {
	ctx := context.Background()
	config := regionalTestConfig()
	ds := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: config.IngressDaemonSet, Namespace: config.IngressNamespace, UID: "public"}, Spec: appsv1.DaemonSetSpec{Selector: &metav1.LabelSelector{}, Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{HostNetwork: true}}}}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ingress"}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}, Addresses: []corev1.NodeAddress{{Type: corev1.NodeExternalIP, Address: "203.0.113.7"}}}}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "ingress", Namespace: config.IngressNamespace, OwnerReferences: []metav1.OwnerReference{{UID: ds.UID, Controller: ptr(true)}}}, Spec: corev1.PodSpec{HostNetwork: true, NodeName: node.Name}, Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
	c := regionalTestClient(t, ds, node, pod)
	r := &RegionalDNS{Client: c, APIReader: c, Namespace: "kura"}
	if err := r.Ensure(ctx, config); err != nil {
		t.Fatal(err)
	}
	endpoint := regionalTestEndpoint(regionalDNSName(config.Region), nil)
	if err := c.Get(ctx, client.ObjectKeyFromObject(endpoint), endpoint); err != nil {
		t.Fatal(err)
	}
	targets, _ := dnsEndpointTargets(endpoint, "*."+config.Domain)
	if !reflect.DeepEqual(targets, []string{"203.0.113.7"}) {
		t.Fatalf("empty region cannot bootstrap public DNS: %v", targets)
	}
}
