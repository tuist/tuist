package linux

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

const ms01UUID = "44312e80-1dc6-11f1-853e-8f903547d200"

var discoveryEpoch = time.Date(2026, 9, 25, 10, 0, 0, 0, time.UTC)

// ms01Announcement is what the boot server records for an MS-01 whose stick
// found nothing published, seen at the given time.
func ms01Announcement(seen time.Time) string {
	return fmt.Sprintf(`--- %[1]s
uuid=%[1]s
serial=MD148LS139QQMQE00070
product=Micro Computer (HK) Tech Limited Venus Series
nic=38:05:25:38:b5:b2 i40e 0x1572
nic=38:05:25:38:b5:b4 igc 0x125c
nic=38:05:25:38:b5:b5 igc 0x125b
from=192.168.50.144
seen=%[2]d
`, ms01UUID, seen.Unix())
}

type discoveryHarness struct {
	d      *RackLinuxDiscovery
	c      client.Client
	runner *fakeRunner
	now    time.Time
}

// newDiscoveryHarness has the edges answer with what their boot servers
// recorded, by the address the operator dials them at.
func newDiscoveryHarness(t *testing.T, recorded map[string]string, objs ...runtime.Object) *discoveryHarness {
	t.Helper()
	objs = append(objs, &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-ssh", Namespace: rackTestNamespace},
		Data:       map[string][]byte{"id_ed25519": testFleetPrivateKey(t)},
	})
	c := fake.NewClientBuilder().WithScheme(rackTestScheme(t)).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackLinuxHost{}, &infrav1.RackLinuxCandidate{}).Build()
	h := &discoveryHarness{c: c, runner: &fakeRunner{reply: func(host, _ string) string { return recorded[host] }}, now: discoveryEpoch}
	h.d = &RackLinuxDiscovery{
		Client:             c,
		CredentialsManager: &credentials.Manager{Client: c, Namespace: rackTestNamespace},
		FleetName:          rackTestFleet,
		RunScript:          h.runner.run,
		Now:                func() time.Time { return h.now },
	}
	return h
}

func connectedEdge(name, device, address string) *infrav1.RackLinuxHost {
	h := edgeHost()
	h.Name = name
	h.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: device, Address: address, Connected: true}
	return h
}

func (h *discoveryHarness) candidate(t *testing.T) *infrav1.RackLinuxCandidate {
	t.Helper()
	cand := &infrav1.RackLinuxCandidate{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: ms01UUID}, cand); err != nil {
		t.Fatalf("candidate: %v", err)
	}
	return cand
}

// A machine whose stick announced itself is listed with the bootMAC to
// declare, its i226-LM, and where it was heard.
func TestRackLinuxDiscoveryListsAnAnnouncedMachine(t *testing.T) {
	seen := discoveryEpoch.Add(-time.Minute)
	h := newDiscoveryHarness(t, map[string]string{"100.64.0.7": ms01Announcement(seen)},
		connectedEdge("ber1-edge-a", "dev-a", "100.64.0.7"))
	if err := h.d.scan(context.Background()); err != nil {
		t.Fatal(err)
	}
	s := h.candidate(t).Status
	if s.UUID != ms01UUID || s.Serial != "MD148LS139QQMQE00070" || s.Product != "Micro Computer (HK) Tech Limited Venus Series" {
		t.Fatalf("identity %+v", s)
	}
	if s.BootMAC != "38:05:25:38:b5:b5" || len(s.NICs) != 3 || s.NICs[1] != (infrav1.RackLinuxCandidateNIC{MAC: "38:05:25:38:b5:b4", Driver: "igc", PCIDevice: "0x125c"}) {
		t.Fatalf("bootMAC %q nics %+v", s.BootMAC, s.NICs)
	}
	if s.Site != "ber1" || s.SeenBy != "ber1-edge-a" || s.Address != "192.168.50.144" || s.DeclaredAs != "" {
		t.Fatalf("seen %+v", s)
	}
	if s.FirstSeen == nil || !s.FirstSeen.Time.Equal(seen) || s.LastSeen == nil || !s.LastSeen.Time.Equal(seen) {
		t.Fatalf("first %v last %v, want %v", s.FirstSeen, s.LastSeen, seen)
	}
	if len(h.runner.runs) != 1 || !strings.Contains(h.runner.runs[0].script, "/var/lib/tuist-rack-boot/announced") {
		t.Fatalf("runs %+v", h.runner.runs)
	}
}

