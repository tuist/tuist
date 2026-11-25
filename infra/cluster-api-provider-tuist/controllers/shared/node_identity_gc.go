package shared

import (
	"context"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/util/wait"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

var (
	orphanedNodeIdentitiesGauge = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "capt_orphaned_node_identities",
		Help: "Operator-minted tart-kubelet-<machine> node identities (ServiceAccount, token, ClusterRoleBinding) whose machine, RackHostLease and Node are all gone. Each one is a long-lived credential nothing uses; non-zero in report-only mode means one is waiting for a person.",
	})
	orphanedNodeIdentitiesRevokedTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "capt_orphaned_node_identities_revoked_total",
		Help: "Orphaned node identities the node-identity sweep revoked.",
	})
)

func init() {
	metrics.Registry.MustRegister(orphanedNodeIdentitiesGauge, orphanedNodeIdentitiesRevokedTotal)
}

const (
	nodeIdentityManagedByLabel = "tuist.dev/managed-by"
	nodeIdentityManagedByValue = "capi-scaleway-applesilicon"
	nodeIdentityMachineLabel   = "tuist.dev/machine"
)

// NodeIdentityRevoker is the slice of credentials.Manager the sweep uses.
type NodeIdentityRevoker interface {
	DeleteNodeIdentity(ctx context.Context, machineName string) error
}

// NodeIdentitySweep is a leader-gated periodic sweep that revokes the
// operator-minted node identities (tart-kubelet-<machine> ServiceAccount, its
// token Secret and ClusterRoleBinding) that outlived what they were minted for.
//
// Every machine kind revokes its identity in its delete path, but that path
// only runs while the finalizer does. An identity outlives its machine when
// the machine is deleted without it: a finalizer stripped by hand, a kind
// whose CRD was removed (Scaleway Elastic Metal), or a CR that predates its
// kind's delete path. Nothing else ever deletes such a token, and on the
// Linux kinds it is bound to system:node, which reads every Secret in the
// cluster. A sweep catches every cause however it happened.
//
// An identity is orphaned only when, for its `tuist.dev/machine` name:
//   - no machine of any kind this operator mints identities for exists in the
//     namespace (ScalewayAppleSilicon, RackAppleSilicon, OVHDedicated, Vultr),
//   - no RackHostLease's Node takes that name (the borrowing side mints the
//     identity under the Node name, not a machine name),
//   - no Node of that name exists, and
//   - the ServiceAccount is older than Grace, which covers a bootstrap or
//     lease takeover that minted the identity before its Node registered.
//
// Identities without the operator's managed-by label, such as the chart's
// rack-joining-nodes ones, are never touched. Everything is re-read uncached
// before revoking. With Revoke false the sweep only reports.
type NodeIdentitySweep struct {
	Client    client.Client
	APIReader client.Reader
	Revoker   NodeIdentityRevoker

	Namespace string
	// LeaseNodeName maps a RackHostLease's name to the Node the borrower
	// registers it as. Nil when this cluster borrows nothing.
	LeaseNodeName func(leaseName string) string

	Interval time.Duration
	Grace    time.Duration
	Revoke   bool
	Log      logr.Logger

	now func() time.Time
}

func (s *NodeIdentitySweep) NeedLeaderElection() bool { return true }

func (s *NodeIdentitySweep) Start(ctx context.Context) error {
	s.Log.Info("node-identity sweep starting", "interval", s.Interval, "grace", s.Grace, "revoke", s.Revoke)
	wait.UntilWithContext(ctx, func(ctx context.Context) {
		if _, err := s.SweepOnce(ctx); err != nil {
			s.Log.Error(err, "node-identity sweep failed; retrying next interval")
		}
	}, s.Interval)
	return nil
}

// SweepOnce finds orphaned identities, revokes them when Revoke is set, and
// returns the machine names it found orphaned.
func (s *NodeIdentitySweep) SweepOnce(ctx context.Context) ([]string, error) {
	reader := s.APIReader
	if reader == nil {
		reader = s.Client
	}
	now := time.Now
	if s.now != nil {
		now = s.now
	}

	sas := &corev1.ServiceAccountList{}
	if err := reader.List(ctx, sas, client.InNamespace(s.Namespace),
		client.MatchingLabels{nodeIdentityManagedByLabel: nodeIdentityManagedByValue}); err != nil {
		return nil, fmt.Errorf("list node identities: %w", err)
	}
	live, err := s.liveNames(ctx, reader)
	if err != nil {
		return nil, err
	}

	var orphaned []string
	var firstErr error
	for i := range sas.Items {
		sa := &sas.Items[i]
		machine := sa.Labels[nodeIdentityMachineLabel]
		if machine == "" || live[machine] {
			continue
		}
		if now().Sub(sa.CreationTimestamp.Time) < s.Grace {
			continue
		}
		hasNode, err := nodeExists(ctx, reader, machine)
		if err != nil {
			return orphaned, err
		}
		if hasNode {
			continue
		}
		orphaned = append(orphaned, machine)
		if !s.Revoke {
			s.Log.Info("orphaned node identity (report-only)", "serviceAccount", sa.Name, "machine", machine)
			continue
		}
		s.Log.Info("revoking orphaned node identity", "serviceAccount", sa.Name, "machine", machine)
		if err := s.Revoker.DeleteNodeIdentity(ctx, machine); err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("revoke %s: %w", sa.Name, err)
			}
			continue
		}
		orphanedNodeIdentitiesRevokedTotal.Inc()
	}
	remaining := len(orphaned)
	if s.Revoke && firstErr == nil {
		remaining = 0
	}
	orphanedNodeIdentitiesGauge.Set(float64(remaining))
	return orphaned, firstErr
}

// liveNames is every name an identity may legitimately be minted under.
func (s *NodeIdentitySweep) liveNames(ctx context.Context, reader client.Reader) (map[string]bool, error) {
	live := map[string]bool{}
	ns := client.InNamespace(s.Namespace)
	lists := []client.ObjectList{
		&infrav1.ScalewayAppleSiliconMachineList{},
		&infrav1.RackAppleSiliconMachineList{},
		&infrav1.OVHDedicatedMachineList{},
		&infrav1.VultrMachineList{},
	}
	for _, list := range lists {
		if err := reader.List(ctx, list, ns); err != nil {
			// A kind not installed in this cluster has no machines; any
			// other failure means the live set is unknown, so revoke nothing.
			if apierrors.IsNotFound(err) || meta.IsNoMatchError(err) {
				continue
			}
			return nil, fmt.Errorf("list %T: %w", list, err)
		}
		items, err := meta.ExtractList(list)
		if err != nil {
			return nil, err
		}
		for _, item := range items {
			if o, ok := item.(client.Object); ok {
				live[o.GetName()] = true
			}
		}
	}
	if s.LeaseNodeName != nil {
		leases := &infrav1.RackHostLeaseList{}
		if err := reader.List(ctx, leases, ns); err != nil && !apierrors.IsNotFound(err) && !meta.IsNoMatchError(err) {
			return nil, fmt.Errorf("list RackHostLeases: %w", err)
		}
		for _, l := range leases.Items {
			live[s.LeaseNodeName(l.Name)] = true
		}
	}
	return live, nil
}

func nodeExists(ctx context.Context, reader client.Reader, name string) (bool, error) {
	err := reader.Get(ctx, client.ObjectKey{Name: name}, &corev1.Node{})
	if apierrors.IsNotFound(err) {
		return false, nil
	}
	return err == nil, err
}
