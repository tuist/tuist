package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"slices"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func privateNode(name, provider, network, members string) corev1.Node {
	return corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name, Labels: map[string]string{"pool": "cache", privateNetworkLabel: network}, Annotations: map[string]string{privateNetworkLabel: network, privateMembershipAnnotation: members}}, Spec: corev1.NodeSpec{ProviderID: provider}}
}

func TestPrivateReplicationRequiresConvergedRealProviders(t *testing.T) {
	valid := privateNode("a", "ovh://gra/a", "pn-test", "members-a")
	for _, tc := range []struct {
		name  string
		nodes []corev1.Node
		want  string
		fail  bool
	}{
		{name: "empty"},
		{name: "unmanaged provider", nodes: []corev1.Node{privateNode("a", "hcloud://1", "", "")}},
		{name: "ready OVH", nodes: []corev1.Node{valid, privateNode("b", "ovh://bhs/b", "pn-test", "members-a")}, want: "pn-test"},
		{name: "mixed pool", nodes: []corev1.Node{valid, privateNode("b", "dedibox://b", "pn-test", "members-a")}, fail: true},
		{name: "unconfigured node", nodes: []corev1.Node{valid, privateNode("b", "ovh://bhs/b", "", "")}, fail: true},
		{name: "different domains", nodes: []corev1.Node{valid, privateNode("b", "ovh://bhs/b", "pn-other", "members-a")}, fail: true},
		{name: "stale routes", nodes: []corev1.Node{valid, privateNode("b", "ovh://bhs/b", "pn-test", "members-b")}, fail: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, network, err := privateReplicationDomain(tc.nodes)
			if (err != nil) != tc.fail || network != tc.want {
				t.Fatalf("network=%q err=%v", network, err)
			}
		})
	}
}

func TestPrivateReplicationUsesPodIdentityAndQualifiedPlacement(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	node := privateNode("a", "ovh://gra/a", "pn-test", "members-a")
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(&node).Build(), PrivateReplication: true}
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "test-cache", Namespace: "test"}}
	instance.Spec.NodeSelector = map[string]string{"pool": "cache"}
	template := podTemplate(instance, "", "staging", "", false, false, false)
	if err := r.configurePrivateReplication(context.Background(), instance, &template, nil); err != nil {
		t.Fatal(err)
	}
	if template.Spec.NodeSelector[privateNetworkLabel] != "pn-test" {
		t.Fatal("new pods can land on an unqualified node")
	}
	var topology map[string]string
	for _, env := range template.Spec.Containers[0].Env {
		if env.Name == peerTopologyEnv {
			if err := json.Unmarshal([]byte(env.Value), &topology); err != nil {
				t.Fatal(err)
			}
		}
	}
	if topology["provider"] != "ovh" || topology["private_network"] != "pn-test" || topology["private_url"] != renderPodNodeURL(instance, "$(POD_NAME)", "$(POD_NAMESPACE)") {
		t.Fatal(topology)
	}
}

func TestPrivateReplicationQualificationDoesNotBlockStatefulSetUpdates(t *testing.T) {
	for _, previouslyQualified := range []bool{false, true} {
		for _, gap := range []string{"mixed", "missing", "stale"} {
			t.Run(fmt.Sprintf("qualified-%t-%s", previouslyQualified, gap), func(t *testing.T) {
				ctx := context.Background()
				scheme := runtime.NewScheme()
				if err := clientgoscheme.AddToScheme(scheme); err != nil {
					t.Fatal(err)
				}
				if err := kurav1alpha1.AddToScheme(scheme); err != nil {
					t.Fatal(err)
				}
				node := privateNode("a", "ovh://gra/a", "pn-test", "members-a")
				instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "cache", Namespace: "test"}, Spec: kurav1alpha1.KuraInstanceSpec{Image: "old", NodeSelector: map[string]string{"pool": "cache"}}}
				c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(&node, instance).Build()
				r := &KuraInstanceReconciler{Client: c, Scheme: scheme, PrivateReplication: previouslyQualified}
				if err := r.reconcileStatefulSet(ctx, instance); err != nil {
					t.Fatal(err)
				}
				before := &appsv1.StatefulSet{}
				key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
				if err := c.Get(ctx, key, before); err != nil {
					t.Fatal(err)
				}
				switch gap {
				case "mixed":
					other := privateNode("b", "dedibox://b", "", "")
					if err := c.Create(ctx, &other); err != nil {
						t.Fatal(err)
					}
				case "missing":
					if err := c.Delete(ctx, &node); err != nil {
						t.Fatal(err)
					}
				case "stale":
					other := privateNode("b", "ovh://gra/b", "pn-test", "members-b")
					if err := c.Create(ctx, &other); err != nil {
						t.Fatal(err)
					}
				}
				r.PrivateReplication = true
				instance.Spec.Image = "new"
				instance.Spec.Replicas = ptr(int32(3))
				if err := r.reconcileStatefulSet(ctx, instance); err != nil {
					t.Fatal(err)
				}
				after := &appsv1.StatefulSet{}
				if err := c.Get(ctx, key, after); err != nil {
					t.Fatal(err)
				}
				if after.Spec.Template.Spec.Containers[0].Image != "new" || *after.Spec.Replicas != 3 {
					t.Fatal("unrelated changes blocked")
				}
				if !reflect.DeepEqual(before.Spec.Template.Spec.NodeSelector, after.Spec.Template.Spec.NodeSelector) {
					t.Fatal("placement changed during qualification gap")
				}
				if after.Spec.Template.Annotations[managedTopologyAnnotation] != before.Spec.Template.Annotations[managedTopologyAnnotation] {
					t.Fatal("managed policy changed")
				}
				for _, env := range before.Spec.Template.Spec.Containers[0].Env {
					if env.Name == peerTopologyEnv && !slices.ContainsFunc(after.Spec.Template.Spec.Containers[0].Env, func(got corev1.EnvVar) bool { return reflect.DeepEqual(env, got) }) {
						t.Fatal("private policy lost")
					}
				}
			})
		}
	}
}

