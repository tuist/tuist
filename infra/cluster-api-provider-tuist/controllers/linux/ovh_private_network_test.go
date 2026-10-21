package linux

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
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
	for _, render := range []func(string, string, int, string, []privateNetworkPeer, ...privateNetworkOwners) string{renderPrivateNetworkScript, renderVultrPrivateNetworkScript} {
		script := render("00:11:22:33:44:55", "172.30.241.2", 24, "192.0.2.1", []privateNetworkPeer{{Public: "192.0.2.2", Private: "172.30.241.3"}})
		command := exec.Command("bash", "-n")
		command.Stdin = strings.NewReader(script)
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("invalid script: %s: %v", output, err)
		}
	}
}

func TestPrivateNetworkGuardRetirement(t *testing.T) {
	for _, tc := range []struct {
		name     string
		owners   privateNetworkOwners
		oldOwner string
		retired  bool
	}{
		{"failed host", privateNetworkOwners{"peer": "192.0.2.2"}, "peer", false},
		{"missing address", privateNetworkOwners{"peer": ""}, "peer", false},
		{"completed deletion", privateNetworkOwners{"other": "192.0.2.3"}, "peer", true},
		{"public address reused", privateNetworkOwners{"other": "192.0.2.2"}, "peer", true},
		{"legacy unknown ownership", privateNetworkOwners{}, "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "private-network-guard-peers"), []byte("192.0.2.2 172.30.241.3\n"), 0600); err != nil {
				t.Fatal(err)
			}
			owners := ""
			if tc.oldOwner != "" {
				owners = "192.0.2.2 " + tc.oldOwner + "\n"
			}
			if err := os.WriteFile(filepath.Join(dir, "private-network-guard-owners"), []byte(owners), 0600); err != nil {
				t.Fatal(err)
			}
			script := renderPrivateNetworkScript("00:11:22:33:44:55", "172.30.241.2", 24, "192.0.2.1", nil, tc.owners)
			start := strings.Index(script, "cat > /etc/tuist/private-network-peers.new")
			end := strings.Index(script, "cat > /usr/local/sbin/tuist-private-network.new")
			// Execute the actual generated file/route reconciliation, with only
			// host paths and the ip command replaced by an isolated recorder.
			script = "set -euo pipefail\nip() { echo \"$*\" >> '" + dir + "/routes'; }\n" + strings.ReplaceAll(script[start:end], "/etc/tuist", dir)
			cmd := exec.Command("bash", "-c", script)
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("%s: %v", output, err)
			}
			guards, err := os.ReadFile(filepath.Join(dir, "private-network-guard-peers"))
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(guards), "192.0.2.2") == tc.retired {
				t.Fatalf("incorrect guards: %s", guards)
			}
			routes, _ := os.ReadFile(filepath.Join(dir, "routes"))
			if strings.Contains(string(routes), "del unreachable 192.0.2.2/32 metric 32767 proto 242") != tc.retired {
				t.Fatalf("incorrect route retirement: %s", routes)
			}
		})
	}
}

func TestDeletingOVHMachineRetainsGuardButLeavesPreflightAndMembership(t *testing.T) {
	now := metav1.Now()
	machine := infrav1.OVHDedicatedMachine{ObjectMeta: metav1.ObjectMeta{Name: "departing", UID: "old", DeletionTimestamp: &now}, Spec: infrav1.OVHDedicatedMachineSpec{NodeTaints: []corev1.Taint{{Key: "tuist.dev/kura-cache", Effect: corev1.TaintEffectNoSchedule}}}, Status: infrav1.OVHDedicatedMachineStatus{ServiceName: "retired", Addresses: []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: "192.0.2.2"}}}}
	peers, members, owners := ovhPrivateParticipants("local", []infrav1.OVHDedicatedMachine{machine}, &privateNetworkReservations{Addresses: map[string]string{"retired": "172.30.241.3"}})
	if len(peers) != 0 || len(members) != 0 || owners["departing/old"] != "192.0.2.2" {
		t.Fatalf("inconsistent deleting membership: %v %v %v", peers, members, owners)
	}
}

func TestPrivateNetworkProviderMTUSettings(t *testing.T) {
	script := renderVultrPrivateNetworkScript("00:11:22:33:44:55", "172.30.241.2", 24, "192.0.2.1", nil)
	if strings.Count(script, `ip link set dev "$iface" mtu 1500`) != 2 || strings.Count(script, "-M do -s 1472") != 2 || strings.Contains(script, "sudo bash") {
		t.Fatal("Vultr preparation or repair lost qualified MTU/root settings")
	}
}

