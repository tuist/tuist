package controllers

import (
	"context"
	"encoding/json"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
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

func TestPrivateReplicationDoesNotSilentlyRemoveActiveTopology(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).Build(), PrivateReplication: true}
	previous := &corev1.PodTemplateSpec{ObjectMeta: metav1.ObjectMeta{Annotations: map[string]string{managedTopologyAnnotation: "true"}}}
	if err := r.configurePrivateReplication(context.Background(), &kurav1alpha1.KuraInstance{}, &corev1.PodTemplateSpec{}, previous); err == nil {
		t.Fatal("missing nodes silently disabled the private route policy")
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