// A machine that a host already declares by one of its MACs is marked with
// that host.
func TestRackLinuxDiscoveryMarksADeclaredMachine(t *testing.T) {
	declared := edgeHost()
	declared.Name = "ber1-store-a"
	declared.Spec.Role = "storage"
	declared.Spec.BootMAC = "38:05:25:38:B5:B5"
	h := newDiscoveryHarness(t, map[string]string{"100.64.0.7": ms01Announcement(discoveryEpoch)},
		connectedEdge("ber1-edge-a", "dev-a", "100.64.0.7"), declared)
	if err := h.d.scan(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := h.candidate(t).Status.DeclaredAs; got != "ber1-store-a" {
		t.Fatalf("declaredAs %q", got)
	}
}

func TestRackLinuxDiscoveryIgnoresWhatIsNotAnAnnouncement(t *testing.T) {
	for name, recorded := range map[string]string{
		"file named apart from its uuid": strings.Replace(ms01Announcement(discoveryEpoch), "--- "+ms01UUID, "--- 00000000-0000-0000-0000-000000000000", 1),
		"unexpected line":                ms01Announcement(discoveryEpoch) + "hostname=evil\n",
		"no NIC":                         "--- " + ms01UUID + "\nuuid=" + ms01UUID + "\nseen=1790330000\n",
		"no time":                        strings.Replace(ms01Announcement(discoveryEpoch), fmt.Sprintf("seen=%d\n", discoveryEpoch.Unix()), "", 1),
		"bad MAC":                        strings.Replace(ms01Announcement(discoveryEpoch), "38:05:25:38:b5:b5", "38:05:25:38:b5", 1),
	} {
		t.Run(name, func(t *testing.T) {
			h := newDiscoveryHarness(t, map[string]string{"100.64.0.7": recorded}, connectedEdge("ber1-edge-a", "dev-a", "100.64.0.7"))
			if err := h.d.scan(context.Background()); err != nil {
				t.Fatal(err)
			}
			list := &infrav1.RackLinuxCandidateList{}
			if err := h.c.List(context.Background(), list); err != nil {
				t.Fatal(err)
			}
			if len(list.Items) != 0 {
				t.Fatalf("listed %+v", list.Items[0].Status)
			}
		})
	}
}

// Only a connected edge runs a boot server whose announcements can be read.
func TestRackLinuxDiscoveryAsksOnlyConnectedEdges(t *testing.T) {
	offline := connectedEdge("ber1-edge-b", "dev-b", "100.64.0.8")
	offline.Status.Tailnet.Connected = false
	storage := connectedEdge("ber1-store-a", "dev-s", "100.64.0.9")
	storage.Spec.Role = "storage"
	h := newDiscoveryHarness(t, nil, offline, storage)
	if err := h.d.scan(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(h.runner.runs) != 0 {
		t.Fatalf("asked %+v", h.runner.runs)
	}
}

// Both edges can hold an announcement for the machine, one from before a
// failover; the newer one wins, and an older one never rolls it back.
func TestRackLinuxDiscoveryKeepsTheNewestAnnouncement(t *testing.T) {
	older, newer := discoveryEpoch.Add(-time.Hour), discoveryEpoch.Add(-time.Minute)
	h := newDiscoveryHarness(t, map[string]string{
		"100.64.0.7": ms01Announcement(older),
		"100.64.0.8": strings.Replace(ms01Announcement(newer), "from=192.168.50.144", "from=192.168.50.145", 1),
	}, connectedEdge("ber1-edge-a", "dev-a", "100.64.0.7"), connectedEdge("ber1-edge-b", "dev-b", "100.64.0.8"))
	for i := 0; i < 2; i++ {
		if err := h.d.scan(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	s := h.candidate(t).Status
	if !s.LastSeen.Time.Equal(newer) || s.SeenBy != "ber1-edge-b" || s.Address != "192.168.50.145" || !s.FirstSeen.Time.Equal(older) {
		t.Fatalf("status %+v", s)
	}
}

// A machine no edge has heard from for a week is gone from the list.
func TestRackLinuxDiscoveryDropsAMachineNotSeenForAWeek(t *testing.T) {
	stale := &infrav1.RackLinuxCandidate{
		ObjectMeta: metav1.ObjectMeta{Name: ms01UUID, Namespace: rackTestNamespace},
		Status:     infrav1.RackLinuxCandidateStatus{UUID: ms01UUID, LastSeen: &metav1.Time{Time: discoveryEpoch.Add(-8 * 24 * time.Hour)}},
	}
	h := newDiscoveryHarness(t, nil, connectedEdge("ber1-edge-a", "dev-a", "100.64.0.7"), stale)
	if err := h.d.scan(context.Background()); err != nil {
		t.Fatal(err)
	}
	err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: ms01UUID}, &infrav1.RackLinuxCandidate{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("stale candidate: %v", err)
	}
}
