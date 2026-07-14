package macos

import (
	"context"
	"testing"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus/testutil"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/scaleway"
)

// fakePool is a stand-in for *scaleway.Client driving the sweep: it
// serves a fixed per-zone server list and records every ReleaseToPool.
type fakePool struct {
	byZone      map[string][]scaleway.Server
	releasedIDs []string
	releaseErr  map[string]error
}

func (f *fakePool) ListServers(_ context.Context, zone string) ([]scaleway.Server, error) {
	return f.byZone[zone], nil
}

func (f *fakePool) ReleaseToPool(_ context.Context, id, _, _ string) error {
	if err := f.releaseErr[id]; err != nil {
		return err
	}
	f.releasedIDs = append(f.releasedIDs, id)
	return nil
}

func machineCR(name, zone, serverID string) *infrav1.ScalewayAppleSiliconMachine {
	return &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist"},
		Spec:       infrav1.ScalewayAppleSiliconMachineSpec{Zone: zone, AdoptPoolPrefix: "tuist-pool-"},
		Status:     infrav1.ScalewayAppleSiliconMachineStatus{ServerID: serverID},
	}
}

func buildCRClient(t *testing.T, crs ...*infrav1.ScalewayAppleSiliconMachine) client.Client {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("infrav1 scheme: %v", err)
	}
	objs := make([]runtime.Object, 0, len(crs))
	for _, c := range crs {
		objs = append(objs, c)
	}
	return fake.NewClientBuilder().WithScheme(scheme).WithRuntimeObjects(objs...).Build()
}

func newReclaimerTest(t *testing.T, pool scalewayPool, claimPrefix string, crs ...*infrav1.ScalewayAppleSiliconMachine) *OrphanReclaimer {
	t.Helper()
	return &OrphanReclaimer{
		Client:          buildCRClient(t, crs...),
		Scaleway:        pool,
		Zones:           []string{"fr-par-1"},
		PoolPrefix:      "tuist-pool-",
		ClaimNamePrefix: claimPrefix,
		Log:             logr.Discard(),
	}
}

// The sweep must reclaim exactly the host that is (a) not in the pool,
// (b) not mid-adoption, (c) owned by no live CR, and (d) inside this
// cluster's claim-name namespace — and nothing else. The serverID and
// claim-name-prefix guards are the load-bearing safety checks: a
// freshly-claimed-but-status-only host (owned by serverID) and a host
// outside our claim namespace (operator-in-progress or another
// cluster) must survive.
func TestOrphanReclaimer_ReclaimsOnlyStrandedHostsInClaimNamespace(t *testing.T) {
	pool := &fakePool{byZone: map[string][]scaleway.Server{
		"fr-par-1": {
			{ID: "pool-1", Name: "tuist-pool-aaaa"},                           // available in pool
			{ID: "pend-1", Name: "tuist-claim-pending-bbbb"},                  // mid-adoption
			{ID: "live-name", Name: "tuist-tuist-builders-fleet-rg4h9-xqzbl"}, // owned: matches a live CR name
			{ID: "live-id", Name: "tuist-tuist-orphan-lookalike"},             // owned: matches a live CR serverID
			{ID: "stray-1", Name: "tuist-tuist-builders-fleet-rg4h9-c295c"},   // STRANDED, in claim namespace
			{ID: "foreign", Name: "apple-silicon-romantic-proskuriakova"},     // stranded but outside claim namespace
		},
	}}

	r := newReclaimerTest(t, pool, "tuist-tuist-",
		machineCR("tuist-tuist-builders-fleet-rg4h9-xqzbl", "fr-par-1", ""),
		machineCR("a-differently-named-cr", "fr-par-1", "live-id"),
	)

	if err := r.reclaimOnce(context.Background()); err != nil {
		t.Fatalf("reclaimOnce: %v", err)
	}

	if len(pool.releasedIDs) != 1 || pool.releasedIDs[0] != "stray-1" {
		t.Fatalf("expected only stray-1 reclaimed, got %v", pool.releasedIDs)
	}
}

// With no claim-name prefix the sweep is report-only: it counts every
// stranded host on the gauge but mutates nothing.
func TestOrphanReclaimer_ReportOnlyDoesNotMutate(t *testing.T) {
	pool := &fakePool{byZone: map[string][]scaleway.Server{
		"fr-par-1": {
			{ID: "pool-1", Name: "tuist-pool-aaaa"},
			{ID: "stray-1", Name: "tuist-tuist-builders-fleet-rg4h9-c295c"},
			{ID: "foreign", Name: "apple-silicon-romantic-proskuriakova"},
		},
	}}

	r := newReclaimerTest(t, pool, "")

	if err := r.reclaimOnce(context.Background()); err != nil {
		t.Fatalf("reclaimOnce: %v", err)
	}

	if len(pool.releasedIDs) != 0 {
		t.Fatalf("report-only mode must not reclaim, got %v", pool.releasedIDs)
	}
	// stray-1 + foreign are both stranded (only pool-1 is excused), so
	// the gauge reports 2 regardless of the claim-name gate.
	if got := testutil.ToFloat64(orphanServersGauge); got != 2 {
		t.Fatalf("expected gauge=2 stranded hosts, got %v", got)
	}
}

// A CR created and adopted after the cycle's initial snapshot must not
// be reclaimed. The detection snapshot (Client) predates the CR, so the
// host is flagged, but the pre-mutation re-check reads the live API
// (APIReader) and sees the new owner by name, so the release is skipped.
func TestOrphanReclaimer_SkipsHostAdoptedSinceScan(t *testing.T) {
	pool := &fakePool{byZone: map[string][]scaleway.Server{
		"fr-par-1": {{ID: "stray-1", Name: "tuist-tuist-builders-fleet-rg4h9-c295c"}},
	}}
	// Detection client has no CRs, so stray-1 is flagged as a candidate.
	r := newReclaimerTest(t, pool, "tuist-tuist-")
	// The live re-check reader sees a CR that now owns the host by name.
	r.APIReader = buildCRClient(t, machineCR("tuist-tuist-builders-fleet-rg4h9-c295c", "fr-par-1", ""))

	if err := r.reclaimOnce(context.Background()); err != nil {
		t.Fatalf("reclaimOnce: %v", err)
	}
	if len(pool.releasedIDs) != 0 {
		t.Fatalf("must not reclaim a host adopted since the scan, got %v", pool.releasedIDs)
	}
}
