package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	saved := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", BaseGeneration: 1, VolumeBytes: 30_000_000_000, HeadSizeBytes: 10_000_000_000}}
	cold := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "22222222-2222-4222-8222-222222222222", VolumeBytes: 30_000_000_000}}
	prefetch := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: cachevolumes.PrefetchReservation, BaseGeneration: 1, VolumeBytes: 30_000_000_000}}
	c.reservations[saved.ID] = saved
	c.reservations[cold.ID] = cold
	c.reservations[prefetch.ID] = prefetch

	// A job holds what it is expected to write; a prefetch holds an archive beside
	// the expanded image.
	if got, want := c.reservedBytes(), uint64(15_000_000_000+5_000_000_000+2*30_000_000_000); got != want {
		t.Fatalf("reserved %d bytes, want %d", got, want)
	}
}

func TestCustomAdmissionScalesWithTheVolumeAndItsHead(t *testing.T) {
	for _, tc := range []struct {
		name string
		slot cachevolumes.Identity
		want uint64
	}{
		{"cold 3 GB", cachevolumes.Identity{VolumeBytes: 3_000_000_000}, 3_000_000_000},
		{"cold 100 GB", cachevolumes.Identity{VolumeBytes: 100_000_000_000}, cachevolumes.UnmeasuredVolumeBytes},
		{"cold without a size", cachevolumes.Identity{}, cachevolumes.UnmeasuredVolumeBytes},
		{"warm with a small head", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 20_000_000_000, HeadSizeBytes: 700_000_000}, 2_700_000_000},
		{"warm with a large head", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 50_000_000_000, HeadSizeBytes: 30_000_000_000}, 45_000_000_000},
		{"warm with a head near the capacity", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 50_000_000_000, HeadSizeBytes: 40_000_000_000}, 50_000_000_000},
		{"warm with an unknown head", cachevolumes.Identity{BaseGeneration: 1, VolumeBytes: 50_000_000_000}, cachevolumes.UnmeasuredVolumeBytes},
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

// expectedAPFS wires runner-cache's attach admission to this host's custom
// reservation, as startCustomVolumes does, on a cache filesystem with free bytes.
func expectedAPFS(t *testing.T, free uint64) (*CustomVolumes, *cachevolumes.APFSImages) {
	t.Helper()
	m, be := m2L(t)
	be.totalBytes, be.perMaster = free, 0
	c := &CustomVolumes{Root: filepath.Join(m.Root, "custom"), Builtins: m}
	b := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{
		Root: c.Root, SizeGB: 20, MinFreeBytes: 40_000_000_000, FreeBytesContext: c.freeBytesContext,
	}, Reserve: c.reserve, Create: func(_ context.Context, path string, _ int64) error {
		return os.WriteFile(path, nil, 0600)
	}}
	if err := b.Init(); err != nil {
		t.Fatal(err)
	}
	return c, b
}

func expectedAttach(t *testing.T, b *cachevolumes.APFSImages, slot cachevolumes.Slot) error {
	t.Helper()
	path := filepath.Join(b.Root, "pods", slot.PodUID, slot.Scope)
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatal(err)
	}
	return b.Attach(context.Background(), slot, path)
}

func expectedSlot(id string, volume, head int64) cachevolumes.Slot {
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: id, Account: 1, Scope: strings.Repeat("a", 64), VolumeBytes: volume, HeadSizeBytes: head}, PodUID: "pod"}
	if head > 0 {
		slot.BaseGeneration, slot.ImageDigest, slot.ContentDigest = 1, strings.Repeat("b", 40), strings.Repeat("c", 64)
	}
	return slot
}

