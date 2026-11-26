package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

// fakeTart answers attach requests the way Tart does, publishing
// `<id>.attached`, and stands in for the job by writing its ID into the clone
// it attached. With release it also answers detach requests with
// `<id>.detached`.
func fakeTart(t *testing.T, ctx context.Context, dir string, release bool) {
	t.Helper()
	go func() {
		for ctx.Err() == nil {
			entries, _ := os.ReadDir(dir)
			for _, entry := range entries {
				if id, ok := strings.CutSuffix(entry.Name(), ".attach"); ok {
					data, _ := os.ReadFile(filepath.Join(dir, entry.Name()))
					image := between(string(data), `"image":"`, `"`)
					if _, err := os.Stat(image); err != nil {
						t.Errorf("attach of a clone that does not exist: %s", image)
					}
					_ = os.WriteFile(image, []byte("written by "+id), 0600)
					_ = os.Remove(filepath.Join(dir, entry.Name()))
					_ = os.WriteFile(filepath.Join(dir, id+".attached"), []byte("{}"), 0600)
				}
				if id, ok := strings.CutSuffix(entry.Name(), ".detach"); ok && release {
					_ = os.Remove(filepath.Join(dir, entry.Name()))
					_ = os.WriteFile(filepath.Join(dir, id+".detached"), []byte("{}"), 0600)
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

func TestBlockVolumeKeepsOnlyACleanReleasedCloneOfTheCurrentVolume(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	root, share := t.TempDir(), t.TempDir()
	block := &BlockVolumes{Root: root, Run: func(_ context.Context, name string, args ...string) error {
		if name == "cp" {
			data, err := os.ReadFile(args[len(args)-2])
			if err != nil {
				return err
			}
			return os.WriteFile(args[len(args)-1], data, 0600)
		}
		return os.WriteFile(args[len(args)-1], []byte("empty"), 0600)
	}}
	scope := strings.Repeat("a", 64)
	pod := func(uid string) *corev1.Pod {
		return &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner-" + uid, UID: types.UID(uid)}}
	}
	attach := func(uid, id string, release, warm bool) {
		t.Helper()
		requests, _ := block.RequestDir(pod(uid))
		fakeTart(t, ctx, requests, release)
		response, err := block.Acquire(ctx, pod(uid), filepath.Join(share, uid), cachevolumes.Identity{ID: id, Scope: scope})
		if err != nil {
			t.Fatal(err)
		}
		if response["volume"] == "" {
			t.Fatal("no volume name for the guest")
		}
		if response["warm"] != warm {
			t.Errorf("%s warm = %v, want %v", id, response["warm"], warm)
		}
	}
	// The guest's clean detach, then the second it waits for Tart's release.
	detachCleanly := func(uid, id string) {
		t.Helper()
		_ = os.WriteFile(filepath.Join(share, uid, scope, ".detached"), []byte(id), 0644)
		for range 50 {
			block.Settle()
			if released, _ := os.ReadFile(filepath.Join(share, uid, scope, ".released")); string(released) == id {
				return
			}
			time.Sleep(20 * time.Millisecond)
		}
	}
	var ended []string
	end := func(_ context.Context, id string) { ended = append(ended, id) }
	gone := func(string, string) (bool, error) { return true, nil }

	// Two jobs clone the same volume: both detach cleanly, but only the first
	// to end replaces it; the second was cloned from a volume that has since
	// moved on.
	attach("pod-1", "use-1", true, false)
	attach("pod-2", "use-2", true, false)
	detachCleanly("pod-1", "use-1")
	detachCleanly("pod-2", "use-2")
	block.Reconcile(ctx, func(name, _ string) (bool, error) { return name == "runner-pod-1", nil }, end)
	block.Reconcile(ctx, gone, end)
	// A third job never detaches cleanly, as when it failed or was cancelled.
	attach("pod-3", "use-3", true, true)
	block.Reconcile(ctx, gone, end)
	// A fourth detaches cleanly, but its VM stops before Tart lets go of the
	// disk, so its clone may be missing writes.
	attach("pod-4", "use-4", false, true)
	detachCleanly("pod-4", "use-4")
	block.Reconcile(ctx, gone, end)

	manifest, err := readBlockManifest(block.volumeDir(scope))
	if err != nil {
		t.Fatal(err)
	}
	volume, _ := os.ReadFile(volumeImage(block.volumeDir(scope)))
	if manifest.Generation != 1 || string(volume) != "written by use-1" {
		t.Fatalf("volume = %q at generation %d, want use-1's writes at generation 1", volume, manifest.Generation)
	}
	for _, id := range []string{"use-2", "use-3", "use-4"} {
		if _, err := os.Stat(filepath.Join(block.volumeDir(scope), "jobs", id+".asif")); !os.IsNotExist(err) {
			t.Errorf("%s's clone was left behind: %v", id, err)
		}
	}
	if strings.Join(ended, ",") != "use-1,use-2,use-3,use-4" {
		t.Errorf("ended uses = %v", ended)
	}
}
