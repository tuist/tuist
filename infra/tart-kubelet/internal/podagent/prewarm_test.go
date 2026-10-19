package podagent

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	img266 = "ghcr.io/tuist/tuist-runner@sha256:266"
	img270 = "ghcr.io/tuist/tuist-runner@sha256:270"
	img261 = "ghcr.io/tuist/tuist-runner@sha256:261"
)

func runnerPool(name, image, fleet string, replicas, floor int64) unstructured.Unstructured {
	spec := map[string]any{
		"image":         image,
		"os":            "darwin",
		"fleetSelector": fleet,
		"replicas":      replicas,
	}
	if floor >= 0 {
		spec["autoscaling"] = map[string]any{"enabled": true, "minWarmPoolFloor": floor, "maxReplicas": int64(18)}
	}
	u := unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "tuist.dev/v1alpha1",
		"kind":       "RunnerPool",
		"spec":       spec,
	}}
	u.SetName(name)
	return u
}

type poolLister struct {
	pools []unstructured.Unstructured
	err   error
}

func (l *poolLister) Get(context.Context, client.ObjectKey, client.Object, ...client.GetOption) error {
	return errors.New("unexpected Get")
}

func (l *poolLister) List(_ context.Context, list client.ObjectList, _ ...client.ListOption) error {
	if l.err != nil {
		return l.err
	}
	ul, ok := list.(*unstructured.UnstructuredList)
	if !ok {
		return errors.New("prewarmer must list RunnerPools as unstructured")
	}
	if gvk := ul.GroupVersionKind(); gvk != runnerPoolListGVK {
		return errors.New("unexpected kind " + gvk.String())
	}
	ul.Items = append(ul.Items, l.pools...)
	return nil
}

type recordingGoldens struct {
	pulled []string
	err    map[string]error
	// onPull runs after each pull, standing in for the disk it consumes.
	onPull func()
}

func (g *recordingGoldens) ensureGolden(_ context.Context, image string) (string, bool, error) {
	g.pulled = append(g.pulled, image)
	if g.onPull != nil {
		g.onPull()
	}
	if err := g.err[image]; err != nil {
		return "", false, err
	}
	return goldenVMName(image), true, nil
}

type fakeGate struct {
	held     bool
	err      error
	released bool
}

func (g *fakeGate) Wait(context.Context) (bool, error) { return g.held, g.err }
func (g *fakeGate) Release()                           { g.released = true }

func plentyOfDisk() (float64, error) { return 80, nil }

// The rack catalog on 2026-10-14: 26.6 keeps a warm runner, 27.0 is in
// demand, 26.1 wants nothing, and other fleets' pools are not this host's.
func rackCatalog() []unstructured.Unstructured {
	return []unstructured.Unstructured{
		runnerPool("macos-ber1-26-1-6vcpu", img261, "tuist-tuist-rack-fleet", 0, 0),
		runnerPool("macos-ber1-27-0-6vcpu", img270, "tuist-tuist-rack-fleet", 3, 0),
		runnerPool("macos-ber1-26-6-6vcpu", img266, "tuist-tuist-rack-fleet", 1, 1),
		runnerPool("macos-ber1-26-6-12vcpu", img266, "tuist-tuist-rack-fleet", 0, 0),
		runnerPool("ber1", img266, "tuist-tuist-rack-fleet", 0, 0),
		runnerPool("macos-26-6-rented", "ghcr.io/tuist/tuist-runner@sha256:rented", "tuist-tuist-runners-fleet", 4, 2),
	}
}

func TestPrewarmerPullsWarmFloorsThenDemandBeforeReleasing(t *testing.T) {
	goldens := &recordingGoldens{}
	gate := &fakeGate{held: true}
	p := &Prewarmer{
		K8s:      &poolLister{pools: rackCatalog()},
		Goldens:  goldens,
		Gate:     gate,
		Fleet:    "tuist-tuist-rack-fleet",
		DiskFree: plentyOfDisk,
	}

	if err := p.Start(context.Background()); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if want := []string{img266, img270}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("pulled %v, want %v", goldens.pulled, want)
	}
	if !gate.released {
		t.Fatal("the gate was not released after the prewarm")
	}
}

// A registered host is serving already; pulling every in-demand image on
// every host at once is what golden affinity exists to avoid.
func TestPrewarmerLeavesAnAlreadyRegisteredHostAlone(t *testing.T) {
	goldens := &recordingGoldens{}
	gate := &fakeGate{held: false}
	p := &Prewarmer{K8s: &poolLister{pools: rackCatalog()}, Goldens: goldens, Gate: gate, Fleet: "tuist-tuist-rack-fleet", DiskFree: plentyOfDisk}

	_ = p.Start(context.Background())

	if len(goldens.pulled) != 0 {
		t.Fatalf("pulled %v on a host that was already registered", goldens.pulled)
	}
	if !gate.released {
		t.Fatal("gate not released")
	}
}

func TestPrewarmerStopsAtTheDiskFloor(t *testing.T) {
	free := 80.0
	goldens := &recordingGoldens{onPull: func() { free = prewarmMinFreePercent - 1 }}
	gate := &fakeGate{held: true}
	p := &Prewarmer{
		K8s:      &poolLister{pools: rackCatalog()},
		Goldens:  goldens,
		Gate:     gate,
		Fleet:    "tuist-tuist-rack-fleet",
		DiskFree: func() (float64, error) { return free, nil },
	}

	_ = p.Start(context.Background())

	if want := []string{img266}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("pulled %v, want only %v before the disk floor", goldens.pulled, want)
	}
	if !gate.released {
		t.Fatal("stopping on disk must still release the gate")
	}
}

func TestPrewarmerReleasesWhenAPullOrTheListFails(t *testing.T) {
	goldens := &recordingGoldens{err: map[string]error{img266: errors.New("tart pull: registry 503")}}
	gate := &fakeGate{held: true}
	p := &Prewarmer{K8s: &poolLister{pools: rackCatalog()}, Goldens: goldens, Gate: gate, Fleet: "tuist-tuist-rack-fleet", DiskFree: plentyOfDisk}
	if err := p.Start(context.Background()); err != nil {
		t.Fatalf("Start returned %v; a Runnable error would stop the whole kubelet", err)
	}
	if want := []string{img266, img270}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("pulled %v, want the next image tried after a failed pull", goldens.pulled)
	}
	if !gate.released {
		t.Fatal("gate not released after a failed pull")
	}

	gate = &fakeGate{held: true}
	p = &Prewarmer{K8s: &poolLister{err: errors.New("no matches for kind RunnerPool")}, Goldens: &recordingGoldens{}, Gate: gate, Fleet: "f", DiskFree: plentyOfDisk}
	if err := p.Start(context.Background()); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if !gate.released {
		t.Fatal("gate not released when RunnerPools cannot be listed")
	}
}

func TestPrewarmImagesIgnoresLinuxPools(t *testing.T) {
	linux := runnerPool("linux", "ghcr.io/tuist/linux-runner:1", "tuist-tuist-rack-fleet", 4, 1)
	linux.Object["spec"].(map[string]any)["os"] = "linux"

	p := &Prewarmer{K8s: &poolLister{pools: []unstructured.Unstructured{linux}}, Fleet: "tuist-tuist-rack-fleet"}
	images, err := p.images(context.Background())
	if err != nil {
		t.Fatalf("images: %v", err)
	}
	if len(images) != 0 {
		t.Fatalf("images = %v, want none from a Linux pool", images)
	}
}
