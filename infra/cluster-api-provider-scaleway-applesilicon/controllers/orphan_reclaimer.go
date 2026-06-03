package controllers

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus"
	"k8s.io/apimachinery/pkg/util/wait"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
)

var (
	orphanServersGauge = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "scaleway_orphan_servers",
		Help: "Scaleway Apple Silicon servers that carry a claimed (non-pool) name but are backed by no live ScalewayAppleSiliconMachine CR. A sustained non-zero value means hosts are leaking out of the adopt pool — billing under Apple's 24h floor while doing no work, and draining the pool that AdoptFromPool draws from.",
	})
	orphansReclaimedTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "scaleway_orphan_servers_reclaimed_total",
		Help: "Stranded Scaleway Apple Silicon servers returned to the adopt pool (rename + reinstall) by the orphan-reclaim sweep.",
	})
)

func init() {
	metrics.Registry.MustRegister(orphanServersGauge, orphansReclaimedTotal)
}

// scalewayPool is the slice of *scaleway.Client the orphan-reclaim
// sweep needs. An interface so tests can drive the sweep without the
// real Scaleway SDK.
type scalewayPool interface {
	ListServers(ctx context.Context, zone string) ([]scaleway.Server, error)
	ReleaseToPool(ctx context.Context, id, zone, poolPrefix string) error
}

// OrphanReclaimer is a leader-gated periodic sweep that returns
// Scaleway Apple Silicon hosts which were once claimed by this
// controller but whose owning ScalewayAppleSiliconMachine CR is gone
// back to the adopt pool.
//
// Why a sweep and not the per-Machine delete path alone: reconcileDelete
// releases a host on normal teardown, but a host strands whenever that
// path doesn't run to completion — a legacy CR with no AdoptPoolPrefix
// (and no controller default) that skips release, a force-delete that
// bypasses the finalizer, or a crash between claiming a pool host and
// writing its CR. Stranded hosts keep billing under Apple's 24h floor
// and silently drain the pool, which is what surfaces later as
// AdoptFromPool returning NoAvailableHost and wedging a deploy. The
// per-Machine path can't cover what never reaches it; a convergent
// sweep catches every strand cause regardless of how it happened.
//
// Safety. A host is left untouched when it is parked in the pool,
// mid-adoption, or named after a live CR. The claim renames a pool host
// to its CR's name, and the CR always exists before that rename, so a
// live CR name is the authoritative "owned" signal and there is no
// claimed-but-CR-missing window short of an actual delete. Active
// reclaim is gated further on ClaimNamePrefix: a host an operator is
// mid-provisioning under a Scaleway-default name, or a host belonging to
// another cluster that shares the Scaleway project, fails the prefix
// check and is reported via the gauge but never mutated. With
// ClaimNamePrefix empty the sweep is report-only.
type OrphanReclaimer struct {
	client.Client

	Scaleway scalewayPool

	// Interval between sweeps.
	Interval time.Duration

	// Zones swept every cycle, unioned with the distinct zones of all
	// live CRs. The static list keeps a zone covered even after its
	// last CR is deleted (the case where a strand is most likely and
	// least visible).
	Zones []string

	// PoolPrefix marks available pool hosts (skipped) and is the
	// rename target when a stranded host is reclaimed.
	PoolPrefix string

	// ClaimNamePrefix gates active reclaim. Only hosts whose Scaleway
	// name starts with this prefix — this cluster's claimed-name
	// namespace within the Scaleway project — are reclaimed. Empty
	// makes the sweep report-only.
	ClaimNamePrefix string

	Log logr.Logger
}

// NeedLeaderElection keeps the sweep on the single elected leader; a
// second replica must not race ReleaseToPool against the leader.
func (r *OrphanReclaimer) NeedLeaderElection() bool { return true }

// Start runs the sweep immediately and then every Interval until the
// manager's context is cancelled. A failed cycle is logged and retried
// next interval rather than crashing the manager.
func (r *OrphanReclaimer) Start(ctx context.Context) error {
	r.Log.Info("orphan-reclaim sweep starting",
		"interval", r.Interval, "zones", r.Zones,
		"poolPrefix", r.PoolPrefix, "mode", r.mode())
	wait.UntilWithContext(ctx, func(ctx context.Context) {
		if err := r.reclaimOnce(ctx); err != nil {
			r.Log.Error(err, "orphan-reclaim sweep cycle failed; retrying next interval")
		}
	}, r.Interval)
	return nil
}

func (r *OrphanReclaimer) mode() string {
	if r.ClaimNamePrefix == "" {
		return "report-only"
	}
	return "reclaim"
}

// reclaimOnce performs a single sweep: build the owned set from live
// CRs, list Scaleway hosts per zone, and reclaim (or report) every
// stranded host. Returns the first error encountered so Start can log
// it; partial progress within the cycle is kept.
func (r *OrphanReclaimer) reclaimOnce(ctx context.Context) error {
	machines := &infrav1.ScalewayAppleSiliconMachineList{}
	if err := r.List(ctx, machines); err != nil {
		return fmt.Errorf("list ScalewayAppleSiliconMachines: %w", err)
	}

	ownedNames := make(map[string]struct{}, len(machines.Items))
	ownedServerIDs := make(map[string]struct{}, len(machines.Items))
	zoneSet := make(map[string]struct{}, len(r.Zones))
	for _, z := range r.Zones {
		if z != "" {
			zoneSet[z] = struct{}{}
		}
	}
	for i := range machines.Items {
		m := &machines.Items[i]
		ownedNames[m.Name] = struct{}{}
		if m.Status.ServerID != "" {
			ownedServerIDs[m.Status.ServerID] = struct{}{}
		}
		if m.Spec.Zone != "" {
			zoneSet[m.Spec.Zone] = struct{}{}
		}
	}

	var (
		orphanCount int
		firstErr    error
	)
	for zone := range zoneSet {
		servers, err := r.Scaleway.ListServers(ctx, zone)
		if err != nil {
			r.Log.Error(err, "list Scaleway servers; skipping zone this cycle", "zone", zone)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		for _, s := range servers {
			if scaleway.IsPoolOrAdopting(s.Name, r.PoolPrefix) {
				continue
			}
			if _, ok := ownedNames[s.Name]; ok {
				continue
			}
			if _, ok := ownedServerIDs[s.ID]; ok {
				continue
			}

			// Stranded: a claimed-style name with no owning CR.
			orphanCount++

			if r.ClaimNamePrefix == "" || !strings.HasPrefix(s.Name, r.ClaimNamePrefix) {
				r.Log.Info("stranded Scaleway host detected (report-only)",
					"server", s.ID, "name", s.Name, "zone", zone,
					"claimNamePrefix", r.ClaimNamePrefix)
				continue
			}

			r.Log.Info("reclaiming stranded Scaleway host to pool",
				"server", s.ID, "name", s.Name, "zone", zone)
			if err := r.Scaleway.ReleaseToPool(ctx, s.ID, zone, r.PoolPrefix); err != nil {
				r.Log.Error(err, "reclaim stranded host failed; retrying next cycle",
					"server", s.ID, "name", s.Name, "zone", zone)
				if firstErr == nil {
					firstErr = err
				}
				continue
			}
			orphansReclaimedTotal.Inc()
		}
	}

	orphanServersGauge.Set(float64(orphanCount))
	return firstErr
}
