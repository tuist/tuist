package podagent

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"k8s.io/client-go/kubernetes/fake"
)

func TestVolumeUsagePersistsRetriesAndHostIdentity(t *testing.T) {
	root := t.TempDir()
	warm := true
	usage := &volumeUsage{PodName: "guest-chosen", PodUID: "guest", VolumeName: "guest", AttachedAt: time.Now().UTC().Format(time.RFC3339), AttachMS: 42, AttachedSizeBytes: 1024, SizeBytes: 4096, CapacityBytes: 20000000000, Warm: &warm}
	entry := &Entry{PodName: "actual-pod", PodUID: "actual-uid", Volume: VolumeAttachment{VolumeName: "tuist-cache", PromotedGeneration: 3}}
	worker := NewConvergeWorker(&VolumeManager{Root: root, CapGiB: 28}, false, nil)
	if err := worker.queueUsage(entry, usage, VolumeOutcomePromoted); err != nil {
		t.Fatal(err)
	}
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if r.URL.Path != "/api/internal/runners/cache-masters/usage" || r.Header.Get("Authorization") != "Bearer host-token" {
			t.Errorf("wrong host request: %s %v", r.URL.Path, r.Header)
		}
		var got volumeUsage
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		if got.PodName != entry.PodName || got.PodUID != entry.PodUID || got.VolumeName != "tuist-cache" || got.Generation != 3 || got.Outcome != "promoted" {
			t.Errorf("identity/outcome: %+v", got)
		}
		if attempts == 1 {
			w.WriteHeader(503)
			return
		}
		w.WriteHeader(200)
	}))
	defer server.Close()
	source := &ServerPrefetch{Client: fake.NewSimpleClientset(), endpoint: server.URL + "/api/internal/runners/cache-masters", token: "host-token", tokenExpiry: time.Now().Add(5 * time.Minute)}
	// A new worker reads the queue left by the previous process.
	restarted := NewConvergeWorker(worker.Volumes, false, source)
	restarted.reportUsage(context.Background())
	path := filepath.Join(root, "usage-reports", "actual-uid.json")
	if _, err := os.Stat(path); err != nil {
		t.Fatal("failed report was lost", err)
	}
	restarted.reportUsage(context.Background())
	if attempts != 1 {
		t.Fatalf("retried before the backoff elapsed: %d attempts", attempts)
	}
	past := time.Now().Add(-time.Second)
	if err := os.Chtimes(path, past, past); err != nil {
		t.Fatal(err)
	}
	restarted.reportUsage(context.Background())
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("acknowledged report retained", err)
	}
	if attempts != 2 {
		t.Fatalf("attempts %d", attempts)
	}
}

func TestVolumeUsageDropsReportsTheServerWillNeverAccept(t *testing.T) {
	for _, tc := range []struct {
		name     string
		status   int
		attached time.Time
		dropped  bool
	}{
		{"execution unavailable", http.StatusGone, time.Now(), true},
		{"invalid report", http.StatusUnprocessableEntity, time.Now(), true},
		{"execution pending", http.StatusTooEarly, time.Now(), false},
		{"server unavailable", http.StatusServiceUnavailable, time.Now(), false},
		{"pending past the max age", http.StatusTooEarly, time.Now().Add(-usageReportMaxAge - time.Minute), true},
		{"server unavailable past the max age", http.StatusServiceUnavailable, time.Now().Add(-usageReportMaxAge - time.Minute), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			warm := true
			usage := &volumeUsage{AttachedAt: tc.attached.UTC().Format(time.RFC3339), CapacityBytes: 1, Warm: &warm}
			entry := &Entry{PodName: "pod", PodUID: "uid", Volume: VolumeAttachment{VolumeName: "tuist-cache"}}
			worker := NewConvergeWorker(&VolumeManager{Root: root, CapGiB: 28}, false, nil)
			if err := worker.queueUsage(entry, usage, VolumeOutcomeDiscarded); err != nil {
				t.Fatal(err)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(tc.status)
			}))
			defer server.Close()
			worker.Prefetch = &ServerPrefetch{Client: fake.NewSimpleClientset(), endpoint: server.URL, token: "host-token", tokenExpiry: time.Now().Add(5 * time.Minute)}
			worker.reportUsage(context.Background())
			path := filepath.Join(root, "usage-reports", "uid.json")
			info, err := os.Stat(path)
			if tc.dropped {
				if !os.IsNotExist(err) {
					t.Fatal("report retained", err)
				}
				return
			}
			if err != nil {
				t.Fatal("report dropped", err)
			}
			if !info.ModTime().After(time.Now()) {
				t.Fatal("retry not deferred")
			}
		})
	}
}

func TestVolumeUsageKeepsReportsBlockedByLocalFailures(t *testing.T) {
	root := t.TempDir()
	warm := true
	usage := &volumeUsage{AttachedAt: time.Now().Add(-usageReportMaxAge - time.Hour).UTC().Format(time.RFC3339), CapacityBytes: 1, Warm: &warm}
	entry := &Entry{PodName: "pod", PodUID: "uid", Volume: VolumeAttachment{VolumeName: "tuist-cache"}}
	worker := NewConvergeWorker(&VolumeManager{Root: root, CapGiB: 28}, false, &ServerPrefetch{})
	if err := worker.queueUsage(entry, usage, VolumeOutcomeDiscarded); err != nil {
		t.Fatal(err)
	}
	worker.reportUsage(context.Background())
	if _, err := os.Stat(filepath.Join(root, "usage-reports", "uid.json")); err != nil {
		t.Fatal("report waiting for an unknown endpoint was dropped", err)
	}
}

func TestGuestVolumeUsageSamplesFilesystemAndPreservesInitialSize(t *testing.T) {
	for _, source := range []string{"cold", "warm", "seeded"} {
		t.Run(source, func(t *testing.T) {
			root := t.TempDir()
			if err := os.WriteFile(filepath.Join(root, "cache-source"), []byte(source), 0600); err != nil {
				t.Fatal(err)
			}
			body := fmt.Sprintf(`
STATUS_SHARE=%q
CACHE_MOUNT=%q
CACHE_ATTACHED_AT=2026-09-30T08:00:00Z
CACHE_ATTACH_MS=42
size=2
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/disk1 100 %%s 90 10%%%% /cache\n' "$size"; }
stage_volume_usage attach
size=7
stage_volume_usage teardown
`, root, root)
			cmd := exec.Command("bash", "-c", guestShellScript(t, body, "stage_volume_usage"))
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("%v: %s", err, output)
			}
			got := readVolumeUsage(root)
			if got == nil || got.AttachedSizeBytes != 2048 || got.SizeBytes != 7168 || got.CapacityBytes != 102400 || got.AttachMS != 42 || *got.Warm != (source != "cold") {
				t.Fatalf("usage: %+v", got)
			}
		})
	}
}

func TestVolumeUsageRejectsInvalidAndSymlinkedGuestReports(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "cache-usage.json")
	for _, data := range []string{`{}`, `{"attached_at":"2026-09-30T08:00:00Z","warm":true,"capacity_bytes":20,"size_bytes":21}`, `{"attached_at":"2026-09-30T08:00:00Z","warm":true,"capacity_bytes":20,"size_bytes":-1}`} {
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
		if got := readVolumeUsage(root); got != nil {
			t.Fatalf("accepted %s", data)
		}
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(t.TempDir(), "outside"), path); err != nil {
		t.Fatal(err)
	}
	if got := readVolumeUsage(root); got != nil {
		t.Fatal("followed symlink")
	}
}
