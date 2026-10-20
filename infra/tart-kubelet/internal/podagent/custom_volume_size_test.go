package podagent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestCustomReservationsFollowTheAllocatedVolumeSize(t *testing.T) {
	m, _ := m2L(t)
	c := &CustomVolumes{Builtins: m, reservations: map[string]cachevolumes.Slot{}}
	restoring := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", BaseGeneration: 1, VolumeBytes: 30_000_000_000}}
	cold := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "22222222-2222-4222-8222-222222222222", VolumeBytes: 30_000_000_000}}
	c.reservations[restoring.ID] = restoring
	c.reservations[cold.ID] = cold

	// A restore holds an archive beside the expanded image; a cold volume holds the image.
	if got, want := c.reservedBytes(), uint64(2*30_000_000_000+30_000_000_000); got != want {
		t.Fatalf("reserved %d bytes, want %d", got, want)
	}
}

func TestCustomAdmissionScalesWithTheVolumeAndItsHead(t *testing.T) {
	for _, tc := range []struct {
		name string
		slot cachevolumes.Identity
		want uint64
	}{
		{"cold 5 GB", cachevolumes.Identity{VolumeBytes: 5_000_000_000}, 5_000_000_000},
		{"cold 100 GB", cachevolumes.Identity{VolumeBytes: 100_000_000_000}, 100_000_000_000},
		{"cold without a size", cachevolumes.Identity{}, customCapacity},
		{"warm with a small head", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 50_000_000_000, HeadSizeBytes: 4_000_000_000}, 50_000_000_000},
		{"warm with a large head", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 50_000_000_000, HeadSizeBytes: 40_000_000_000}, 80_000_000_000},
		{"warm with an unknown head", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 50_000_000_000}, 100_000_000_000},
		{"prefetch of a known head", cachevolumes.Identity{ID: cachevolumes.PrefetchReservation, BaseGeneration: 1, VolumeBytes: 100_000_000_000, HeadSizeBytes: 10_000_000_000}, 20_000_000_000},
		{"prefetch of an unknown head", cachevolumes.Identity{ID: cachevolumes.PrefetchReservation, BaseGeneration: 1, VolumeBytes: 30_000_000_000}, 60_000_000_000},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := customAdmissionBytes(cachevolumes.Slot{Identity: tc.slot}); got != tc.want {
				t.Fatalf("admission needs %d bytes, want %d", got, tc.want)
			}
		})
	}
}

// sizedMailbox serves one guest request and records the authorization body.
func sizedMailbox(t *testing.T, request string) (*CustomVolumes, *corev1.Pod, *map[string]any) {
	t.Helper()
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "job", Namespace: "runners", UID: "job-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(share, "cache.request"), []byte(request), 0600); err != nil {
		t.Fatal(err)
	}
	sent := &map[string]any{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(sent)
		_ = json.NewEncoder(w).Encode(cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Account: 1, Scope: strings.Repeat("a", 64), VolumeBytes: 50_000_000_000})
	}))
	t.Cleanup(server.Close)
	store, err := cachevolumes.Open(root, &slowCustomBackend{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	store.MaxVolumeBytes = 100_000_000_000
	c := &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host", Namespace: "runners", Store: store, MaxVolumeBytes: 100_000_000_000,
		tokenValue: "token", tokenUntil: time.Now().Add(time.Hour)}
	return c, pod, sent
}

func TestCustomMailboxForwardsTheRequestedSizeAndTheHostMaximum(t *testing.T) {
	c, pod, sent := sizedMailbox(t, `{"key":"deps","uid":501,"requested_volume_bytes":50000000000}`)

	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}

	if (*sent)["requested_volume_bytes"] != float64(50_000_000_000) || (*sent)["max_volume_bytes"] != float64(100_000_000_000) {
		t.Fatalf("authorized with %v", *sent)
	}
	if response := readCustomResponse(t, filepath.Join(c.Root, "pods", string(pod.UID), "cache.request.response")); response["id"] == nil {
		t.Fatal("a 50 GB volume was not attached:", response)
	}
}

func TestCustomMailboxDropsAnInvalidRequestedSize(t *testing.T) {
	for _, requested := range []string{`0`, `-1`, `2500000000`, `101000000000`, `"50gb"`} {
		c, pod, sent := sizedMailbox(t, `{"key":"deps","uid":501,"requested_volume_bytes":`+requested+`}`)

		if err := c.requests(context.Background(), pod); err != nil {
			t.Fatal(err)
		}

		if _, ok := (*sent)["requested_volume_bytes"]; ok || (*sent)["max_volume_bytes"] != float64(100_000_000_000) {
			t.Fatalf("size %s authorized with %v", requested, *sent)
		}
	}
}

func TestCustomHostMaximumDefaultsToTheSharedDefault(t *testing.T) {
	if got := (&CustomVolumes{}).maxVolumeBytes(); got != cachevolumes.DefaultMaxVolumeBytes {
		t.Fatal(got)
	}
}
