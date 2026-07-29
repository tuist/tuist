package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestIsNoSpaceError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"unrelated", errors.New("connection refused"), false},
		// Foundation uses a curly apostrophe; the Sqlite layer Tart's
		// pull pipeline goes through speaks straight ENOSPC.
		{
			"curly-apostrophe",
			errors.New("Error: The file couldn’t be saved because there isn’t enough space."),
			true,
		},
		{
			"straight-apostrophe",
			errors.New("Error: The file couldn't be saved because there isn't enough space."),
			true,
		},
		{
			"sqlite",
			errors.New("ERROR: NSURLStorageURLCacheDB: database or disk is full"),
			true,
		},
		{
			"posix-enospc",
			errors.New("write /tmp/x: No space left on device"),
			true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsNoSpaceError(tc.err); got != tc.want {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
}

// A golden base with no backing Pod and past its retention window is a
// reap candidate — but only if it isn't currently running. On the staging
// host-Kura mini a golden was booted directly (launchd, serving
// benchmarks); with no liveness guard the GC killed it mid-session. These
// cases pin that the reap consults IsRunning before deleting.
func TestRunOnceSparesRunningVMs(t *testing.T) {
	const golden = goldenBaseVMPrefix + "deadbeef"
	const node = "mini-1"
	const retention = time.Hour
	now := time.Date(2026, 7, 9, 12, 0, 0, 0, time.UTC)

	newCollector := func(t *testing.T, isRunning func(context.Context, string) (bool, error)) (*Collector, string) {
		t.Helper()
		dir := t.TempDir()
		deletes := filepath.Join(dir, "deletes.txt")
		bin := filepath.Join(dir, "faketart")
		// `list` reports one stopped local golden; `delete` records the
		// name so the test can assert whether the reap fired.
		body := fmt.Sprintf("#!/bin/sh\n"+
			"if [ \"$1\" = \"list\" ]; then\n"+
			"  printf '%%s' '[{\"Name\":\"%s\",\"Source\":\"local\",\"State\":\"stopped\",\"CPU\":4,\"Memory\":8192,\"Size\":72}]'\n"+
			"elif [ \"$1\" = \"delete\" ]; then\n"+
			"  printf '%%s\\n' \"$2\" >> %q\n"+
			"fi\n", golden, deletes)
		if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}

		scheme := runtime.NewScheme()
		if err := corev1.AddToScheme(scheme); err != nil {
			t.Fatalf("add core scheme: %v", err)
		}
		// No Pods scheduled here, so the golden is unreferenced.
		k := fake.NewClientBuilder().WithScheme(scheme).
			WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
				return []string{o.(*corev1.Pod).Spec.NodeName}
			}).Build()

		c := &Collector{
			K8s:             k,
			Tart:            &tart.Client{Binary: bin},
			NodeName:        node,
			GoldenRetention: retention,
			Now:             func() time.Time { return now },
			IsRunning:       isRunning,
			// Last seen unreferenced 2h ago (retention 1h): absent the
			// liveness guard, this golden reaps.
			goldenSeen: map[string]time.Time{golden: now.Add(-2 * retention)},
		}
		return c, deletes
	}

	deleted := func(t *testing.T, deletes string) bool {
		t.Helper()
		b, err := os.ReadFile(deletes)
		if errors.Is(err, os.ErrNotExist) {
			return false
		}
		if err != nil {
			t.Fatal(err)
		}
		return strings.Contains(string(b), golden)
	}

	t.Run("running golden past retention is spared", func(t *testing.T) {
		c, deletes := newCollector(t, func(context.Context, string) (bool, error) { return true, nil })
		c.RunOnce(context.Background())
		if deleted(t, deletes) {
			t.Fatal("running golden past retention was deleted")
		}
	})

	t.Run("stopped golden past retention is reaped", func(t *testing.T) {
		c, deletes := newCollector(t, func(context.Context, string) (bool, error) { return false, nil })
		c.RunOnce(context.Background())
		if !deleted(t, deletes) {
			t.Fatal("stopped golden past retention was not reaped")
		}
	})

	t.Run("unreadable liveness signal spares the VM (fail-safe)", func(t *testing.T) {
		c, deletes := newCollector(t, func(context.Context, string) (bool, error) {
			return false, errors.New("pgrep boom")
		})
		c.RunOnce(context.Background())
		if deleted(t, deletes) {
			t.Fatal("golden was reaped despite an unreadable liveness signal")
		}
	})
}

