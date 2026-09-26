package racknode

import (
	"context"
	"fmt"
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
	if cfg == nil || (cfg.Hash == a.applied && now.Sub(a.appliedAt) < a.Reapply) {
		return nil
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
	return applyErr
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
