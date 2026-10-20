package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

const (
	stagingNode  = "ber1-runner-b02"
	stagingFleet = "tuist-tuist-rack-fleet"
	img3610      = "ghcr.io/tuist/tuist-runner:macos-26-1-1-0.36.0"
	img3611      = "ghcr.io/tuist/tuist-runner:macos-26-1-1-0.36.1"
)

func prewarmAnnotation(image string) string {
	return prewarmImageAnnotationPrefix + strings.TrimPrefix(goldenVMName(image), goldenBaseVMPrefix)
}

// stagingReader serves Pods and Nodes from a fake client and RunnerPools from
// a fixed list, which the fake client cannot list as unstructured.
type stagingReader struct {
	client.Reader
	pools []unstructured.Unstructured
}

func (r *stagingReader) List(ctx context.Context, list client.ObjectList, opts ...client.ListOption) error {
	if ul, ok := list.(*unstructured.UnstructuredList); ok {
		if ul.GroupVersionKind() != runnerPoolListGVK {
			return errors.New("unexpected kind " + ul.GroupVersionKind().String())
		}
		ul.Items = append(ul.Items, r.pools...)
		return nil
	}
	return r.Reader.List(ctx, list, opts...)
}

func newStagingReader(t *testing.T, annotations map[string]string, pools ...unstructured.Unstructured) *stagingReader {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add core scheme: %v", err)
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: stagingNode, Annotations: annotations}}
	k := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).
		WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
			return []string{o.(*corev1.Pod).Spec.NodeName}
		}).Build()
	return &stagingReader{Reader: k, pools: pools}
}

func servingPool(name, specImage, servingImage string) unstructured.Unstructured {
	pool := runnerPool(name, specImage, stagingFleet, 0, 0)
	if servingImage != "" {
		pool.Object["status"] = map[string]any{"servingImage": servingImage}
	}
	return pool
}

func TestPrewarmerDownloadsTheImagesItsNodeRequests(t *testing.T) {
	annotations := map[string]string{
		prewarmAnnotation(img3610): img3610,
		prewarmAnnotation(img3611): img3611,
		// A key that does not match the image it names is ignored.
		prewarmAnnotation(img270): img3611 + "-other",
		"tuist.dev/unrelated":     img266,
	}
	goldens := &recordingGoldens{held: map[string]bool{img3610: true}}
	p := &Prewarmer{
		K8s:      newStagingReader(t, annotations),
		Goldens:  goldens,
		NodeName: stagingNode,
		DiskFree: plentyOfDisk,
	}

	p.prewarmRequested(context.Background())

	if want := []string{img3611}; !reflect.DeepEqual(goldens.pulled, want) {
		t.Fatalf("pulled %v, want %v", goldens.pulled, want)
	}
}

func TestPrewarmerDefersRequestedImagesBelowTheDiskFloor(t *testing.T) {
	goldens := &recordingGoldens{}
	p := &Prewarmer{
		K8s:      newStagingReader(t, map[string]string{prewarmAnnotation(img3611): img3611}),
		Goldens:  goldens,
		NodeName: stagingNode,
		DiskFree: func() (float64, error) { return prewarmMinFreePercent - 1, nil },
	}

	p.prewarmRequested(context.Background())

	if len(goldens.pulled) != 0 {
		t.Fatalf("pulled %v below the disk floor, want nothing", goldens.pulled)
	}
}

func TestPrewarmImagesPullsTheServingImageWhileANewOneStages(t *testing.T) {
	pools := []prewarmPool{}
	for _, item := range []unstructured.Unstructured{servingPool("macos-ber1-26-1-1", img3611, img3610)} {
		item.Object["spec"].(map[string]any)["replicas"] = int64(1)
		pool, err := decodePool(item)
		if err != nil {
			t.Fatal(err)
		}
		pools = append(pools, pool)
	}

	if got, want := prewarmImages(pools, stagingFleet), []string{img3610}; !reflect.DeepEqual(got, want) {
		t.Fatalf("prewarm images = %v, want %v", got, want)
	}
}