func TestPrivateReplicationVultrRequiresCurrentBootAndConvergedRegion(t *testing.T) {
	ready := privateNode("a", "vultr://ord/a", "vpc-test", "members")
	ready.Status.NodeInfo.BootID = "boot-a"
	ready.Annotations["tuist.dev/private-network-revision"] = "script:boot-a"
	provider, network, err := privateReplicationDomain([]corev1.Node{ready})
	if err != nil || provider != "vultr" || network != "vpc-test" {
		t.Fatalf("qualified Vultr: %s %s %v", provider, network, err)
	}
	rebooted := ready.DeepCopy()
	rebooted.Status.NodeInfo.BootID = "boot-b"
	if _, _, err := privateReplicationDomain([]corev1.Node{*rebooted}); err == nil {
		t.Fatal("accepted a stale boot attestation")
	}
	unqualified := privateNode("b", "vultr://scl/b", "", "")
	if provider, _, err := privateReplicationDomain([]corev1.Node{unqualified}); err != nil || provider != "" {
		t.Fatal("unqualified Vultr must retain canonical replication")
	}
	if _, _, err := privateReplicationDomain([]corev1.Node{ready, unqualified}); err == nil {
		t.Fatal("partly qualified placement must not advertise topology")
	}
	other := ready.DeepCopy()
	other.Name = "b"
	other.Labels[privateNetworkLabel] = "other"
	other.Annotations[privateNetworkLabel] = "other"
	if _, _, err := privateReplicationDomain([]corev1.Node{ready, *other}); err == nil {
		t.Fatal("accepted mixed routing domains")
	}
}

func TestPrivateReplicationPoolChangeWithdrawsPreviousPolicy(t *testing.T) {
	for _, destination := range []string{"empty", "canonical", "unqualified", "qualified"} {
		t.Run(destination, func(t *testing.T) {
			ctx := context.Background()
			scheme := runtime.NewScheme()
			if err := clientgoscheme.AddToScheme(scheme); err != nil {
				t.Fatal(err)
			}
			if err := kurav1alpha1.AddToScheme(scheme); err != nil {
				t.Fatal(err)
			}
			node := privateNode("old", "ovh://gra/old", "pn-test", "old-members")
			instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "cache", Namespace: "test"}, Spec: kurav1alpha1.KuraInstanceSpec{Image: "old", NodeSelector: map[string]string{"pool": "cache"}}}
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(&node, instance).Build()
			r := &KuraInstanceReconciler{Client: c, Scheme: scheme, PrivateReplication: true}
			if err := r.reconcileStatefulSet(ctx, instance); err != nil {
				t.Fatal(err)
			}
			if err := c.Delete(ctx, &node); err != nil {
				t.Fatal(err)
			}
			if destination != "empty" {
				next := privateNode("new", "hcloud://new", "", "")
				next.Labels["pool"] = "new"
				if destination == "unqualified" {
					next.Spec.ProviderID = "ovh://gra/new"
				}
				if destination == "qualified" {
					next = privateNode("new", "ovh://gra/new", "pn-new", "new-members")
					next.Labels["pool"] = "new"
				}
				if err := c.Create(ctx, &next); err != nil {
					t.Fatal(err)
				}
			}
			instance.Spec.NodeSelector = map[string]string{"pool": "new"}
			if err := r.reconcileStatefulSet(ctx, instance); err != nil {
				t.Fatal(err)
			}
			sts := &appsv1.StatefulSet{}
			if err := c.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
				t.Fatal(err)
			}
			wantSelector := map[string]string{"pool": "new"}
			if destination == "qualified" {
				wantSelector[privateNetworkLabel] = "pn-new"
			}
			if !reflect.DeepEqual(sts.Spec.Template.Spec.NodeSelector, wantSelector) {
				t.Fatalf("pool change ignored: %v", sts.Spec.Template.Spec.NodeSelector)
			}
			env := sts.Spec.Template.Spec.Containers[0].Env
			if got := hasEnvVar(env, peerTopologyEnv); got != (destination == "qualified") {
				t.Fatalf("topology present=%t for %s", got, destination)
			}
			if got := sts.Spec.Template.Annotations[managedTopologyAnnotation] == "true"; got != (destination == "qualified") {
				t.Fatalf("managed annotation present=%t for %s", got, destination)
			}
		})
	}
}

