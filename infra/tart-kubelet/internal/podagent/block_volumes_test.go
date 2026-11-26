package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

// fakeTart answers every attach request the way Tart does: it creates the
// overlay it was asked for and publishes `<id>.attached`.
func fakeTart(t *testing.T, ctx context.Context, dir string) {
	t.Helper()
	go func() {
		for ctx.Err() == nil {
			entries, _ := os.ReadDir(dir)
			for _, entry := range entries {
				if id, ok := strings.CutSuffix(entry.Name(), ".attach"); ok {
					data, _ := os.ReadFile(filepath.Join(dir, entry.Name()))
					overlay := between(string(data), `"overlay":"`, `"`)
					_ = os.WriteFile(overlay, []byte("overlay"), 0600)
					_ = os.Remove(filepath.Join(dir, entry.Name()))
					_ = os.WriteFile(filepath.Join(dir, id+".attached"), []byte("{}"), 0600)
				}
			}
		}
	}()
}

func between(s, start, end string) string {
	_, after, _ := strings.Cut(s, start)
	value, _, _ := strings.Cut(after, end)
	return value
}

func TestBlockVolumeKeepsOnlyACleanOverlayOnTheStackItWasMadeOn(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	root, share := t.TempDir(), t.TempDir()
	block := &BlockVolumes{Root: root, Run: func(_ context.Context, name string, args ...string) error {
		return os.WriteFile(args[len(args)-1], []byte("base"), 0600)
	}}
	scope := strings.Repeat("a", 64)
	pod := func(uid string) *corev1.Pod {
		return &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner-" + uid, UID: types.UID(uid)}}
	}
	attach := func(uid, id string) {
		t.Helper()
		requests, _ := block.RequestDir(pod(uid))
		fakeTart(t, ctx, requests)
		response, err := block.Acquire(ctx, pod(uid), filepath.Join(share, uid), cachevolumes.Identity{ID: id, Scope: scope})
		if err != nil {
			t.Fatal(err)
		}
		if response["volume"] == "" {
			t.Fatal("no volume name for the guest")
		}
	}
	detachCleanly := func(uid, id string) {
		_ = os.WriteFile(filepath.Join(share, uid, scope, ".detached"), []byte(id), 0644)
	}
	var ended []string
	end := func(_ context.Context, id string) { ended = append(ended, id) }
	gone := func(string, string) (bool, error) { return true, nil }

	// Two jobs on the same stack: both detach cleanly, but only the first to
	// end can become the next layer; the second was made on a stack that has
	// since moved.
	attach("pod-1", "use-1")
	attach("pod-2", "use-2")
	detachCleanly("pod-1", "use-1")
	detachCleanly("pod-2", "use-2")
	block.Reconcile(ctx, func(name, _ string) (bool, error) { return name == "runner-pod-1", nil }, end)
	block.Reconcile(ctx, gone, end)
	// A third job never detaches cleanly, as when it failed or was cancelled.
	attach("pod-3", "use-3")
	block.Reconcile(ctx, gone, end)

	manifest, err := readBlockManifest(block.volumeDir(scope))
	if err != nil {
		t.Fatal(err)
	}
	if len(manifest.Layers) != 2 || !strings.HasSuffix(manifest.Layers[1], "layer-use-1.asif") {
		t.Fatalf("layers = %v, want the base and use-1's overlay", manifest.Layers)
	}
	for _, id := range []string{"use-2", "use-3"} {
		if _, err := os.Stat(filepath.Join(block.volumeDir(scope), "jobs", id+".asif")); !os.IsNotExist(err) {
			t.Errorf("%s's overlay was left behind: %v", id, err)
		}
	}
	if strings.Join(ended, ",") != "use-1,use-2,use-3" {
		t.Errorf("ended uses = %v", ended)
	}
}