// runner-cache admits before calling Reserve; if either asks for other than the
// shared rule, a job is refused with room for it or admitted without.
func TestHostAndCustomAdmissionAgreeOnWhatAJobNeeds(t *testing.T) {
	for _, tc := range []struct {
		name         string
		volume, head int64
	}{
		{"unmeasured", 20_000_000_000, 0},
		{"unmeasured without a size", 0, 0},
		{"small head", 20_000_000_000, 700_000_000},
		{"large head", 30_000_000_000, 15_000_000_000},
		{"head near the capacity", 20_000_000_000, 19_000_000_000},
	} {
		t.Run(tc.name, func(t *testing.T) {
			slot := expectedSlot("11111111-1111-4111-8111-111111111111", tc.volume, tc.head)
			need := uint64(slot.ExpectedBytes(customCapacity))
			for free, fits := range map[uint64]bool{need: true, need - 1: false} {
				for subject, admit := range map[string]func(*CustomVolumes, *cachevolumes.APFSImages) error{
					"runner-cache": func(_ *CustomVolumes, b *cachevolumes.APFSImages) error {
						b.Reserve = nil
						return expectedAttach(t, b, slot)
					},
					"custom admission": func(c *CustomVolumes, _ *cachevolumes.APFSImages) error {
						_, err := c.reserve(context.Background(), slot)
						return err
					},
					"both": func(_ *CustomVolumes, b *cachevolumes.APFSImages) error { return expectedAttach(t, b, slot) },
				} {
					err := admit(expectedAPFS(t, free))
					if fits && err != nil {
						t.Errorf("%s refused with the expected %d bytes free: %v", subject, free, err)
					}
					if !fits && !errors.Is(err, cachevolumes.ErrCapacity) {
						t.Errorf("%s admitted with %d bytes free, one less than expected: %v", subject, free, err)
					}
				}
			}
		})
	}
}

// One job's six volumes: four small custom ones at the default 20 GB capacity
// and the managed Xcode and module caches. Reserving every capacity took 130 GB.
func TestAJobsSmallVolumesFitBesideEachOther(t *testing.T) {
	c, b := expectedAPFS(t, 45_000_000_000)
	for i, head := range []struct{ volume, used int64 }{
		{20_000_000_000, 700_000_000},
		{20_000_000_000, 100_000_000},
		{20_000_000_000, 4_600_000_000},
		{20_000_000_000, 100_000_000},
		{30_000_000_000, 15_000_000_000},
		{20_000_000_000, 2_800_000_000},
	} {
		slot := expectedSlot(fmt.Sprintf("%08d-1111-4111-8111-111111111111", i), head.volume, head.used)
		slot.Scope = strings.Repeat(string(rune('a'+i)), 64)
		if err := expectedAttach(t, b, slot); err != nil {
			t.Fatalf("volume %d refused with %d bytes reserved: %v", i, c.reservedBytes(), err)
		}
	}
	if got, want := c.reservedBytes(), uint64(41_100_000_000); got != want {
		t.Fatalf("reserved %d bytes for the running job, want %d", got, want)
	}
}

// A running VM's copy is reserved up to what the job is expected to write, less
// what it already holds.
func TestARunningCopyReservesItsRemainingExpectedGrowth(t *testing.T) {
	m, be := m2L(t)
	be.perMaster = 1_000_000_000
	c := &CustomVolumes{Root: t.TempDir(), Builtins: m, reservations: map[string]cachevolumes.Slot{}}
	slot := expectedSlot("11111111-1111-4111-8111-111111111111", 20_000_000_000, 700_000_000)
	slot.State = "active"
	c.reservations[slot.ID] = slot
	image := filepath.Join(c.Root, "images", slot.ID+".img")
	if err := os.MkdirAll(filepath.Dir(image), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(image, nil, 0600); err != nil {
		t.Fatal(err)
	}

	if got, want := c.reservedBytes(), uint64(2_700_000_000-1_000_000_000); got != want {
		t.Fatalf("reserved %d bytes, want %d", got, want)
	}
	be.perMaster = 3_000_000_000
	if got := c.reservedBytes(); got != 0 {
		t.Fatalf("a copy past its expected size still reserved %d bytes", got)
	}
}
