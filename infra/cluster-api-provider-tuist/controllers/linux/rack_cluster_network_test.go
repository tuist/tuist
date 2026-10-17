package linux

import (
	"context"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func storeConvergeOptions() rackConvergeOptions {
	o := edgeConvergeOptions()
	o.NodeName, o.Role, o.Edge = "ber1-store-a", "storage", nil
	o.NodeLabels = map[string]string{"tuist.dev/rack-storage": "ber1"}
	o.ClusterNetwork = &infrav1.RackLinuxHostClusterNetwork{PublicAddress: "149.6.170.31", Address: "10.10.0.11"}
	o.NodeIP = o.ClusterNetwork.PublicAddress
	return o
}

func absent(cfg infrav1.RackNodeConfig, path string) bool {
	return slices.ContainsFunc(cfg.Absent, func(f infrav1.RackNodeFile) bool { return f.Path == path })
}

func written(cfg infrav1.RackNodeConfig, path string) bool {
	return slices.ContainsFunc(cfg.Files, func(f infrav1.RackNodeFile) bool { return f.Path == path })
}

// A cluster-network host runs Cilium at its site's public address: no Cilium
// exclusion, no bridge CNI, the public address held on a dummy interface for
// the kubelet and Cilium to bind, and Cilium's health probe handed to it from
// the host's own address, where the edge forwards it.
func TestRackNodeConfigPutsAClusterNetworkHostOnCilium(t *testing.T) {
	cfg := rackNodeConfig(storeConvergeOptions())

	unit := configFile(t, cfg, "/etc/systemd/system/kubelet.service").Content
	if !strings.Contains(unit, "--node-ip=149.6.170.31") {
		t.Error("the kubelet does not register at the public address")
	}
	if strings.Contains(unit, ciliumNoScheduleLabel) {
		t.Error("a cluster-network node registers with the Cilium exclusion")
	}
	if written(cfg, rackLocalCNIPath) || !absent(cfg, rackLocalCNIPath) {
		t.Error("the bridge CNI's configuration would shadow Cilium's")
	}

	netdev := configFile(t, cfg, rackClusterAddressNetdevPath)
	network := configFile(t, cfg, rackClusterAddressNetworkPath)
	if netdev.Group != "networkd" || network.Group != "networkd" {
		t.Errorf("networkd creates a new netdev only when it restarts: %q %q", netdev.Group, network.Group)
	}
	if !strings.Contains(netdev.Content, "Kind=dummy") || !strings.Contains(network.Content, "Address=149.6.170.31/32") {
		t.Errorf("the dummy interface does not hold the public address:\n%s\n%s", netdev.Content, network.Content)
	}

	health := configFile(t, cfg, rackClusterHealthPath).Content
	if !strings.Contains(health, "ip daddr 10.10.0.11 tcp dport 4240 dnat to 149.6.170.31") || !strings.Contains(health, "delete table ip tuist_cluster_health") {
		t.Errorf("health rules:\n%s", health)
	}
	if !slices.Contains(cfg.Nftables, rackClusterHealthPath) {
		t.Error("the health rules are never loaded")
	}
	if !strings.Contains(configFile(t, cfg, rackCiliumSysctlPath).Content, "net.ipv4.conf.lxc*.rp_filter = 0") ||
		!slices.Contains(cfg.Sysctl, infrav1.RackNodeSysctl{Path: rackCiliumSysctlPath}) {
		t.Error("the pods' interfaces keep strict reverse-path filtering")
	}
	if written(cfg, rackClusterForwardsPath) || len(cfg.ClusterNodeSets) != 0 {
		t.Error("only an edge forwards")
	}
}

func TestRackNodeConfigKeepsOtherRackHostsOnTheBridge(t *testing.T) {
	o := storeConvergeOptions()
	o.ClusterNetwork, o.NodeIP = nil, "100.64.0.9"
	cfg := rackNodeConfig(o)

	if !strings.Contains(configFile(t, cfg, "/etc/systemd/system/kubelet.service").Content, ciliumNoScheduleLabel+"=true") {
		t.Error("a bridge node lost the Cilium exclusion")
	}
	if !written(cfg, rackLocalCNIPath) {
		t.Error("a bridge node has no CNI")
	}
	for _, path := range []string{rackClusterAddressNetdevPath, rackClusterAddressNetworkPath, rackClusterHealthPath, rackCiliumSysctlPath} {
		if written(cfg, path) {
			t.Errorf("a bridge node writes %s", path)
		}
	}
}

// An edge forwards the cluster's ports on the site's public address to each
// cluster-network host, from the addresses the agent keeps in the set. The set
// is declared, never flushed, so reloading the file keeps what the agent put
// in it.
func TestRackNodeConfigForwardsTheSitesClusterNetworkHostsFromTheEdge(t *testing.T) {
	o := edgeConvergeOptions()
	o.Forwards = []infrav1.RackLinuxHostClusterNetwork{{PublicAddress: "149.6.170.31", Address: "10.10.0.11"}}
	cfg := rackNodeConfig(o)

	rules := configFile(t, cfg, rackClusterForwardsPath).Content
	for _, want := range []string{
		"add set ip tuist_cluster_forwards nodes { type ipv4_addr; }",
		"flush chain ip tuist_cluster_forwards prerouting",
		`iifname "wan0" ip daddr 149.6.170.31 ip saddr @nodes udp dport 8472 dnat to 10.10.0.11`,
		`iifname "wan0" ip daddr 149.6.170.31 ip saddr @nodes tcp dport { 4240, 10250 } dnat to 10.10.0.11`,
	} {
		if !strings.Contains(rules, want) {
			t.Errorf("the forwards lack %q:\n%s", want, rules)
		}
	}
	for _, forbidden := range []string{"delete table", "flush set", "flush table"} {
		if strings.Contains(rules, forbidden) {
			t.Errorf("reloading the forwards would empty the set (%q):\n%s", forbidden, rules)
		}
	}
	if !slices.Contains(cfg.Nftables, rackClusterForwardsPath) {
		t.Error("the forwards are never loaded")
	}
	if want := []infrav1.RackNodeNftSet{{Family: "ip", Table: "tuist_cluster_forwards", Name: "nodes"}}; !slices.Equal(cfg.ClusterNodeSets, want) {
		t.Errorf("cluster node sets %+v", cfg.ClusterNodeSets)
	}

	// With nothing to forward the chain is still rewritten, empty, so a host
	// leaving the cluster network stops being forwarded to.
	o.Forwards = nil
	rules = configFile(t, rackNodeConfig(o), rackClusterForwardsPath).Content
	if strings.Contains(rules, "dnat") || !strings.Contains(rules, "flush chain ip tuist_cluster_forwards prerouting") {
		t.Errorf("an edge with nothing to forward:\n%s", rules)
	}
}

// A cluster-network host is reached at its site's public address, by the
// control plane for the kubelet as by every node for Cilium's tunnel, so that
// is its only address but its name, its kubelet proxy goes, and its Node loses
// the Cilium exclusion it registered with.
func TestRackLinuxMachineReachesAClusterNetworkNodeAtItsPublicAddress(t *testing.T) {
	host, machine := claimedEdge()
	host.Spec.Role = "storage"
	host.Spec.ClusterNetwork = &infrav1.RackLinuxHostClusterNetwork{PublicAddress: "149.6.170.31", Address: "10.10.0.11"}
	node := uninitializedEdgeNode()
	node.Labels = map[string]string{ciliumNoScheduleLabel: "true", "tuist.dev/rack-storage": "ber1"}
	proxy := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: "rack-linux-" + edgeUUID + "-kubelet", Namespace: "tailscale-operator"}}
	objs := append(rackClusterObjects(true), host, machine, node, proxy, kubeletProxyPod("10.1.2.3", true))
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	m := h.reconcile(t)

	got := h.node(t)
	want := []corev1.NodeAddress{
		{Type: corev1.NodeInternalIP, Address: "149.6.170.31"},
		{Type: corev1.NodeHostName, Address: "ber1-edge"},
	}
	if !reflect.DeepEqual(got.Status.Addresses, want) {
		t.Fatalf("addresses %+v", got.Status.Addresses)
	}
	// Cilium binds its health responder to the node IP once, when it starts,
	// so it must not be scheduled before the host holds the address.
	if got.Labels[ciliumNoScheduleLabel] != "true" {
		t.Fatal("the Cilium exclusion went before the host ran the configuration holding the address")
	}

	m.Status.Agent = &infrav1.RackNodeAgentStatus{AppliedHash: m.Status.NodeConfig.Hash, AppliedAt: &metav1.Time{Time: time.Now()}}
	if err := h.c.Status().Update(context.Background(), m); err != nil {
		t.Fatal(err)
	}
	h.reconcile(t)
	got = h.node(t)
	if _, ok := got.Labels[ciliumNoScheduleLabel]; ok {
		t.Error("the node keeps the Cilium exclusion once the host holds the address")
	}
	if got.Labels["tuist.dev/rack-storage"] != "ber1" {
		t.Errorf("labels %v", got.Labels)
	}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: "tailscale-operator", Name: proxy.Name}, &corev1.Service{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the kubelet egress is still there: %v", err)
	}
}

