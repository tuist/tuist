package linux

import (
	"context"
	"os/exec"
	"reflect"
	"strings"
	"testing"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestPrivateAddressesSurviveMachineRelease(t *testing.T) {
	ctx := context.Background()
	machine := func(name, service string) *infrav1.OVHDedicatedMachine {
		return &infrav1.OVHDedicatedMachine{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "staging"}, Spec: infrav1.OVHDedicatedMachineSpec{NodeTaints: []corev1.Taint{{Key: "tuist.dev/kura-cache", Effect: corev1.TaintEffectNoSchedule}}}, Status: infrav1.OVHDedicatedMachineStatus{ServiceName: service}}
	}
	a, b := machine("a", "server-a"), machine("b", "server-b")
	c := fake.NewClientBuilder().WithScheme(releaseScheme(t)).WithObjects(a, b).Build()
	r := &OVHDedicatedMachineReconciler{Client: c, PrivateNetworkConfigName: "private-network"}
	first, _, err := r.reservePrivateNetwork(ctx, a, "pn-test", "172.30.241.0/24")
	if err != nil {
		t.Fatal(err)
	}
	old := first.Addresses["server-b"]
	if err := c.Delete(ctx, b); err != nil {
		t.Fatal(err)
	}
	next := machine("c", "server-c")
	if err := c.Create(ctx, next); err != nil {
		t.Fatal(err)
	}
	second, _, err := r.reservePrivateNetwork(ctx, a, "pn-test", "172.30.241.0/24")
	if err != nil {
		t.Fatal(err)
	}
	if second.Addresses["server-b"] != old || second.Addresses["server-c"] == old {
		t.Fatalf("released host's address was recycled: %+v", second)
	}
	if second.Addresses["server-a"] != first.Addresses["server-a"] {
		t.Fatal("existing reservation changed")
	}
}

func TestPrivateNetworkRejectsUnsafeAddressPlans(t *testing.T) {
	for _, cidr := range []string{"10.0.0.1/24", "8.8.8.0/24", "172.30.0.0/16", "172.30.0.0/29", "::1/128"} {
		if err := allocatePrivateNetwork("pn-test", cidr, &privateNetworkReservations{}, []string{"a"}); err == nil {
			t.Fatalf("accepted %s", cidr)
		}
	}
	for _, r := range []privateNetworkReservations{
		{Network: "pn-other", CIDR: "172.30.241.0/24"},
		{Network: "pn-test", CIDR: "172.30.242.0/24"},
		{Addresses: map[string]string{"a": "172.30.241.2", "b": "172.30.241.2"}},
		{Addresses: map[string]string{"a": "172.30.241.1"}},
		{Addresses: map[string]string{"a": "172.30.241.255"}},
	} {
		if err := allocatePrivateNetwork("pn-test", "172.30.241.0/24", &r, []string{"c"}); err == nil {
			t.Fatalf("accepted unsafe reservations %+v", r)
		}
	}
}

func TestPrivateNetworkAllocationIsStableAndBounded(t *testing.T) {
	r := &privateNetworkReservations{}
	if err := allocatePrivateNetwork("pn-test", "172.30.241.0/28", r, []string{"b", "a"}); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(r.Addresses, map[string]string{"a": "172.30.241.2", "b": "172.30.241.3"}) {
		t.Fatal(r.Addresses)
	}
	for i := 0; i < 11; i++ {
		if err := allocatePrivateNetwork("pn-test", "172.30.241.0/28", r, []string{string(rune('c' + i))}); err != nil {
			t.Fatal(err)
		}
	}
	if err := allocatePrivateNetwork("pn-test", "172.30.241.0/28", r, []string{"overflow"}); err == nil {
		t.Fatal("accepted an exhausted pool")
	}
}

func TestPrivateNetworkDoesNotEnrollRunnerOrOtherNamespaces(t *testing.T) {
	r := &OVHDedicatedMachineReconciler{PrivateNetworkConfigName: "network", PrivateNetworkNamespace: "staging"}
	for _, m := range []*infrav1.OVHDedicatedMachine{
		{ObjectMeta: metav1.ObjectMeta{Namespace: "production"}},
		{ObjectMeta: metav1.ObjectMeta{Namespace: "staging"}, Spec: infrav1.OVHDedicatedMachineSpec{KataRuntime: true}},
		{ObjectMeta: metav1.ObjectMeta{Namespace: "staging"}},
	} {
		if err := r.reconcilePrivateNetwork(context.Background(), m, &corev1.Node{}); err != nil {
			t.Fatal(err)
		}
	}
}

func TestPrivateNetworkScriptSyntax(t *testing.T) {
	script := renderPrivateNetworkScript("00:11:22:33:44:55", "172.30.241.2", 24, "192.0.2.1", []privateNetworkPeer{{Public: "192.0.2.2", Private: "172.30.241.3"}})
	command := exec.Command("bash", "-n")
	command.Stdin = strings.NewReader(script)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("invalid script: %s: %v", output, err)
	}
}