// End-to-end regression for the substring liveness bug at the orphan
// branch, exercising the real Tart.IsRunning (no override). A stopped
// orphan `X` must be reaped even while a differently-named `X-2` runs —
// before IsRunning anchored the name, pgrep's substring match reported `X`
// live off the `X-2` process and the GC skipped it every pass. Both names
// are valid VMNameForPod outputs.
func TestRunOnceReapsOrphanDespiteSimilarlyNamedRunningVM(t *testing.T) {
	if _, err := exec.LookPath("pgrep"); err != nil {
		t.Skip("pgrep not available on this host")
	}

	const orphan = "tuist-runners-runner-team-job"
	const running = orphan + "-2"
	const node = "mini-1"

	dir := t.TempDir()
	deletes := filepath.Join(dir, "deletes.txt")
	bin := filepath.Join(dir, "faketart")
	body := fmt.Sprintf("#!/bin/sh\n"+
		"if [ \"$1\" = \"list\" ]; then\n"+
		"  printf '%%s' '[{\"Name\":\"%s\",\"Source\":\"local\",\"State\":\"running\",\"CPU\":4,\"Memory\":8192,\"Size\":72}]'\n"+
		"elif [ \"$1\" = \"delete\" ]; then\n"+
		"  printf '%%s\\n' \"$2\" >> %q\n"+
		"fi\n", orphan, deletes)
	if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	// A live `tart run <orphan>-2` decoy. The compound `-c` body keeps sh
	// from exec-replacing itself, so the argv survives for pgrep to read.
	decoyCtx, cancel := context.WithCancel(context.Background())
	defer cancel()
	decoy := exec.CommandContext(decoyCtx, "/bin/sh", "-c", "sleep 30; :", "tart", "run", running)
	if err := decoy.Start(); err != nil {
		t.Fatalf("start decoy: %v", err)
	}
	defer func() {
		cancel()
		_ = decoy.Wait()
	}()

	tartClient := &tart.Client{Binary: bin, UserDataDir: dir}
	// Wait until the decoy is visible so the test can't pass just because
	// pgrep hasn't caught up to the process yet.
	deadline := time.Now().Add(3 * time.Second)
	for {
		isUp, err := tartClient.IsRunning(context.Background(), running)
		if err != nil {
			t.Fatalf("IsRunning(%q): %v", running, err)
		}
		if isUp {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("decoy never became visible to pgrep")
		}
		time.Sleep(20 * time.Millisecond)
	}

	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add core scheme: %v", err)
	}
	// No Pods scheduled here, so the orphan is unreferenced.
	k := fake.NewClientBuilder().WithScheme(scheme).
		WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
			return []string{o.(*corev1.Pod).Spec.NodeName}
		}).Build()

	// IsRunning left nil so live() uses the real Tart.IsRunning.
	c := &Collector{K8s: k, Tart: tartClient, NodeName: node}
	c.RunOnce(context.Background())

	b, err := os.ReadFile(deletes)
	if err != nil {
		t.Fatalf("read deletes: %v", err)
	}
	if !strings.Contains(string(b), orphan) {
		t.Fatalf("orphan %q was not reaped despite only %q running", orphan, running)
	}
}

