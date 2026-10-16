package racknode

import (
	"context"
	"fmt"
	"net"
	"slices"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// Response is what `rack-node apply` writes: the result, and why the apply
// failed when it did.
type Response struct {
	Result
	Error string `json:"error,omitempty"`
}

// LockingHost is a host whose applies do not overlap.
type LockingHost interface {
	Host
	Lock() (func(), error)
}

// Agent keeps a rack node's configuration applied from the node agent's pod:
// the configuration in the status of the RackLinuxMachine its Node belongs
// to, applied when it changes and every Reapply otherwise, and what it did
// reported in that status's agent field.
type Agent struct {
	Client    client.Client
	Host      LockingHost
	Namespace string
	Node      string
	Reapply   time.Duration

	// Now is overridden in tests.
	Now func() time.Time

	applied   string
	appliedAt time.Time

	synced   string
	syncedAt time.Time
}

func (a *Agent) now() time.Time {
	if a.Now != nil {
		return a.Now()
	}
	return time.Now()
}

// Once applies the configuration when it is new or due again.
func (a *Agent) Once(ctx context.Context) error {
	name, err := a.machineName(ctx)
	if err != nil {
		return err
	}
	machine := &infrav1.RackLinuxMachine{}
	if err := a.Client.Get(ctx, types.NamespacedName{Namespace: a.Namespace, Name: name}, machine); err != nil {
		return fmt.Errorf("read RackLinuxMachine %s: %w", name, err)
	}
	cfg := machine.Status.NodeConfig
	now := a.now()
	if cfg == nil {
		return nil
	}
	if cfg.Hash == a.applied && now.Sub(a.appliedAt) < a.Reapply {
		return a.syncClusterNodeSets(ctx, cfg.ClusterNodeSets)
	}

	unlock, err := a.Host.Lock()
	if err != nil {
		return err
	}
	res, applyErr := Apply(ctx, a.Host, Request{Config: *cfg}, Options{Now: a.Now})
	unlock()

	report := infrav1.RackNodeAgentStatus{AppliedAt: &metav1.Time{Time: now}}
	if previous := machine.Status.Agent; previous != nil {
		report.Changed, report.Restarted = previous.Changed, previous.Restarted
	}
	if len(res.Changed) > 0 || len(res.Restarted) > 0 {
		report.Changed, report.Restarted = res.Changed, res.Restarted
	}
	switch {
	case applyErr != nil:
		report.Error = applyErr.Error()
	case res.ForeignJoin:
		report.Error = "kubeadm joined this host, so the agent leaves it alone"
	case res.NeedsBootstrap:
		report.Error = "the kubelet has no client certificate; the operator joins the host again over SSH"
	default:
		report.AppliedHash = res.Applied
		a.applied, a.appliedAt = res.Applied, now
	}
	orig := machine.DeepCopy()
	machine.Status.Agent = &report
	if err := a.Client.Status().Patch(ctx, machine, client.MergeFrom(orig)); err != nil {
		return fmt.Errorf("report on RackLinuxMachine %s: %w", name, err)
	}
	if applyErr != nil || report.AppliedHash == "" {
		return applyErr
	}
	// An apply reloads the sets' files, which keeps their elements, but the
	// sets may be new.
	a.synced = ""
	return a.syncClusterNodeSets(ctx, cfg.ClusterNodeSets)
}

// machineName is the RackLinuxMachine the agent's Node belongs to, the last
// part of its rack-linux://<site>/<host> providerID.
func (a *Agent) machineName(ctx context.Context) (string, error) {
	node := &corev1.Node{}
	if err := a.Client.Get(ctx, types.NamespacedName{Name: a.Node}, node); err != nil {
		return "", fmt.Errorf("read Node %s: %w", a.Node, err)
	}
	rest, ok := strings.CutPrefix(node.Spec.ProviderID, "rack-linux://")
	parts := strings.Split(rest, "/")
	if !ok || len(parts) != 2 || parts[1] == "" {
		return "", fmt.Errorf("Node %s is not a rack Linux node (providerID %q)", a.Node, node.Spec.ProviderID)
	}
	return parts[1], nil
}

// syncClusterNodeSets keeps the configuration's cluster node sets equal to the
// cluster's Cilium nodes' addresses: when they change, and every Reapply to
// repair drift. Each set is replaced in one nft transaction, so it is never
// seen empty while it changes.
func (a *Agent) syncClusterNodeSets(ctx context.Context, sets []infrav1.RackNodeNftSet) error {
	if len(sets) == 0 {
		return nil
	}
	nodes := &corev1.NodeList{}
	if err := a.Client.List(ctx, nodes); err != nil {
		return fmt.Errorf("list the cluster's nodes: %w", err)
	}
	addresses := ClusterNodeAddresses(nodes.Items)
	key := strings.Join(addresses, ",")
	now := a.now()
	if key == a.synced && now.Sub(a.syncedAt) < a.Reapply {
		return nil
	}
	if _, err := a.Host.Run(ctx, []byte(clusterNodeSetsScript(sets, addresses)), "nft", "-f", "-"); err != nil {
		return fmt.Errorf("sync the cluster node sets: %w", err)
	}
	a.synced, a.syncedAt = key, now
	return nil
}

// ClusterNodeAddresses are the IPv4 InternalIPs of the nodes that run Cilium:
// Linux nodes without the Cilium exclusion, sorted.
func ClusterNodeAddresses(nodes []corev1.Node) []string {
	var addresses []string
	for i := range nodes {
		node := &nodes[i]
		if node.Labels["kubernetes.io/os"] != "linux" || node.Labels["cilium.io/no-schedule"] == "true" {
			continue
		}
		for _, address := range node.Status.Addresses {
			if ip := net.ParseIP(address.Address); address.Type == corev1.NodeInternalIP && ip != nil && ip.To4() != nil {
				addresses = append(addresses, ip.To4().String())
			}
		}
	}
	sort.Strings(addresses)
	return slices.Compact(addresses)
}

func clusterNodeSetsScript(sets []infrav1.RackNodeNftSet, addresses []string) string {
	var b strings.Builder
	for _, set := range sets {
		fmt.Fprintf(&b, "flush set %s %s %s\n", set.Family, set.Table, set.Name)
		if len(addresses) > 0 {
			fmt.Fprintf(&b, "add element %s %s %s { %s }\n", set.Family, set.Table, set.Name, strings.Join(addresses, ", "))
		}
	}
	return b.String()
}
