package podagent

import (
	"context"
	"reflect"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

const (
	img261Pool = "ghcr.io/tuist/tuist-runner@sha256:261"
	img264     = "ghcr.io/tuist/tuist-runner@sha256:264"
	img271     = "ghcr.io/tuist/tuist-runner@sha256:271"
	imgSmoke   = "ghcr.io/tuist/tuist-runner@sha256:smoke"
)

var budgetNow = time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC)

// withDemand stamps the pool's status.lastDemandAt as the runners-controller
// does.
func withDemand(pool unstructured.Unstructured, at time.Time) unstructured.Unstructured {
	_ = unstructured.SetNestedField(pool.Object, at.UTC().Format(time.RFC3339), "status", "lastDemandAt")
	return pool
}

func rankedNext(t *testing.T, pools []unstructured.Unstructured, upcoming upcomingImages, held map[string]struct{}) []string {
	t.Helper()
	specs, err := listRunnerPools(context.Background(), &poolLister{pools: pools})
	if err != nil {
		t.Fatal(err)
	}
	var next []string
	for _, line := range rankImageLines(specs, upcoming, rackFleet, held, budgetNow) {
		next = append(next, line.next)
	}
	return next
}

// Warm floors rank first, then the images whose pools had work most
// recently by the day, then those the host holds. A pool that pins its own
// image, such as the smoke pool, is outside the ranking.
func TestRankImageLines(t *testing.T) {
	pools := []unstructured.Unstructured{
		catalogPool("macos-ber1-26-4-1", img264, "26.4.1", "stacked", 0, 0),
		withDemand(catalogPool("macos-ber1-26-1-1", img261Pool, "26.1.1", "stacked", 0, 0), budgetNow.Add(-3*24*time.Hour)),
		withDemand(catalogPool("macos-ber1-27-1", img271, "27.1", "stacked", 0, 0), budgetNow.Add(-2*time.Hour)),
		withDemand(catalogPool("macos-ber1-27-0", img270, "27.0", "stacked", 0, 0), budgetNow.Add(-20*time.Hour)),
		catalogPool("macos-ber1-26-6", img266, "26.6", "stacked", 1, 1),
		withDemand(runnerPool("ber1", imgSmoke, rackFleet, 1, 0), budgetNow),
	}

	got := rankedNext(t, pools, nil, heldGoldensOf(img270))

	want := []string{img266, img270, img271, img261Pool, img264}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ranking = %v, want %v: floor, then demand by the day with held images first, then no demand", got, want)
	}
}

// The 6 and 12 vCPU pools of an Xcode run one image: they rank as one line,
// with the most recent demand of either, and a pool moving to a release ranks
// by the image it moves to.
func TestRankImageLinesGroupsPoolsByTheImageTheyRunNext(t *testing.T) {
	pools := []unstructured.Unstructured{
		catalogPool("macos-ber1-27-1", img271, "27.1", "stacked", 0, 0),
		withDemand(catalogPool("macos-ber1-27-1-12vcpu", img271, "27.1", "stacked", 0, 0), budgetNow.Add(-time.Hour)),
		catalogPool("macos-ber1-26-6", img266, "26.6", "stacked", 0, 0),
	}

	specs, err := listRunnerPools(context.Background(), &poolLister{pools: pools})
	if err != nil {
		t.Fatal(err)
	}
	lines := rankImageLines(specs, upcomingImages{"26.6.stacked": stackedNext}, rackFleet, nil, budgetNow)
	if len(lines) != 2 || lines[0].next != img271 || !lines[0].lastDemand.Equal(budgetNow.Add(-time.Hour)) {
		t.Fatalf("lines = %+v, want 27.1 first with its 12 vCPU pool's demand", lines)
	}
	if got, want := lines[1].images, []string{stackedNext, img266}; lines[1].next != stackedNext || !reflect.DeepEqual(got, want) {
		t.Fatalf("26.6 line = %+v, want it ranked by its next image and keeping its current one", lines[1])
	}
}

