package podagent

import (
	"context"
	"reflect"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

const (
	rackFleet   = "tuist-tuist-rack-fleet"
	img266Next  = "ghcr.io/tuist/tuist-runner@sha256:266next"
	img270Next  = "ghcr.io/tuist/tuist-runner@sha256:270next"
	stackedNext = "ghcr.io/tuist/tuist-runner@sha256:266stackednext"
)

// catalogPool is a RunnerPool that follows the catalog's image for xcode, as
// the chart renders it.
func catalogPool(name, image, xcode, variant string, replicas, floor int64) unstructured.Unstructured {
	pool := runnerPool(name, image, rackFleet, replicas, floor)
	pool.SetLabels(map[string]string{xcodeVersionLabel: xcode, runnerImageVariantLabel: variant})
	return pool
}

func heldGoldensOf(images ...string) map[string]struct{} {
	held := map[string]struct{}{}
	for _, image := range images {
		held[goldenVMName(image)] = struct{}{}
	}
	return held
}

func stagingPrewarmer(pools *poolLister, goldens *recordingGoldens) *Prewarmer {
	return &Prewarmer{K8s: pools, Goldens: goldens, Fleet: rackFleet, DiskFree: plentyOfDisk}
}

// On 2026-10-21 ber1-runner-b04 and b08 pulled a new runner image from
// ghcr.io for 532 s and 562 s while its first Pod waited. A release names its
// images before a deploy moves the pools to them, so a host that serves a
// pool pulls the pool's next image while it still runs the current one, and
// leaves alone the pools it does not serve.
func TestStagePullsTheNextImageOfThePoolsTheHostServes(t *testing.T) {
	pools := &poolLister{
		pools: []unstructured.Unstructured{
			catalogPool("macos-ber1-26-6-6vcpu", img266, "26.6", "stacked", 1, 1),
			catalogPool("macos-ber1-26-6-12vcpu", img266, "26.6", "stacked", 0, 0),
			catalogPool("macos-ber1-27-0-6vcpu", img270, "27.0", "stacked", 3, 0),
		},
		upcoming: map[string]string{
			"26.6.stacked":    stackedNext,
			"26.6.standalone": img266Next,
			"27.0.stacked":    img270Next,
		},
	}
	goldens := &recordingGoldens{held: heldGoldensOf(img266)}

	stagingPrewarmer(pools, goldens).stage(context.Background())

	if want := []string{stackedNext}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("staged %v, want %v: only the next image of the variant the served pools run", goldens.pulled, want)
	}
}

// After a deploy moves a pool, following it to the new image is the GC's
// (follow.go): staging pulls only what a pool moves to next.
func TestStageLeavesAPoolTheDeployAlreadyMoved(t *testing.T) {
	pools := &poolLister{
		pools:    []unstructured.Unstructured{catalogPool("macos-ber1-26-6-6vcpu", stackedNext, "26.6", "stacked", 0, 0)},
		upcoming: map[string]string{"26.6.stacked": stackedNext},
	}
	goldens := &recordingGoldens{held: heldGoldensOf(img266)}

	stagingPrewarmer(pools, goldens).stage(context.Background())

	if len(goldens.pulled) != 0 {
		t.Fatalf("staged %v for a pool already on its next image", goldens.pulled)
	}
}

// The host runs one golden pull at a time, and a Pod's pull is for a job
// that is waiting. Staging starts none while a Pod waits on one.
func TestStageYieldsToAPodsGoldenPull(t *testing.T) {
	pools := &poolLister{
		pools:    []unstructured.Unstructured{catalogPool("macos-ber1-26-6-6vcpu", img266, "26.6", "stacked", 0, 0)},
		upcoming: map[string]string{"26.6.stacked": stackedNext},
	}
	goldens := &recordingGoldens{held: heldGoldensOf(img266), awaiting: true}

	stagingPrewarmer(pools, goldens).stage(context.Background())

	if len(goldens.pulled) != 0 {
		t.Fatalf("staged %v while a Pod waited on a pull", goldens.pulled)
	}
}

func TestStageStopsAtTheDiskFloor(t *testing.T) {
	pools := &poolLister{
		pools: []unstructured.Unstructured{
			catalogPool("macos-ber1-26-6-6vcpu", img266, "26.6", "stacked", 0, 0),
			catalogPool("macos-ber1-27-0-6vcpu", img270, "27.0", "stacked", 0, 0),
		},
		upcoming: map[string]string{"26.6.stacked": stackedNext, "27.0.stacked": img270Next},
	}
	free := 80.0
	goldens := &recordingGoldens{held: heldGoldensOf(img266, img270), onPull: func() { free = prewarmMinFreePercent - 1 }}
	p := stagingPrewarmer(pools, goldens)
	p.DiskFree = func() (float64, error) { return free, nil }

	p.stage(context.Background())

	if len(goldens.pulled) != 1 {
		t.Fatalf("staged %v, want one image before the disk floor", goldens.pulled)
	}
}

// A pool that pins its own image, or an entry naming another repository, is
// not staged.
func TestUpcomingImagesApplyOnlyToCatalogPoolsInTheirRepository(t *testing.T) {
	upcoming := upcomingImages{
		"26.6.stacked":    stackedNext,
		"27.0.standalone": "registry.example.com/other@sha256:270",
	}
	pools, err := listRunnerPools(context.Background(), &poolLister{pools: []unstructured.Unstructured{
		catalogPool("follows", img266, "26.6", "stacked", 0, 0),
		runnerPool("pinned", img266, rackFleet, 0, 0),
		catalogPool("elsewhere", img270, "27.0", "standalone", 0, 0),
		catalogPool("current", stackedNext, "26.6", "stacked", 0, 0),
	}})
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, pool := range pools {
		got[pool.Metadata.Name] = upcoming.forPool(pool)
	}
	want := map[string]string{"follows": stackedNext, "pinned": "", "elsewhere": "", "current": ""}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("next images = %v, want %v", got, want)
	}
}
