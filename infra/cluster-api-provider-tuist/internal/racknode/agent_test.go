package racknode

import (
	"context"
	"slices"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const agentUUID = "44312e80-1dc6-11f1-853e-8f903547d200"

type lockingFake struct {
	*fakeHost
	locks int
}

func (l *lockingFake) Lock() (func(), error) {
	l.locks++
	return func() {}, nil
}

func newAgent(t *testing.T, cfg *infrav1.RackNodeConfig) (*Agent, client.Client, *lockingFake, *time.Time) {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge-a"}, Spec: corev1.NodeSpec{ProviderID: "rack-linux://ber1/" + agentUUID}}
	machine := &infrav1.RackLinuxMachine{ObjectMeta: metav1.ObjectMeta{Name: agentUUID, Namespace: "tuist"}}
	machine.Status.NodeConfig = cfg
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node, machine).WithStatusSubresource(&infrav1.RackLinuxMachine{}).Build()
	host := &lockingFake{fakeHost: newFakeHost()}
	host.withIdentity(t, testNow.Add(24*time.Hour))
	now := testNow
	a := &Agent{Client: c, Host: host, Namespace: "tuist", Node: "ber1-edge-a", Reapply: 5 * time.Minute, Now: func() time.Time { return now }}
	return a, c, host, &now
}

func agentReport(t *testing.T, c client.Client) *infrav1.RackNodeAgentStatus {
	t.Helper()
	m := &infrav1.RackLinuxMachine{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: "tuist", Name: agentUUID}, m); err != nil {
		t.Fatal(err)
	}
	return m.Status.Agent
}

// The agent applies the configuration of the machine its Node belongs to, and
// reports it.
func TestAgentAppliesItsMachinesConfigurationAndReports(t *testing.T) {
	cfg := testConfig()
	a, c, host, _ := newAgent(t, &cfg)

	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}

	report := agentReport(t, c)
	if report == nil || report.AppliedHash != "hash-1" || report.Error != "" || report.AppliedAt == nil || len(report.Changed) == 0 {
		t.Fatalf("report %+v", report)
	}
	if host.locks != 1 || string(host.files[HashPath].data) != "hash-1\n" {
		t.Fatalf("locks %d, applied %q", host.locks, host.files[HashPath].data)
	}
}

// An unchanged configuration is applied again only every Reapply, to repair
// drift, and a new one at once.
func TestAgentAppliesANewConfigurationAtOnceAndAnUnchangedOneNowAndThen(t *testing.T) {
	cfg := testConfig()
	a, c, host, now := newAgent(t, &cfg)
	ctx := context.Background()
	if err := a.Once(ctx); err != nil {
		t.Fatal(err)
	}

	*now = now.Add(time.Minute)
	if err := a.Once(ctx); err != nil || host.locks != 1 {
		t.Fatalf("applied again after a minute (%d applies, %v)", host.locks, err)
	}

	*now = now.Add(5 * time.Minute)
	if err := a.Once(ctx); err != nil || host.locks != 2 {
		t.Fatalf("did not repair drift after Reapply (%d applies, %v)", host.locks, err)
	}

	m := &infrav1.RackLinuxMachine{}
	if err := c.Get(ctx, types.NamespacedName{Namespace: "tuist", Name: agentUUID}, m); err != nil {
		t.Fatal(err)
	}
	next := testConfig()
	next.Hash = "hash-2"
	m.Status.NodeConfig = &next
	if err := c.Status().Update(ctx, m); err != nil {
		t.Fatal(err)
	}
	*now = now.Add(time.Second)
	if err := a.Once(ctx); err != nil || host.locks != 3 || agentReport(t, c).AppliedHash != "hash-2" {
		t.Fatalf("did not apply the new configuration at once (%d applies, %v)", host.locks, err)
	}
}

func TestAgentReportsAKubeletWithoutIdentity(t *testing.T) {
	cfg := testConfig()
	a, c, host, _ := newAgent(t, &cfg)
	delete(host.files, KubeletClientCertPath)

	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}

	if report := agentReport(t, c); report.AppliedHash != "" || report.Error == "" {
		t.Fatalf("report %+v", report)
	}
}