// From 2026-10-24 to 10-28 every BER1 rack runner Pod Pending for over a
// minute with most guest slots free waited 3 to 29 minutes on a pull, on a
// host without its pool's image. With a budget, a host stages the images of
// the top of the ranking it lacks, whether or not it holds their current
// image, and nothing beyond the budget or outside the catalog.
func TestStageFillsTheBudgetWithTheTopOfTheRanking(t *testing.T) {
	pools := &poolLister{
		pools: []unstructured.Unstructured{
			catalogPool("macos-ber1-26-6", img266, "26.6", "stacked", 1, 1),
			withDemand(catalogPool("macos-ber1-27-1", img271, "27.1", "stacked", 0, 0), budgetNow.Add(-time.Hour)),
			withDemand(catalogPool("macos-ber1-27-0", img270, "27.0", "stacked", 0, 0), budgetNow.Add(-2*time.Hour)),
			catalogPool("macos-ber1-26-4-1", img264, "26.4.1", "stacked", 0, 0),
			withDemand(runnerPool("ber1", imgSmoke, rackFleet, 1, 0), budgetNow),
		},
		upcoming: map[string]string{"27.0.stacked": img270Next},
		budgets:  map[string]string{rackFleet: "3"},
	}
	goldens := &recordingGoldens{held: heldGoldensOf(img266)}
	p := stagingPrewarmer(pools, goldens)
	p.Now = func() time.Time { return budgetNow }

	p.stage(context.Background())

	if want := []string{img270Next, img271}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("staged %v, want %v: the images the top three lines run next that the host lacks, same-day demand by name", goldens.pulled, want)
	}
}

// A fleet without a budget keeps staging only the releases of the images its
// hosts hold.
func TestStageWithoutABudgetStagesOnlyReleasesOfHeldImages(t *testing.T) {
	pools := &poolLister{
		pools: []unstructured.Unstructured{
			catalogPool("macos-ber1-26-6", img266, "26.6", "stacked", 1, 1),
			withDemand(catalogPool("macos-ber1-27-1", img271, "27.1", "stacked", 0, 0), budgetNow),
		},
		upcoming: map[string]string{"26.6.stacked": stackedNext},
		budgets:  map[string]string{"tuist-tuist-builders-fleet": "3"},
	}
	goldens := &recordingGoldens{held: heldGoldensOf(img266)}

	stagingPrewarmer(pools, goldens).stage(context.Background())

	if want := []string{stackedNext}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("staged %v, want %v", goldens.pulled, want)
	}
}

// The GC keeps what the budget keeps, reaps the catalog goldens beyond it
// with their cached images unless a Pod here runs them, and lets a release of
// an image beyond the budget go instead of following it.
func TestApplyBudget(t *testing.T) {
	pools, err := listRunnerPools(context.Background(), &poolLister{pools: []unstructured.Unstructured{
		catalogPool("macos-ber1-26-6", img266, "26.6", "stacked", 1, 1),
		withDemand(catalogPool("macos-ber1-27-1", img271, "27.1", "stacked", 0, 0), budgetNow.Add(-time.Hour)),
		catalogPool("macos-ber1-26-4-1", img264, "26.4.1", "stacked", 0, 0),
		catalogPool("macos-ber1-27-0", img270, "27.0", "stacked", 0, 0),
	}})
	if err != nil {
		t.Fatal(err)
	}
	e := &expectedSet{
		vms:    map[string]struct{}{goldenVMName(img270): {}},
		budget: &budgetPlan{pools: pools, budget: 2},
		successions: map[string]succession{
			goldenVMName("ghcr.io/tuist/tuist-runner@sha256:266prev"): {current: img266},
			goldenVMName("ghcr.io/tuist/tuist-runner@sha256:264prev"): {current: img264},
		},
	}
	c := &Collector{Fleet: rackFleet}

	c.applyBudget(e, nil, budgetNow)

	if want := map[string]struct{}{goldenVMName(img266): {}, goldenVMName(img271): {}}; !reflect.DeepEqual(e.kept, want) {
		t.Fatalf("kept = %v, want 26.6 and 27.1", e.kept)
	}
	if want := map[string]struct{}{goldenVMName(img264): {}}; !reflect.DeepEqual(e.overBudget, want) {
		t.Fatalf("overBudget = %v, want 26.4.1 only: 27.0 runs a Pod here", e.overBudget)
	}
	if want := map[string]struct{}{img264: {}}; !reflect.DeepEqual(e.overBudgetRefs, want) {
		t.Fatalf("overBudgetRefs = %v, want %v", e.overBudgetRefs, want)
	}
	if _, followed := e.successions[goldenVMName("ghcr.io/tuist/tuist-runner@sha256:264prev")]; followed || len(e.successions) != 1 {
		t.Fatalf("successions = %v, want only the release of a kept image followed", e.successions)
	}
}
