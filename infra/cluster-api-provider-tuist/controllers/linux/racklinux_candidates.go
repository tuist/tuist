package linux

import (
	"context"
	"time"

	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	rackCandidateTidyInterval = time.Minute
	rackCandidateLifetime     = 7 * 24 * time.Hour
)

// RackLinuxCandidates keeps tidy the RackLinuxCandidates a rack's boot
// servers list from install sticks' announcements (internal/rackboot), so a
// person declares a machine from `kubectl get rlc` instead of reading its MAC
// off its label. Once a minute it marks each with the hostname of the
// RackLinuxHost named after its UUID, and drops an undeclared one no boot
// server has heard from for a week. A declared one stays: it is what the
// machine said about itself, which its host reads its boot MAC and model from.
type RackLinuxCandidates struct {
	client.Client

	// Now is overridden in tests.
	Now func() time.Time
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxcandidates,verbs=get;list;watch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racklinuxcandidates/status,verbs=get;update;patch

// Start keeps the candidates tidy until the manager stops.
func (d *RackLinuxCandidates) Start(ctx context.Context) error {
	logger := ctrl.Log.WithName("racklinux-candidates")
	ticker := time.NewTicker(rackCandidateTidyInterval)
	defer ticker.Stop()
	for {
		if err := d.tidy(ctx); err != nil {
			logger.Error(err, "tidy the machines rack boot servers heard from")
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

// NeedLeaderElection keeps the tidying to one replica.
func (d *RackLinuxCandidates) NeedLeaderElection() bool { return true }

func (d *RackLinuxCandidates) now() time.Time {
	if d.Now != nil {
		return d.Now()
	}
	return time.Now()
}

func (d *RackLinuxCandidates) tidy(ctx context.Context) error {
	hosts := &infrav1.RackLinuxHostList{}
	if err := d.List(ctx, hosts); err != nil {
		return err
	}
	cands := &infrav1.RackLinuxCandidateList{}
	if err := d.List(ctx, cands); err != nil {
		return err
	}
	for i := range cands.Items {
		cand := &cands.Items[i]
		declared := declaringHost(hosts.Items, cand)
		if declared == "" && cand.Status.LastSeen != nil && d.now().Sub(cand.Status.LastSeen.Time) > rackCandidateLifetime {
			if err := d.Delete(ctx, cand); client.IgnoreNotFound(err) != nil {
				return err
			}
			continue
		}
		if declared == cand.Status.DeclaredAs {
			continue
		}
		orig := cand.DeepCopy()
		cand.Status.DeclaredAs = declared
		if err := d.Status().Patch(ctx, cand, client.MergeFrom(orig)); err != nil {
			return err
		}
	}
	return nil
}

// declaringHost is the hostname of the host named after the candidate's UUID.
func declaringHost(hosts []infrav1.RackLinuxHost, cand *infrav1.RackLinuxCandidate) string {
	for i := range hosts {
		h := &hosts[i]
		if h.Namespace == cand.Namespace && h.Name == cand.Name && h.DeletionTimestamp.IsZero() {
			return h.Spec.Hostname
		}
	}
	return ""
}
