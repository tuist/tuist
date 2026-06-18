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

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/scaleway"
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

	// APIReader is an uncached reader used to re-check ownership in the
	// instant before a host is reclaimed. The cached Client can lag a
	// just-created CR, and reclaim is destructive, so the final check
	// reads straight from the API server. Falls back to the cached
	// Client when nil (tests).
	APIReader client.Reader

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

// reclaimOnce performs a single sweep: snapshot the owned set from live
// CRs, list Scaleway hosts per zone, then reclaim (or report) every
// stranded host. Returns the first error encountered so Start can log
// it; partial progress within the cycle is kept.
func (r *OrphanReclaimer) reclaimOnce(ctx context.Context) error {
	owned, zones, err := r.ownedSnapshot(ctx, r.Client)
	if err != nil {
		return err
	}

	type strand struct{ id, name, zone string }
	var (
		candidates  []strand
		orphanCount int
		firstErr    error
	)
	for zone := range zones {
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
			if owned.has(s.Name, s.ID) {
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
			candidates = append(candidates, strand{id: s.ID, name: s.Name, zone: zone})
		}
	}
	orphanServersGauge.Set(float64(orphanCount))

	if len(candidates) == 0 {
		return firstErr
	}

	// Re-check ownership against the live API right before mutating. The
	// snapshot above was taken before the per-zone Scaleway scans (and
	// off a possibly cache-lagged client); a CR created and adopted in
	// the meantime now owns its host under the CR's name (the claim
	// renames the pool host to it), so releasing from the stale snapshot
	// would wipe a live, freshly-adopted host. A failed re-check aborts
	// reclaim this cycle rather than act on stale data.
	fresh, _, err := r.ownedSnapshot(ctx, r.reader())
	if err != nil {
		return fmt.Errorf("re-check ownership before reclaim: %w", err)
	}
	for _, c := range candidates {
		if fresh.has(c.name, c.id) {
			r.Log.Info("skipping reclaim; host adopted since scan",
				"server", c.id, "name", c.name, "zone", c.zone)
			continue
		}
		r.Log.Info("reclaiming stranded Scaleway host to pool",
			"server", c.id, "name", c.name, "zone", c.zone)
		if err := r.Scaleway.ReleaseToPool(ctx, c.id, c.zone, r.PoolPrefix); err != nil {
			r.Log.Error(err, "reclaim stranded host failed; retrying next cycle",
				"server", c.id, "name", c.name, "zone", c.zone)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		orphansReclaimedTotal.Inc()
	}
	return firstErr
}

func (r *OrphanReclaimer) reader() client.Reader {
	if r.APIReader != nil {
		return r.APIReader
	}
	return r.Client
}

// ownership is the set of host names and serverIDs claimed by live CRs.
type ownership struct {
	names map[string]struct{}
	ids   map[string]struct{}
}

func (o ownership) has(name, id string) bool {
	if _, ok := o.names[name]; ok {
		return true
	}
	if id != "" {
		if _, ok := o.ids[id]; ok {
			return true
		}
	}
	return false
}

// ownedSnapshot lists the live ScalewayAppleSiliconMachine CRs through
// reader and returns the owned host names + serverIDs, plus the zones to
// sweep (the configured Zones unioned with every CR's zone, so a zone
// stays covered after its last CR is deleted).
func (r *OrphanReclaimer) ownedSnapshot(ctx context.Context, reader client.Reader) (ownership, map[string]struct{}, error) {
	machines := &infrav1.ScalewayAppleSiliconMachineList{}
	if err := reader.List(ctx, machines); err != nil {
		return ownership{}, nil, fmt.Errorf("list ScalewayAppleSiliconMachines: %w", err)
	}
	owned := ownership{
		names: make(map[string]struct{}, len(machines.Items)),
		ids:   make(map[string]struct{}, len(machines.Items)),
	}
	zones := make(map[string]struct{}, len(r.Zones))
	for _, z := range r.Zones {
		if z != "" {
			zones[z] = struct{}{}
		}
	}
	for i := range machines.Items {
		m := &machines.Items[i]
		owned.names[m.Name] = struct{}{}
		if m.Status.ServerID != "" {
			owned.ids[m.Status.ServerID] = struct{}{}
		}
		if m.Spec.Zone != "" {
			zones[m.Spec.Zone] = struct{}{}
		}
	}
	return owned, zones, nil
}