// An edge forwards to the cluster-network hosts of its own site only.
func TestRackLinuxMachineForwardsTheSitesClusterNetworkHostsFromItsEdge(t *testing.T) {
	host, machine := claimedEdge()
	store := func(name, site, public string) *infrav1.RackLinuxHost {
		h := edgeHost()
		h.Name, h.Spec.Hostname, h.Spec.Role, h.Spec.Location.Site = name, name, "storage", site
		h.Spec.ClusterNetwork = &infrav1.RackLinuxHostClusterNetwork{PublicAddress: public, Address: "10.10.0.11"}
		return h
	}
	objs := append(rackClusterObjects(true), host, machine, uninitializedEdgeNode(),
		store("ber1-store-a", "ber1", "149.6.170.31"), store("ams1-store-a", "ams1", "203.0.113.9"))
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	m := h.reconcile(t)
	if m.Status.NodeConfig == nil {
		t.Fatal("no node configuration was published")
	}

	rules := configFile(t, *m.Status.NodeConfig, rackClusterForwardsPath).Content
	if !strings.Contains(rules, "ip daddr 149.6.170.31") || strings.Contains(rules, "203.0.113.9") {
		t.Errorf("the edge forwards:\n%s", rules)
	}
	requests := h.r.machinesForHost(context.Background(), store("ber1-store-a", "ber1", "149.6.170.31"))
	if !slices.ContainsFunc(requests, func(r reconcile.Request) bool { return r.Name == edgeUUID }) {
		t.Errorf("a change to the site's store does not wake its edge: %v", requests)
	}
}
