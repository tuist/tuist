package cachevolumes

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func capturedLog() (*slog.Logger, *bytes.Buffer) {
	var out bytes.Buffer
	return slog.New(slog.NewTextHandler(&out, nil)), &out
}

// On 2026-10-21 cache phase lines carried only their category, so which
// volume a phase ran for had to be inferred from the server's records.
func TestPhasesNameTheirVolume(t *testing.T) {
	b, _ := newLocal(t)
	var observations []Observation
	b.Observe = func(o Observation) { observations = append(observations, o) }
	slot := Slot{Identity: identity(first), PodName: "runner-1", PodUID: "pod"}
	slot.ManagedKey = "tuist-xcode"
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	jobWrote(t, path)
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	want := Subject{Scope: slot.Scope, Use: slot.ID, Kind: KindManaged, Key: "tuist-xcode", Pod: "runner-1"}
	operations := map[string]bool{}
	for _, o := range observations {
		operations[o.Operation] = true
		if o.Subject != want {
			t.Fatalf("%s reported %+v", o.Operation, o.Subject)
		}
	}
	for _, operation := range []string{"admission", "format", "mount", "attach", "compress", "upload", "publish"} {
		if !operations[operation] {
			t.Fatal("missing phase", operation, operations)
		}
	}
}

func TestSubjectNeverCarriesACustomerKey(t *testing.T) {
	slot := Slot{Identity: identity(first), PodName: "runner-1"}
	slot.ManagedKey = "acme-ios-derived-data"
	subject := SubjectOf(slot)
	if subject.Kind != KindCustom || subject.Key != "" {
		t.Fatalf("%+v", subject)
	}
	fields := fmt.Sprint(subject.Fields()...)
	if strings.Contains(fields, "acme") {
		t.Fatal(fields)
	}
	slot.Kind, slot.Generation, slot.ManagedKey = KindCheckout, 4, "tuist-xcode"
	if subject := SubjectOf(slot); subject.Kind != KindCheckout || subject.Key != "" || subject.CheckoutGeneration != 4 {
		t.Fatalf("%+v", subject)
	}
}

func writeMaster(t *testing.T, root, scope string, generation int64, age time.Duration) string {
	t.Helper()
	master := filepath.Join(root, "masters", scope, fmt.Sprintf("%020d-%s.img", generation, strings.Repeat("c", 64)))
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, make([]byte, 64<<10), 0600); err != nil {
		t.Fatal(err)
	}
	used := time.Now().Add(-age)
	if err := os.Chtimes(master, used, used); err != nil {
		t.Fatal(err)
	}
	return master
}

func TestCapacityEvictionNamesTheMasterAndWhatItMadeRoomFor(t *testing.T) {
	root := t.TempDir()
	scope := strings.Repeat("a", 64)
	writeMaster(t, root, scope, 3, time.Hour)
	free := uint64(0)
	log, out := capturedLog()
	b := &LocalImages{Root: root, Log: log, FreeBytes: func(string) (uint64, error) { return free, nil }}
	b.Reclaim = func(_ context.Context, minimum uint64) error {
		free = minimum
		return nil
	}
	job := Slot{Identity: identity(first), PodName: "runner-1"}
	if err := b.reserveBytes(WithSubject(context.Background(), SubjectOf(job)), 20); err != nil {
		t.Fatal(err)
	}
	line := out.String()
	for _, want := range []string{`msg="cache master evicted"`, "scope=" + scope, "generation=3", "reason=idle", "needed_bytes=20", "free_bytes=0", "for_use=" + first, "for_pod=runner-1", "bytes="} {
		if !strings.Contains(line, want) {
			t.Fatalf("missing %s in %s", want, line)
		}
	}
}

func TestMaintenanceEvictionsLogTheirReason(t *testing.T) {
	b, r := newLocal(t)
	log, out := capturedLog()
	b.Log = log
	idle := writeMaster(t, b.Root, strings.Repeat("b", 64), 2, 8*24*time.Hour)
	slot := Slot{Identity: identity(first), PodUID: "p"}
	path := t.TempDir()
	if err := b.Attach(context.Background(), slot, path); err != nil {
		t.Fatal(err)
	}
	jobWrote(t, path)
	if err := b.Seal(slot, path); err != nil {
		t.Fatal(err)
	}
	b.Transfer = invalidatedTransfer{r}
	if err := b.Maintain(); err != nil {
		t.Fatal(err)
	}
	lines := out.String()
	for _, want := range []string{
		"scope=" + filepath.Base(filepath.Dir(idle)) + " generation=2 bytes=",
		"scope=" + slot.Scope + " generation=1 bytes=",
		"reason=expired",
		"reason=superseded head_generation=2",
	} {
		if !strings.Contains(lines, want) {
			t.Fatalf("missing %s in %s", want, lines)
		}
	}
}