func TestAgentWaitsForAConfiguration(t *testing.T) {
	a, c, host, _ := newAgent(t, nil)

	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}
	if host.locks != 0 || agentReport(t, c) != nil {
		t.Fatal("applied without a configuration")
	}
}

func clusterNode(name, os string, excluded bool, addresses ...string) *corev1.Node {
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name, Labels: map[string]string{"kubernetes.io/os": os}}}
	if excluded {
		node.Labels["cilium.io/no-schedule"] = "true"
	}
	for _, address := range addresses {
		node.Status.Addresses = append(node.Status.Addresses, corev1.NodeAddress{Type: corev1.NodeInternalIP, Address: address})
	}
	return node
}

// The nodes that run Cilium are the Linux nodes without its exclusion: not
// the macOS hosts, not the rack's bridge nodes, and only their IPv4
// InternalIPs.
func TestClusterNodeAddressesAreTheCiliumNodes(t *testing.T) {
	nodes := []corev1.Node{
		*clusterNode("eu-west-a", "linux", false, "51.68.54.127", "2001:db8::1"),
		*clusterNode("hetzner-cp", "linux", false, "49.12.18.71"),
		*clusterNode("ber1-store-a", "linux", false, "149.6.170.31"),
		*clusterNode("ber1-edge-a", "linux", true, "100.102.176.95"),
		*clusterNode("mini", "darwin", false, "100.66.118.128"),
		*clusterNode("eu-west-b", "linux", false, "51.68.54.127"),
	}
	want := []string{"149.6.170.31", "49.12.18.71", "51.68.54.127"}
	if got := ClusterNodeAddresses(nodes); !slices.Equal(got, want) {
		t.Fatalf("addresses %v, want %v", got, want)
	}
}

// The agent keeps the configuration's sets equal to the Cilium nodes'
// addresses: once applied, when a node joins, and not again while nothing
// changes, each in one transaction.
func TestAgentKeepsTheClusterNodeSetsEqualToTheCiliumNodes(t *testing.T) {
	cfg := testConfig()
	cfg.ClusterNodeSets = []infrav1.RackNodeNftSet{{Family: "ip", Table: "tuist_cluster_forwards", Name: "nodes"}}
	a, c, host, now := newAgent(t, &cfg)
	ctx := context.Background()
	if err := c.Create(ctx, clusterNode("eu-west-a", "linux", false, "51.68.54.127")); err != nil {
		t.Fatal(err)
	}

	if err := a.Once(ctx); err != nil {
		t.Fatal(err)
	}
	want := "flush set ip tuist_cluster_forwards nodes\nadd element ip tuist_cluster_forwards nodes { 51.68.54.127 }\n"
	if len(host.stdin) != 1 || host.stdin[0] != want {
		t.Fatalf("synced %q, want %q", host.stdin, want)
	}

	*now = now.Add(time.Minute)
	if err := a.Once(ctx); err != nil || len(host.stdin) != 1 {
		t.Fatalf("synced an unchanged set again (%d, %v)", len(host.stdin), err)
	}

	if err := c.Create(ctx, clusterNode("us-east-a", "linux", false, "15.204.1.2")); err != nil {
		t.Fatal(err)
	}
	*now = now.Add(time.Minute)
	if err := a.Once(ctx); err != nil {
		t.Fatal(err)
	}
	want = "flush set ip tuist_cluster_forwards nodes\nadd element ip tuist_cluster_forwards nodes { 15.204.1.2, 51.68.54.127 }\n"
	if len(host.stdin) != 2 || host.stdin[1] != want {
		t.Fatalf("after a node joined, synced %q", host.stdin)
	}
}

func TestAgentSyncsNoSetsWithoutAny(t *testing.T) {
	cfg := testConfig()
	a, _, host, _ := newAgent(t, &cfg)
	if err := a.Once(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(host.stdin) != 0 {
		t.Fatalf("synced %q", host.stdin)
	}
}
