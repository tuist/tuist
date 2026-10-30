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
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// A release moves a pool to a new image. A host that holds the previous one
// pulls the new one before the GC reaps the previous golden, so the base
// both share stays in Tart's content store and the pull is only the overlay.
func TestRunOnceFollowsAReleaseBeforeReapingThePreviousImage(t *testing.T) {
	const node = "mini-1"
	const fleet = "tuist-tuist-rack-fleet"
	const repo = "ghcr.io/tuist/tuist-runner"
	previous := repo + "@sha256:previous"
	current := repo + "@sha256:current"
	start := time.Date(2026, 10, 22, 13, 0, 0, 0, time.UTC)

	released := func(status map[string]any) *poolLister {
		pool := runnerPool("macos-ber1-27-0", current, fleet, 1, 1)
		pool.Object["status"] = status
		return &poolLister{pools: []unstructured.Unstructured{pool}}
	}
	withPrevious := map[string]any{"observedImage": current, "previousImage": previous}

	type collector struct {
		*Collector
		goldens *recordingGoldens
		now     *time.Time
		free    *float64
		deletes func(t *testing.T) []string
	}
	newCollector := func(t *testing.T, entries []string, pools *poolLister) collector {
		t.Helper()
		dir := t.TempDir()
		var listing []string
		for _, e := range entries {
			source := "local"
			if !isGoldenVMName(e) {
				source = "OCI"
			}
			listing = append(listing, fmt.Sprintf(`{"Name":"%s","Source":"%s","State":"stopped","CPU":4,"Memory":8192,"Size":68}`, e, source))
		}
		deletes := filepath.Join(dir, "deletes.txt")
		bin := filepath.Join(dir, "faketart")
		body := fmt.Sprintf("#!/bin/sh\n"+
			"if [ \"$1\" = \"list\" ]; then\n"+
			"  printf '%%s' '[%s]'\n"+
			"elif [ \"$1\" = \"delete\" ]; then\n"+
			"  printf '%%s\\n' \"$2\" >> %q\n"+
			"fi\n", strings.Join(listing, ","), deletes)
		if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
		scheme := runtime.NewScheme()
		if err := corev1.AddToScheme(scheme); err != nil {
			t.Fatalf("add core scheme: %v", err)
		}
		k := fake.NewClientBuilder().WithScheme(scheme).
			WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
				return []string{o.(*corev1.Pod).Spec.NodeName}
			}).Build()
		now := start
		free := 50.0
		goldens := &recordingGoldens{}
		c := &Collector{
			K8s:             &gcReader{Reader: k, pools: pools},
			Tart:            &tart.Client{Binary: bin},
			NodeName:        node,
			Fleet:           fleet,
			GoldenRetention: 24 * time.Hour,
			Now:             func() time.Time { return now },
			HostDiskFree:    func() (float64, error) { return free, nil },
			IsRunning:       func(context.Context, string) (bool, error) { return false, nil },
			Goldens:         goldens,
		}
		read := func(t *testing.T) []string {
			t.Helper()
			b, err := os.ReadFile(deletes)
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			if err != nil {
				t.Fatal(err)
			}
			return strings.Fields(string(b))
		}
		return collector{Collector: c, goldens: goldens, now: &now, free: &free, deletes: read}
	}
	run := func(c collector) {
		c.RunOnce(context.Background())
		c.followWG.Wait()
	}

	t.Run("pulls the current image and keeps the previous one meanwhile", func(t *testing.T) {
		c := newCollector(t, []string{goldenVMName(previous), previous}, released(withPrevious))
		run(c)
		if got := c.deletes(t); len(got) != 0 {
			t.Fatalf("deletes = %v, want none until the current image is pulled", got)
		}
		if want := []string{current}; !reflect.DeepEqual(c.goldens.pulled, want) {
			t.Fatalf("pulled = %v, want %v", c.goldens.pulled, want)
		}
	})

	t.Run("reaps the previous image once the current one is here", func(t *testing.T) {
		c := newCollector(t, []string{goldenVMName(previous), goldenVMName(current), previous, current}, released(withPrevious))
		run(c)
		if want := []string{goldenVMName(previous), previous}; !reflect.DeepEqual(c.deletes(t), want) {
			t.Fatalf("deletes = %v, want %v", c.deletes(t), want)
		}
		if len(c.goldens.pulled) != 0 {
			t.Fatalf("pulled = %v, want nothing", c.goldens.pulled)
		}
	})

	t.Run("pulls nothing on a host that never held the previous image", func(t *testing.T) {
		c := newCollector(t, nil, released(withPrevious))
		run(c)
		if len(c.goldens.pulled) != 0 {
			t.Fatalf("pulled = %v, want nothing", c.goldens.pulled)
		}
	})

	t.Run("follows a release the controller has not recorded yet", func(t *testing.T) {
		c := newCollector(t, []string{goldenVMName(previous), previous}, released(map[string]any{"observedImage": previous}))
		run(c)
		if got := c.deletes(t); len(got) != 0 {
			t.Fatalf("deletes = %v, want none", got)
		}
		if want := []string{current}; !reflect.DeepEqual(c.goldens.pulled, want) {
			t.Fatalf("pulled = %v, want %v", c.goldens.pulled, want)
		}
	})

	t.Run("lets the previous image go after the follow timeout", func(t *testing.T) {
		c := newCollector(t, []string{goldenVMName(previous), previous}, released(withPrevious))
		c.goldens.err = map[string]error{current: errors.New("manifest unknown")}
		run(c)
		if got := c.deletes(t); len(got) != 0 {
			t.Fatalf("deletes = %v, want none inside the timeout", got)
		}
		*c.now = start.Add(defaultFollowTimeout)
		run(c)
		if want := []string{goldenVMName(previous), previous}; !reflect.DeepEqual(c.deletes(t), want) {
			t.Fatalf("deletes = %v, want %v", c.deletes(t), want)
		}
	})

	t.Run("does not follow under disk pressure", func(t *testing.T) {
		c := newCollector(t, []string{goldenVMName(previous), previous}, released(withPrevious))
		*c.free = defaultGoldenReclaimFreeFloor - 1
		run(c)
		if len(c.goldens.pulled) != 0 {
			t.Fatalf("pulled = %v, want nothing under disk pressure", c.goldens.pulled)
		}
		if got := c.deletes(t); len(got) == 0 || got[0] != goldenVMName(previous) {
			t.Fatalf("deletes = %v, want the previous golden reaped", got)
		}
	})

	t.Run("does not pull below the prewarm free floor", func(t *testing.T) {
		c := newCollector(t, []string{goldenVMName(previous), previous}, released(withPrevious))
		*c.free = prewarmMinFreePercent - 1
		run(c)
		if len(c.goldens.pulled) != 0 {
			t.Fatalf("pulled = %v, want nothing below the prewarm floor", c.goldens.pulled)
		}
	})
}
