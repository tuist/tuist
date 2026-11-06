package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func fakeTartListing(t *testing.T, listing string, fail bool) *tart.Client {
	t.Helper()
	bin := filepath.Join(t.TempDir(), "faketart")
	body := fmt.Sprintf("#!/bin/sh\nif [ \"$1\" = \"list\" ]; then\n  printf '%%s' '%s'\nfi\n", listing)
	if fail {
		body = "#!/bin/sh\necho 'tart list failed' >&2\nexit 1\n"
	}
	if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return &tart.Client{Binary: bin}
}

// A reinstalled host comes back with no marker and no golden, which is what
// the prewarm gate holds. An idle host that holds no golden right now still
// has its marker, and a host that holds one records the marker, so neither is
// held on a restart.
func TestHostDiskFresh(t *testing.T) {
	golden := `[{"Name":"` + goldenVMName("ghcr.io/tuist/tuist-runner@sha256:aaa") + `","Source":"local","State":"stopped"}]`

	t.Run("no marker and no golden is fresh", func(t *testing.T) {
		h := &HostDisk{Tart: fakeTartListing(t, "[]", false), MarkerPath: filepath.Join(t.TempDir(), "marker")}
		if fresh, err := h.Fresh(context.Background()); err != nil || !fresh {
			t.Fatalf("Fresh = %v, %v; want an erased disk to be fresh", fresh, err)
		}
	})

	t.Run("a golden without a marker records one", func(t *testing.T) {
		h := &HostDisk{Tart: fakeTartListing(t, golden, false), MarkerPath: filepath.Join(t.TempDir(), "state", "marker")}
		if fresh, err := h.Fresh(context.Background()); err != nil || fresh {
			t.Fatalf("Fresh = %v, %v; want a host holding a golden not to be fresh", fresh, err)
		}
		if _, err := os.Stat(h.MarkerPath); err != nil {
			t.Fatalf("marker not recorded for a host holding a golden: %v", err)
		}
	})

	t.Run("a marker without a golden is not fresh", func(t *testing.T) {
		h := &HostDisk{Tart: fakeTartListing(t, "[]", false), MarkerPath: filepath.Join(t.TempDir(), "marker")}
		if err := h.Record(); err != nil {
			t.Fatal(err)
		}
		if fresh, err := h.Fresh(context.Background()); err != nil || fresh {
			t.Fatalf("Fresh = %v, %v; want an idle host whose images were superseded not to be fresh", fresh, err)
		}
	})

	t.Run("a failed listing is an error", func(t *testing.T) {
		h := &HostDisk{Tart: fakeTartListing(t, "", true), MarkerPath: filepath.Join(t.TempDir(), "marker")}
		if _, err := h.Fresh(context.Background()); err == nil {
			t.Fatal("Fresh hid a failed tart list")
		}
	})
}

// A golden already on disk is recorded too, so a host that only ever clones
// from goldens it pulled before the marker existed still gets one.
func TestEnsureGoldenRecordsTheHostDisk(t *testing.T) {
	bin, _ := fakeTartForGolden(t, false)
	h := &HostDisk{MarkerPath: filepath.Join(t.TempDir(), "marker")}
	r := &Reconciler{Tart: &tart.Client{Binary: bin}, HostDisk: h}
	if _, _, err := r.ensureGolden(context.Background(), "ghcr.io/tuist/tuist-runner@sha256:aaa"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(h.MarkerPath); errors.Is(err, os.ErrNotExist) {
		t.Fatal("ensureGolden did not record that the host holds a golden")
	}
}