// Golden bases stay "referenced" forever when a warm Pod per Xcode pool
// pins each one (keepGolden never reaps a referenced golden), so retention
// alone can't stop the disk filling. reclaimGoldensUnderDiskPressure is the
// bound that does: below the host free-space floor it reaps referenced
// goldens too — least-valuable first, sparing the golden that backs a live
// clone and keeping at least MinGoldensKept.
func TestReclaimGoldensUnderDiskPressure(t *testing.T) {
	const node = "mini-1"

	pod := func(name, image string) *corev1.Pod {
		return &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{Namespace: "default", Name: name},
			Spec: corev1.PodSpec{
				NodeName:   node,
				Containers: []corev1.Container{{Name: "c", Image: image}},
			},
		}
	}

	// newCollector builds a Collector over a *stateful* fake tart: `list`
	// enumerates a VM directory and `delete` removes from it, so a golden the
	// aggressive main loop reaps is gone from the reclaim pass's re-list.
	// A static list would let reclaim count already-deleted goldens toward the
	// keep floor and over-delete the last real base.
	newCollector := func(t *testing.T, vms map[string]string, hostFree func() (float64, error), running func(string) bool, pods ...*corev1.Pod) (*Collector, func(t *testing.T) []string) {
		t.Helper()
		dir := t.TempDir()
		vmdir := filepath.Join(dir, "vms")
		if err := os.MkdirAll(vmdir, 0o755); err != nil {
			t.Fatal(err)
		}
		for name, src := range vms {
			if err := os.WriteFile(filepath.Join(vmdir, name), []byte(src), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		deletes := filepath.Join(dir, "deletes.txt")
		bin := filepath.Join(dir, "faketart")
		body := fmt.Sprintf(`#!/bin/sh
VMDIR=%q
DELETES=%q
if [ "$1" = "list" ]; then
  printf '['
  first=1
  for f in "$VMDIR"/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    src=$(cat "$f")
    if [ "$first" -eq 0 ]; then printf ','; fi
    printf '{"Name":"%%s","Source":"%%s","State":"stopped","CPU":4,"Memory":8192,"Size":68}' "$name" "$src"
    first=0
  done
  printf ']'
elif [ "$1" = "delete" ]; then
  rm -f "$VMDIR/$2"
  printf '%%s\n' "$2" >> "$DELETES"
fi
`, vmdir, deletes)
		if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
		scheme := runtime.NewScheme()
		if err := corev1.AddToScheme(scheme); err != nil {
			t.Fatalf("add core scheme: %v", err)
		}
		objs := make([]client.Object, 0, len(pods))
		for _, p := range pods {
			objs = append(objs, p)
		}
		k := fake.NewClientBuilder().WithScheme(scheme).
			WithObjects(objs...).
			WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
				return []string{o.(*corev1.Pod).Spec.NodeName}
			}).Build()
		c := &Collector{
			K8s:          k,
			Tart:         &tart.Client{Binary: bin},
			NodeName:     node,
			HostDiskFree: hostFree,
			IsRunning:    func(_ context.Context, name string) (bool, error) { return running(name), nil },
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
		return c, read
	}

	contains := func(xs []string, want string) bool {
		for _, x := range xs {
			if x == want {
				return true
			}
		}
		return false
	}

	t.Run("reaps referenced+unreferenced under pressure, spares live-backed", func(t *testing.T) {
		imgA := "reg/runner@sha256:aaa" // podA live  -> golden live-backed (spare)
		imgB := "reg/runner@sha256:bbb" // podB idle  -> golden idle-referenced (reap)
		imgC := "reg/runner@sha256:ccc" // no pod     -> golden unreferenced (reap first)
		gA, gB, gC := goldenVMName(imgA), goldenVMName(imgB), goldenVMName(imgC)
		// gC is unreferenced, so the aggressive main loop reaps it; gB is
		// referenced-but-idle, so only the disk-pressure reclaim reaps it;
		// gA backs podA's live clone, so it must survive both.
		c, read := newCollector(t, map[string]string{gA: "local", gB: "local", gC: "local"},
			func() (float64, error) { return 5, nil },
			func(name string) bool { return name == "default-pod-a" },
			pod("pod-a", imgA), pod("pod-b", imgB))
		c.RunOnce(context.Background())
		got := read(t)
		if !contains(got, gC) {
			t.Errorf("unreferenced golden %q not reaped under disk pressure; deletes=%v", gC, got)
		}
		if !contains(got, gB) {
			t.Errorf("idle referenced golden %q not reaped under disk pressure; deletes=%v", gB, got)
		}
		if contains(got, gA) {
			t.Errorf("live-backed golden %q was reaped; deletes=%v", gA, got)
		}
	})

	t.Run("stops reaping once free recovers", func(t *testing.T) {
		imgB1, imgB2 := "reg/runner@sha256:b11", "reg/runner@sha256:b22"
		gB1, gB2 := goldenVMName(imgB1), goldenVMName(imgB2)
		calls := 0
		hostFree := func() (float64, error) {
			calls++
			// runOnce probe (1) + reclaim's post-main-loop probe (2) are
			// both under the floor; the probe after the first reap (3+)
			// shows recovery, so exactly one golden is reaped.
			if calls <= 2 {
				return 5, nil
			}
			return 50, nil
		}
		// Both goldens are referenced by idle pods, so the aggressive main
		// loop keeps both and only the reclaim pass reaps — isolating the
		// "stop as soon as free recovers" behaviour to one deletion.
		c, read := newCollector(t, map[string]string{gB1: "local", gB2: "local"}, hostFree,
			func(string) bool { return false },
			pod("pod-b1", imgB1), pod("pod-b2", imgB2))
		c.RunOnce(context.Background())
		if got := read(t); len(got) != 1 {
			t.Fatalf("expected exactly one reap once free recovered, got %v", got)
		}
	})

	t.Run("no-op when above floor", func(t *testing.T) {
		imgA, imgB, imgC := "reg/runner@sha256:aaa", "reg/runner@sha256:bbb", "reg/runner@sha256:ccc"
		gA, gB, gC := goldenVMName(imgA), goldenVMName(imgB), goldenVMName(imgC)
		c, read := newCollector(t, map[string]string{gA: "local", gB: "local", gC: "local"},
			func() (float64, error) { return 50, nil },
			func(string) bool { return false },
			pod("pod-a", imgA), pod("pod-b", imgB))
		c.RunOnce(context.Background())
		if got := read(t); len(got) != 0 {
			t.Fatalf("reaped goldens despite ample free space; deletes=%v", got)
		}
	})
}
