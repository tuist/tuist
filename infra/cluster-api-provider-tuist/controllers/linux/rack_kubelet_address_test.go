package linux

import (
	"context"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func kubeletProxyPod(ip string, ready bool) *corev1.Pod {
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "ts-rack-linux-ber1-edge-kubelet-abcde-0",
			Namespace: "tailscale-operator",
			Labels: map[string]string{
				"tailscale.com/parent-resource":      "rack-linux-ber1-edge-kubelet",
				"tailscale.com/parent-resource-ns":   "tailscale-operator",
				"tailscale.com/parent-resource-type": "svc",
			},
		},
		Status: corev1.PodStatus{
			Phase:      corev1.PodRunning,
			PodIP:      ip,
			Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: status}},
		},
	}
}

func uninitializedEdgeNode() *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge"},
		Spec: corev1.NodeSpec{
			ProviderID: "rack-linux://ber1/ber1-edge",
			Taints: []corev1.Taint{
				{Key: "tuist.dev/rack-edge", Value: "ber1", Effect: corev1.TaintEffectNoSchedule},
				{Key: cloudProviderUninitializedTaint, Value: "true", Effect: corev1.TaintEffectNoSchedule},
			},
		},
		Status: corev1.NodeStatus{
			Addresses: []corev1.NodeAddress{
				{Type: corev1.NodeInternalIP, Address: "100.64.0.7"},
				{Type: corev1.NodeHostName, Address: "ber1-edge"},
			},
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
		},
	}
}

func claimedEdge() (*infrav1.RackLinuxHost, *infrav1.RackLinuxMachine) {
	host := claimedEdgeHost("dev-1")
	host.Status.ClaimedBy = "edge-0"
	machine := edgeMachine()
	machine.Status.RackLinuxHost = "ber1-edge"
	return host, machine
}

func (h *rackMachineHarness) node(t *testing.T) *corev1.Node {
	t.Helper()
	node := &corev1.Node{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Name: "ber1-edge"}, node); err != nil {
		t.Fatal(err)
	}
	return node
}

// The API server reaches a kubelet at the node's ExternalIP first, and a rack
// node's own address is on the tailnet, which the control plane is not. So the
// node's ExternalIP is the address of a proxy Pod that forwards to it.
func TestRackLinuxMachineGivesTheNodeAnAddressTheAPIServerReaches(t *testing.T) {
	host, machine := claimedEdge()
	pod := kubeletProxyPod("10.1.2.3", true)
	objs := append(rackClusterObjects(true), host, machine, uninitializedEdgeNode(), pod)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.reconcile(t)

	svc := &corev1.Service{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: "tailscale-operator", Name: "rack-linux-ber1-edge-kubelet"}, svc); err != nil {
		t.Fatalf("kubelet egress Service: %v", err)
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != "100.64.0.7" {
		t.Errorf("tailnet-ip %q", svc.Annotations["tailscale.com/tailnet-ip"])
	}
	if _, ok := svc.Annotations["tailscale.com/proxy-group"]; ok {
		t.Error("the kubelet egress is on the ProxyGroup, whose Pods do not listen on the kubelet's port")
	}
	// The Tailscale operator tags a proxy of its own with tag:k8s unless told
	// otherwise, which its credential may not mint.
	if svc.Annotations["tailscale.com/tags"] != "tag:tuist-k8s-staging" {
		t.Errorf("tags %q", svc.Annotations["tailscale.com/tags"])
	}
	if len(svc.Spec.Ports) != 1 || svc.Spec.Ports[0].Port != 10250 {
		t.Errorf("ports %+v", svc.Spec.Ports)
	}

	node := h.node(t)
	want := []corev1.NodeAddress{
		{Type: corev1.NodeInternalIP, Address: "100.64.0.7"},
		{Type: corev1.NodeExternalIP, Address: "10.1.2.3"},
		{Type: corev1.NodeHostName, Address: "ber1-edge"},
	}
	if !reflect.DeepEqual(node.Status.Addresses, want) {
		t.Fatalf("addresses %+v", node.Status.Addresses)
	}
	for _, taint := range node.Spec.Taints {
		if taint.Key == cloudProviderUninitializedTaint {
			t.Fatal("the node is still waiting for a cloud provider")
		}
	}
	if len(node.Spec.Taints) != 1 {
		t.Fatalf("taints %+v", node.Spec.Taints)
	}

	pod.Status.PodIP = "10.1.2.4"
	if err := h.c.Status().Update(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	h.reconcile(t)
	if got := h.node(t).Status.Addresses[1].Address; got != "10.1.2.4" {
		t.Fatalf("ExternalIP %q after the proxy moved", got)
	}
}

func TestRackLinuxMachineInitializesTheNodeBeforeItsKubeletProxyIsUp(t *testing.T) {
	host, machine := claimedEdge()
	objs := append(rackClusterObjects(true), host, machine, uninitializedEdgeNode(), kubeletProxyPod("10.1.2.3", false))
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.reconcile(t)

	node := h.node(t)
	want := []corev1.NodeAddress{
		{Type: corev1.NodeInternalIP, Address: "100.64.0.7"},
		{Type: corev1.NodeHostName, Address: "ber1-edge"},
	}
	if !reflect.DeepEqual(node.Status.Addresses, want) {
		t.Fatalf("addresses %+v", node.Status.Addresses)
	}
	for _, taint := range node.Spec.Taints {
		if taint.Key == cloudProviderUninitializedTaint {
			t.Fatal("the node is still waiting for a cloud provider")
		}
	}
}

func TestRackLinuxMachineDeleteRemovesTheKubeletEgress(t *testing.T) {
	host, machine := claimedEdge()
	machine.Finalizers = []string{RackLinuxMachineFinalizer}
	now := metav1.Now()
	machine.DeletionTimestamp = &now
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: "rack-linux-ber1-edge-kubelet", Namespace: "tailscale-operator"}}
	objs := append(rackClusterObjects(true), host, machine, uninitializedEdgeNode(), svc)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.reconcile(t)

	err := h.c.Get(context.Background(), types.NamespacedName{Namespace: "tailscale-operator", Name: "rack-linux-ber1-edge-kubelet"}, &corev1.Service{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("kubelet egress Service still there: %v", err)
	}
}

func TestRackLinuxMachineWakesWhenItsKubeletProxyMoves(t *testing.T) {
	host, machine := claimedEdge()
	objs := append(rackClusterObjects(true), host, machine)
	h := newRackMachineHarness(t, "v1.34.8", objs...)

	got := h.r.machineForKubeletProxy(context.Background(), kubeletProxyPod("10.1.2.3", true))
	want := []reconcile.Request{{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: "edge-0"}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("requests %+v", got)
	}

	other := kubeletProxyPod("10.1.2.3", true)
	other.Labels["tailscale.com/parent-resource"] = "rack-linux-ber1-edge"
	if got := h.r.machineForKubeletProxy(context.Background(), other); len(got) != 0 {
		t.Fatalf("the SSH egress woke %+v", got)
	}
}