func decodePool(item unstructured.Unstructured) (prewarmPool, error) {
	pools, err := listRunnerPools(context.Background(), &stagingReader{pools: []unstructured.Unstructured{item}})
	if err != nil || len(pools) != 1 {
		return prewarmPool{}, fmt.Errorf("decode pool: %v", err)
	}
	return pools[0], nil
}

// stagingCollector runs the GC over a fake tart holding the given local
// golden bases, every one unreferenced and last seen within retention.
func stagingCollector(t *testing.T, reader client.Reader, fleet string, goldens ...string) (*Collector, func() []string) {
	t.Helper()
	dir := t.TempDir()
	deletes := filepath.Join(dir, "deletes.txt")
	entries := make([]string, 0, len(goldens))
	for _, name := range goldens {
		entries = append(entries, fmt.Sprintf(`{"Name":"%s","Source":"local","State":"stopped","CPU":4,"Memory":8192,"Size":60}`, name))
	}
	bin := filepath.Join(dir, "faketart")
	body := fmt.Sprintf("#!/bin/sh\n"+
		"if [ \"$1\" = \"list\" ]; then\n"+
		"  printf '%%s' '[%s]'\n"+
		"elif [ \"$1\" = \"delete\" ]; then\n"+
		"  printf '%%s\\n' \"$2\" >> %q\n"+
		"fi\n", strings.Join(entries, ","), deletes)
	if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)
	seen := map[string]time.Time{}
	for _, name := range goldens {
		seen[name] = now.Add(-time.Hour)
	}
	c := &Collector{
		K8s:             reader,
		Tart:            &tart.Client{Binary: bin},
		NodeName:        stagingNode,
		Fleet:           fleet,
		GoldenRetention: 24 * time.Hour,
		HostDiskFree:    plentyOfDisk,
		Now:             func() time.Time { return now },
		IsRunning:       func(context.Context, string) (bool, error) { return false, nil },
		goldenSeen:      seen,
	}
	return c, func() []string {
		b, err := os.ReadFile(deletes)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		if err != nil {
			t.Fatal(err)
		}
		return strings.Fields(string(b))
	}
}

func TestCollectorReapsGoldensOfImagesNoPoolNamesAnyMore(t *testing.T) {
	superseded := goldenVMName("ghcr.io/tuist/tuist-runner:macos-26-1-1-0.35.0")
	reader := newStagingReader(t, nil, servingPool("macos-ber1-26-1-1", img3611, img3610))
	c, deleted := stagingCollector(t, reader, stagingFleet, superseded, goldenVMName(img3610), goldenVMName(img3611))

	c.RunOnce(context.Background())

	if got, want := deleted(), []string{superseded}; !reflect.DeepEqual(got, want) {
		t.Fatalf("deleted %v, want only the superseded golden %v: the pool still serves and stages the others", got, want)
	}
}

func TestCollectorKeepsGoldensItsNodeWasAskedToHold(t *testing.T) {
	asked := "ghcr.io/tuist/tuist-runner:macos-26-0-1-0.36.1"
	reader := newStagingReader(t, map[string]string{prewarmAnnotation(asked): asked})
	c, deleted := stagingCollector(t, reader, stagingFleet, goldenVMName(asked))
	c.goldenSeen[goldenVMName(asked)] = c.now().Add(-48 * time.Hour)

	c.RunOnce(context.Background())

	if got := deleted(); len(got) != 0 {
		t.Fatalf("deleted %v, want the requested golden kept past retention", got)
	}
}

func TestCollectorKeepsRetentionOnHostsNoPoolServes(t *testing.T) {
	other := goldenVMName("ghcr.io/tuist/xcresult-processor:0.12.0")
	reader := newStagingReader(t, nil, servingPool("macos-ber1-26-1-1", img3611, img3610))
	c, deleted := stagingCollector(t, reader, "tuist-tuist-macos-fleet", other)

	c.RunOnce(context.Background())

	if got := deleted(); len(got) != 0 {
		t.Fatalf("deleted %v, want goldens on a host outside every pool's fleet kept for the retention window", got)
	}
}
