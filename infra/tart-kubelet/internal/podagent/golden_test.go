package podagent

import (
	"context"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestGoldenVMName(t *testing.T) {
	const img = "ghcr.io/tuist/tuist-runner@sha256:" + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

	name := goldenVMName(img)

	if !isGoldenVMName(name) {
		t.Fatalf("goldenVMName(%q) = %q is not recognised as a golden name", img, name)
	}
	if !strings.HasPrefix(name, goldenBaseVMPrefix) {
		t.Fatalf("name %q missing prefix %q", name, goldenBaseVMPrefix)
	}
	if got := goldenVMName(img); got != name {
		t.Fatalf("goldenVMName not deterministic: %q != %q", got, name)
	}
	if len(name) > 63 {
		t.Fatalf("name %q exceeds Tart's 63-char limit (%d)", name, len(name))
	}

	// A different digest must map to a different golden so a runner-image
	// roll materialises a fresh base instead of reusing the old one.
	other := goldenVMName("ghcr.io/tuist/tuist-runner@sha256:" + strings.Repeat("f", 64))
	if other == name {
		t.Fatalf("distinct images collided on golden name %q", name)
	}

	// A per-Pod runner clone name must never be mistaken for a golden.
	runnerClone := "tuist-runners-runner-abc123"
	if isGoldenVMName(runnerClone) {
		t.Fatalf("runner clone %q misclassified as golden", runnerClone)
	}
}

// The golden base a Pod's image clones from must land in expectedSet so
// the GC's "local" branch retains it instead of reaping it as an orphan
// clone — the bug that would force a full re-pull on the next recycle.
func TestExpectedSetRetainsGoldenBase(t *testing.T) {
	const node = "mini-1"
	img := "ghcr.io/tuist/tuist-runner@sha256:" + strings.Repeat("a", 64)

	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-xyz"},
		Spec: corev1.PodSpec{
			NodeName:   node,
			Containers: []corev1.Container{{Name: "runner", Image: img}},
		},
	}

	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add core scheme: %v", err)
	}
	k := fake.NewClientBuilder().WithScheme(scheme).
		WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
			return []string{o.(*corev1.Pod).Spec.NodeName}
		}).
		WithObjects(pod).Build()

	c := &Collector{K8s: k, NodeName: node}
	expected, err := c.expectedSet(context.Background())
	if err != nil {
		t.Fatalf("expectedSet: %v", err)
	}

	if _, ok := expected.vms[VMNameForPod(pod)]; !ok {
		t.Fatalf("runner clone %q missing from expected.vms", VMNameForPod(pod))
	}
	if _, ok := expected.vms[goldenVMName(img)]; !ok {
		t.Fatalf("golden base %q missing from expected.vms", goldenVMName(img))
	}
	if _, ok := expected.images[img]; !ok {
		t.Fatalf("image %q missing from expected.images", img)
	}
}

func TestKeepGolden(t *testing.T) {
	now := time.Date(2026, 6, 24, 12, 0, 0, 0, time.UTC)
	const golden = goldenBaseVMPrefix + "deadbeef"
	const retention = time.Hour

	referenced := &expectedSet{vms: map[string]struct{}{golden: {}}, images: map[string]struct{}{}}
	unreferenced := &expectedSet{vms: map[string]struct{}{}, images: map[string]struct{}{}}

	t.Run("referenced is kept and clock reset", func(t *testing.T) {
		c := &Collector{}
		if !c.keepGolden(golden, referenced, now, retention, false) {
			t.Fatal("referenced golden was not kept")
		}
		if got := c.goldenSeen[golden]; !got.Equal(now) {
			t.Fatalf("last-seen = %v, want %v", got, now)
		}
	})

	t.Run("unreferenced first sighting is kept on grace", func(t *testing.T) {
		c := &Collector{}
		if !c.keepGolden(golden, unreferenced, now, retention, false) {
			t.Fatal("first-sight unreferenced golden was reaped immediately")
		}
		if got := c.goldenSeen[golden]; !got.Equal(now) {
			t.Fatalf("last-seen = %v, want %v", got, now)
		}
	})

	t.Run("unreferenced within retention is kept", func(t *testing.T) {
		c := &Collector{goldenSeen: map[string]time.Time{golden: now.Add(-30 * time.Minute)}}
		if !c.keepGolden(golden, unreferenced, now, retention, false) {
			t.Fatal("golden last seen 30m ago (retention 1h) was reaped")
		}
	})

	t.Run("unreferenced past retention is reaped", func(t *testing.T) {
		c := &Collector{goldenSeen: map[string]time.Time{golden: now.Add(-2 * time.Hour)}}
		if c.keepGolden(golden, unreferenced, now, retention, false) {
			t.Fatal("golden last seen 2h ago (retention 1h) was kept")
		}
	})

	t.Run("aggressive reaps unreferenced even when fresh", func(t *testing.T) {
		c := &Collector{goldenSeen: map[string]time.Time{golden: now}}
		if c.keepGolden(golden, unreferenced, now, retention, true) {
			t.Fatal("aggressive reclaim kept an unreferenced golden")
		}
	})

	t.Run("aggressive still keeps a referenced golden", func(t *testing.T) {
		c := &Collector{}
		if !c.keepGolden(golden, referenced, now, retention, true) {
			t.Fatal("aggressive reclaim reaped a golden a Pod still references")
		}
	})
}