func TestPrivateNetworkFailedRetirementRetainsIntent(t *testing.T) {
	dir := t.TempDir()
	for name, data := range map[string]string{
		"private-network-guard-peers":  "192.0.2.2 172.30.241.3\n",
		"private-network-guard-owners": "192.0.2.2 retired/uid\n",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	script := renderPrivateNetworkScript("00:11:22:33:44:55", "172.30.241.2", 24, "192.0.2.1", nil, privateNetworkOwners{})
	start := strings.Index(script, "cat > /etc/tuist/private-network-peers.new")
	end := strings.Index(script, "cat > /usr/local/sbin/tuist-private-network.new")
	script = "set -euo pipefail\nip() { case \"$*\" in *'route show exact'*) echo 'unreachable 192.0.2.2 proto 242';; esac; }\n" + strings.ReplaceAll(script[start:end], "/etc/tuist", dir)
	if output, err := exec.Command("bash", "-c", script).CombinedOutput(); err == nil || !strings.Contains(string(output), "retaining cleanup intent") {
		t.Fatalf("lost failed cleanup: %s %v", output, err)
	}
	owners, err := os.ReadFile(filepath.Join(dir, "private-network-guard-owners"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(owners), "retired/uid") {
		t.Fatal("failed retirement lost its owner")
	}
}

type fakeOVHVRackAPI struct{ fakeOVHAPI }

func (f *fakeOVHVRackAPI) GetWithContext(_ context.Context, path string, res any) error {
	var body any
	switch {
	case strings.HasSuffix(path, "/networkInterfaceController?linkType=private"):
		body = []string{"aa:bb:cc:dd:ee:01"}
	case strings.Contains(path, "/networkInterfaceController/"):
		body = map[string]string{"virtualNetworkInterface": "vni-1"}
	case strings.Contains(path, "/virtualNetworkInterface/"):
		body = map[string]any{"enabled": true, "mode": "vrack", "vrack": "pn-test"}
	default:
		return fmt.Errorf("unexpected OVH GET %s", path)
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, res)
}

func TestPrivateNetworkWaitingOnPeerIsPendingNotFailure(t *testing.T) {
	ctx := context.Background()
	machine := func(name, service, ip string) *infrav1.OVHDedicatedMachine {
		return &infrav1.OVHDedicatedMachine{
			ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist", UID: types.UID(name + "-uid")},
			Spec:       infrav1.OVHDedicatedMachineSpec{NodeTaints: []corev1.Taint{{Key: "tuist.dev/kura-cache", Effect: corev1.TaintEffectNoSchedule}}},
			Status:     infrav1.OVHDedicatedMachineStatus{ServiceName: service, Addresses: []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: ip}}},
		}
	}
	local, lagging, stale := machine("a", "server-a", "198.51.100.1"), machine("b", "server-b", "198.51.100.2"), machine("c", "server-c", "198.51.100.3")
	config := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "private-network", Namespace: "tuist"}, Data: map[string]string{"vrackID": "pn-test", "cidr": "172.30.241.0/24"}}
	node := func(name string) *corev1.Node {
		return &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}, Status: corev1.NodeStatus{NodeInfo: corev1.NodeSystemInfo{BootID: name + "-boot"}}}
	}
	c := fake.NewClientBuilder().WithScheme(releaseScheme(t)).WithObjects(local, lagging, stale, config, node("a"), node("b"), node("c")).Build()
	r := &OVHDedicatedMachineReconciler{Client: c, OVHClient: &ovh.Client{API: &fakeOVHVRackAPI{}}, PrivateNetworkConfigName: "private-network", PrivateNetworkNamespace: "tuist"}

	// The local host already installed the current membership; its peers still
	// carry an older one, so it can only wait for them.
	reservations, machines, err := r.reservePrivateNetwork(ctx, local, "pn-test", "172.30.241.0/24")
	if err != nil {
		t.Fatal(err)
	}
	peers, members, owners := ovhPrivateParticipants("server-a", machines, reservations)
	membership := fmt.Sprintf("%x", sha256.Sum256([]byte(strings.Join(members, "\n"))))
	script := renderPrivateNetworkScript("aa:bb:cc:dd:ee:01", reservations.Addresses["server-a"], 24, "198.51.100.1", peers, owners)
	for name, annotations := range map[string]map[string]string{
		"a": {privateNetworkAnnotation: "pn-test", privateNetworkMembers: membership, privateNetworkRevision: fmt.Sprintf("%x:a-boot", sha256.Sum256([]byte(script)))},
		"b": {privateNetworkAnnotation: "pn-test", privateNetworkMembers: "older"},
		"c": {privateNetworkAnnotation: "pn-test", privateNetworkMembers: "older"},
	} {
		n := &corev1.Node{}
		if err := c.Get(ctx, types.NamespacedName{Name: name}, n); err != nil {
			t.Fatal(err)
		}
		n.Annotations = annotations
		if err := c.Update(ctx, n); err != nil {
			t.Fatal(err)
		}
	}
	current := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: "a"}, current); err != nil {
		t.Fatal(err)
	}

	err = r.reconcilePrivateNetwork(ctx, local, current)

	var pending *privateNetworkPending
	if !errors.As(err, &pending) {
		t.Fatalf("waiting on peers must be reported as pending, got %v", err)
	}
	if !reflect.DeepEqual(pending.peers, []string{"b", "c"}) {
		t.Fatalf("pending must name every lagging peer, got %v", pending.peers)
	}
	condition := conditions.Get(local, privateNetworkReady)
	if condition == nil || condition.Status != corev1.ConditionFalse || condition.Reason != "WaitingForPeerRoutes" || condition.Severity != clusterv1.ConditionSeverityInfo {
		t.Fatalf("unexpected condition %+v", condition)
	}
	if current.Labels[privateNetworkAnnotation] != "" {
		t.Fatal("topology advertised before every peer installed the membership")
	}
}