func TestPrivateReplicationCanonicalPolicyRequiresAgreement(t *testing.T) {
	for _, tc := range []struct {
		name     string
		policies []string
		fail     bool
	}{
		{"legacy", []string{"", "[]"}, false},
		{"approved", []string{`["scl-id"]`, `["scl-id"]`}, false},
		{"updating", []string{`["scl-id"]`, ""}, true},
		{"unknown", []string{`["scl-id"]`, `["other"]`}, true},
		{"malformed", []string{`{"scl":"id"}`}, true},
		{"same domain", []string{`["pn-test"]`}, true},
		{"duplicate", []string{`["scl-id","scl-id"]`}, true},
		{"whitespace", []string{`[" scl-id"]`}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			nodes := []corev1.Node{}
			for i, policy := range tc.policies {
				node := privateNode(fmt.Sprint(i), "vultr://ord/host", "pn-test", "members")
				node.Status.NodeInfo.BootID = "boot"
				node.Annotations["tuist.dev/private-network-revision"] = "script:boot"
				node.Annotations[privateCanonicalNetworksAnnotation] = policy
				nodes = append(nodes, node)
			}
			_, err := privateCanonicalNetworks(nodes, "pn-test")
			if (err != nil) != tc.fail {
				t.Fatalf("policy result: %v", err)
			}
		})
	}
}

func TestPrivateReplicationPublishesCanonicalVPCIDs(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	node := privateNode("ord", "vultr://ord/host", "ord-id", "members")
	node.Status.NodeInfo.BootID = "boot"
	node.Annotations["tuist.dev/private-network-revision"] = "script:boot"
	node.Annotations[privateCanonicalNetworksAnnotation] = `["scl-id"]`
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(&node).Build(), PrivateReplication: true}
	instance := &kurav1alpha1.KuraInstance{Spec: kurav1alpha1.KuraInstanceSpec{NodeSelector: map[string]string{"pool": "cache"}}}
	template := podTemplate(instance, "", "production", "", false, false, false)
	if err := r.configurePrivateReplication(context.Background(), instance, &template, nil); err != nil {
		t.Fatal(err)
	}
	for _, env := range template.Spec.Containers[0].Env {
		if env.Name == peerTopologyEnv {
			var topology struct {
				Network   string   `json:"private_network"`
				Canonical []string `json:"canonical_networks"`
			}
			if err := json.Unmarshal([]byte(env.Value), &topology); err != nil {
				t.Fatal(err)
			}
			if topology.Network != "ord-id" || !slices.Equal(topology.Canonical, []string{"scl-id"}) {
				t.Fatal(topology)
			}
			return
		}
	}
	t.Fatal("topology not published")
}

func TestProductionRegionalPolicyIsStagedBeforeSantiagoQualification(t *testing.T) {
	docs := renderStableChartWithValues(t, "tuist", []string{"templates/_helpers.tpl", "templates/vultr-private-network.yaml"}, []string{"values-managed-common.yaml", "values-managed-production.yaml"})
	for _, doc := range docs {
		if doc["kind"] != "ConfigMap" {
			continue
		}
		data := doc["data"].(map[string]interface{})
		var regions map[string]struct {
			Qualified      bool     `json:"qualified"`
			CanonicalPeers []string `json:"canonicalPeers"`
		}
		if err := json.Unmarshal([]byte(data["regions.json"].(string)), &regions); err != nil {
			t.Fatal(err)
		}
		if !regions["ord"].Qualified || regions["scl"].Qualified || !slices.Equal(regions["ord"].CanonicalPeers, []string{"scl"}) || !slices.Equal(regions["scl"].CanonicalPeers, []string{"ord"}) {
			t.Fatal(regions)
		}
		return
	}
	t.Fatal("regional network ConfigMap missing")
}
