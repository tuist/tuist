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
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func TestVolumeUsagePersistsRetriesAndHostIdentity(t *testing.T) {
	root := t.TempDir()
	warm := true
	usage := &volumeUsage{PodName: "guest-chosen", PodUID: "guest", VolumeName: "guest", AttachedAt: "2026-09-30T08:00:00Z", AttachMS: 42, AttachedSizeBytes: 1024, SizeBytes: 4096, CapacityBytes: 20000000000, Warm: &warm}
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
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("acknowledged report retained", err)
	}
	if attempts != 2 {
		t.Fatalf("attempts %d", attempts)
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

func TestVolumeUsageWaitsSilentlyForTheServerEndpoint(t *testing.T) {
	root := t.TempDir()
	warm := true
	usage := &volumeUsage{AttachedAt: "2026-09-30T08:00:00Z", CapacityBytes: 20000000000, Warm: &warm}
	entry := &Entry{PodName: "runner", PodUID: "runner-uid", Volume: VolumeAttachment{VolumeName: "tuist-cache"}}
	source := &ServerPrefetch{Client: fake.NewSimpleClientset(), token: "host-token", tokenExpiry: time.Now().Add(5 * time.Minute)}
	worker := NewConvergeWorker(&VolumeManager{Root: root, CapGiB: 28}, false, source)
	if err := worker.queueUsage(entry, usage, VolumeOutcomePromoted); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "usage-reports", "runner-uid.json")
	queuedAt := time.Now().Add(-time.Hour).Truncate(time.Second)
	if err := os.Chtimes(path, queuedAt, queuedAt); err != nil {
		t.Fatal(err)
	}

	logs := captureLogs(t)
	worker.reportUsage(context.Background())
	for _, line := range logs() {
		if strings.Contains(line, "report volume usage") {
			t.Fatalf("logged the not-yet-known endpoint as a failure: %q", line)
		}
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal("report dropped while the endpoint was unknown", err)
	}
	if !info.ModTime().Equal(queuedAt) {
		t.Fatalf("report requeued behind newer ones: mtime %v, want %v", info.ModTime(), queuedAt)
	}

	delivered := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delivered++
	}))
	defer server.Close()
	source.ObservePod(&corev1.Pod{Spec: corev1.PodSpec{Containers: []corev1.Container{{
		Env: []corev1.EnvVar{{Name: runnerDispatchURLEnv, Value: server.URL + runnerDispatchPath}},
	}}}})
	worker.reportUsage(context.Background())
	if _, err := os.Stat(path); !os.IsNotExist(err) || delivered != 1 {
		t.Fatalf("report not delivered once the endpoint was known: delivered=%d err=%v", delivered, err)
	}
}

func TestRecoveredRunnerPodTeachesTheServerEndpoint(t *testing.T) {
	source := &ServerPrefetch{}
	store := NewStore()
	// recoverState adopted this Pod's live VM, so createPod returns before
	// provisioning anything.
	store.Put("tuist-runners", "runner-0", &Entry{PodName: "runner-0", VMName: "runner-0"})
	r := &Reconciler{Store: store, Converge: NewConvergeWorker(&VolumeManager{}, false, source)}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-0"},
		Spec: corev1.PodSpec{Containers: []corev1.Container{{
			Env: []corev1.EnvVar{{Name: runnerDispatchURLEnv, Value: "https://tuist.example" + runnerDispatchPath}},
		}}},
	}
	if err := r.createPod(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if got, want := source.currentEndpoint(), "https://tuist.example"+cacheMastersPath; got != want {
		t.Fatalf("endpoint = %q, want %q", got, want)
	}
}
