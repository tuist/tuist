package rackboot

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-logr/logr"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const (
	testNamespace = "tuist"
	hostUUID      = "44312e80-1dc6-11f1-853e-8f903547d200"
	bootMAC       = "38:05:25:38:b5:b5"
	otherNIC      = "38:05:25:38:b5:b4"
	strangerMAC   = "02:00:00:00:00:01"
	keyID         = "kAbC123"
)

var testNow = time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)

type harness struct {
	s         *Server
	c         client.Client
	neighbors map[string]string
	holds     bool
}

func newHarness(t *testing.T, objs ...client.Object) *harness {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).
		WithStatusSubresource(&infrav1.RackLinuxHost{}, &infrav1.RackLinuxCandidate{}).Build()
	h := &harness{c: c, neighbors: map[string]string{}}
	h.s = NewServer(Config{
		Address: "192.168.50.1", HTTPPort: 8480, Namespace: testNamespace, SecretName: "fleet-boot",
		Site: "ber1", Node: "ber1-edge-b", StateDir: t.TempDir(), NetbootDir: t.TempDir(),
	}, c, c, logr.Discard())
	h.s.Now = func() time.Time { return testNow }
	h.s.Neighbors = func(ip net.IP) (string, bool) {
		mac, ok := h.neighbors[ip.String()]
		return mac, ok
	}
	h.s.Holds = func() bool { return h.holds }
	return h
}

func publishedHost(key string) *infrav1.RackLinuxHost {
	pinned := metav1.NewTime(testNow.Add(-time.Hour))
	return &infrav1.RackLinuxHost{
		ObjectMeta: metav1.ObjectMeta{Name: hostUUID, Namespace: testNamespace},
		Spec:       infrav1.RackLinuxHostSpec{Hostname: "ber1-edge-a", Role: "edge"},
		Status: infrav1.RackLinuxHostStatus{
			BootMAC: bootMAC,
			Hardware: &infrav1.RackLinuxHostHardware{
				NICs:     []infrav1.RackLinuxCandidateNIC{{MAC: bootMAC, Driver: "igc", PCIDevice: "0x125b"}, {MAC: otherNIC, Driver: "igc", PCIDevice: "0x125c"}},
				BootMAC:  bootMAC,
				PinnedAt: &pinned,
			},
			Install: &infrav1.RackLinuxHostInstallStatus{KeyID: key, BootMAC: bootMAC},
		},
	}
}

func announcedCandidate() *infrav1.RackLinuxCandidate {
	return &infrav1.RackLinuxCandidate{
		ObjectMeta: metav1.ObjectMeta{Name: hostUUID, Namespace: testNamespace},
		Status: infrav1.RackLinuxCandidateStatus{
			UUID: hostUUID,
			NICs: []infrav1.RackLinuxCandidateNIC{{MAC: bootMAC, Driver: "igc", PCIDevice: "0x125b"}, {MAC: otherNIC, Driver: "igc", PCIDevice: "0x125c"}},
		},
	}
}

func bootSecretData(key string) map[string][]byte {
	return map[string][]byte{
		"38-05-25-38-b5-b5.ipxe":      []byte("#!ipxe\nkernel http://192.168.50.1:8480/ubuntu/vmlinuz\n"),
		"38-05-25-38-b5-b5.user-data": []byte("#cloud-config\n# tuist-install-id: " + key + "\n"),
		"38-05-25-38-b5-b5.meta-data": []byte("instance-id: ber1-edge-a-" + strings.ToLower(key) + "\n"),
		"38-05-25-38-b5-b5.uuid":      []byte(hostUUID),
		"38-05-25-38-b5-b5.install":   []byte(key),
	}
}

func (h *harness) get(t *testing.T, path, from string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.RemoteAddr = from + ":40000"
	rec := httptest.NewRecorder()
	h.s.Handler().ServeHTTP(rec, req)
	return rec
}

func (h *harness) host(t *testing.T) *infrav1.RackLinuxHost {
	t.Helper()
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, host); err != nil {
		t.Fatal(err)
	}
	return host
}

func TestOnlyACompleteInstallIsServed(t *testing.T) {
	data := bootSecretData(keyID)
	data["aa-bb-cc-dd-ee-ff.ipxe"] = []byte("#!ipxe\n")
	data["aa-bb-cc-dd-ee-ff.user-data"] = []byte("#cloud-config\n")
	data["aa-bb-cc-dd-ee-ff.meta-data"] = []byte("instance-id: x\n")
	data["aa-bb-cc-dd-ee-ff.uuid"] = []byte(hostUUID)
	data["not-a-mac.ipxe"] = []byte("#!ipxe\n")

	installs := ParseInstalls(data)
	if len(installs) != 1 {
		t.Fatalf("installs %v, want only the one with its join key's ID", installs)
	}
	inst := installs["38-05-25-38-b5-b5"]
	if inst.UUID != hostUUID || inst.KeyID != keyID {
		t.Fatalf("install %+v", inst)
	}
}

func TestAHostsBootScriptIsServedByItsMACAndItsUUID(t *testing.T) {
	h := newHarness(t)
	h.s.SetInstalls(bootSecretData(keyID))

	for _, path := range []string{"/hosts/38-05-25-38-b5-b5.ipxe", "/hosts/" + hostUUID + ".ipxe", "/hosts/" + strings.ToUpper(hostUUID) + ".ipxe"} {
		rec := h.get(t, path, "192.168.50.102")
		if rec.Code != http.StatusOK || !strings.HasPrefix(rec.Body.String(), "#!ipxe\nkernel") {
			t.Fatalf("%s: %d %q", path, rec.Code, rec.Body.String())
		}
	}
	for _, path := range []string{"/hosts/aa-bb-cc-dd-ee-ff.ipxe", "/hosts/04450c00-63f4-11f1-81f4-3582298d5c00.ipxe", "/hosts/nothing.ipxe", "/hosts/38-05-25-38-b5-b5"} {
		if rec := h.get(t, path, "192.168.50.102"); rec.Code != http.StatusNotFound {
			t.Fatalf("%s: %d, want 404", path, rec.Code)
		}
	}

	h.s.SetInstalls(nil)
	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5.ipxe", "192.168.50.102"); rec.Code != http.StatusNotFound {
		t.Fatalf("a withdrawn install is still served: %d", rec.Code)
	}
}

func TestTheSeedGoesOnlyToTheHostsNICsAndThenOnlyToTheFirstThatAsked(t *testing.T) {
	h := newHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	h.neighbors["192.168.50.102"] = otherNIC
	h.neighbors["192.168.50.103"] = strangerMAC
	h.neighbors["192.168.50.104"] = bootMAC

	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.200"); rec.Code != http.StatusForbidden {
		t.Fatalf("an address with no neighbor entry got the seed: %d", rec.Code)
	}
	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.103"); rec.Code != http.StatusForbidden {
		t.Fatalf("a MAC that is not the host's got the seed: %d", rec.Code)
	}
	if boot := h.host(t).Status.Boot; boot != nil {
		t.Fatalf("a refused request recorded %+v", boot)
	}

	rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.102")
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "tuist-install-id: "+keyID) {
		t.Fatalf("the host's own NIC was refused: %d %q", rec.Code, rec.Body.String())
	}
	boot := h.host(t).Status.Boot
	if boot == nil || boot.KeyID != keyID || boot.ServedTo != otherNIC || boot.ServedAddress != "192.168.50.102" ||
		boot.ServedAt == nil {
		t.Fatalf("status.boot %+v", boot)
	}

	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.102"); rec.Code != http.StatusOK {
		t.Fatalf("the NIC the seed went to cannot ask again: %d", rec.Code)
	}
	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.104"); rec.Code != http.StatusForbidden {
		t.Fatalf("another of the host's NICs got a seed already handed out: %d", rec.Code)
	}
	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/meta-data", "192.168.50.103"); rec.Code != http.StatusOK {
		t.Fatalf("meta-data carries nothing secret, yet was refused: %d", rec.Code)
	}
}

func TestTheSeedOfAnInstallTheHostNoLongerCarriesIsNotHandedOut(t *testing.T) {
	h := newHarness(t, publishedHost("kNewer1"))
	h.s.SetInstalls(bootSecretData(keyID))
	h.neighbors["192.168.50.104"] = bootMAC

	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.104"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("a superseded install's seed was handed out: %d", rec.Code)
	}
	if boot := h.host(t).Status.Boot; boot != nil {
		t.Fatalf("recorded %+v for a superseded install", boot)
	}
}

// peer is another edge's boot server of the same site, over the same API.
func (h *harness) peer(node string, holds func() bool) *Server {
	cfg := h.s.cfg
	cfg.Node = node
	s := NewServer(cfg, h.c, h.c, logr.Discard())
	s.Now = h.s.Now
	s.Holds = holds
	return s
}

func servers(boot *infrav1.RackLinuxHostBootStatus) map[string]bool {
	out := map[string]bool{}
	if boot != nil {
		for _, s := range boot.Servers {
			out[s.Node] = s.HoldsAddress
		}
	}
	return out
}

// Every edge's boot server reports the installs it holds, holding the
// provisioning address or not: the operator reboots an edge into its install
// only once another edge, which takes the address over, holds it.
func TestEveryReadyBootServerReportsTheInstallsItHolds(t *testing.T) {
	h := newHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	h.s.ready.Store(true)

	h.s.Acknowledge(context.Background())
	host := h.host(t)
	if got := servers(host.Status.Boot); host.Status.Boot.KeyID != keyID || len(got) != 1 || got["ber1-edge-b"] {
		t.Fatalf("status.boot %+v, want ber1-edge-b's report, not holding the address", host.Status.Boot)
	}
	version := host.ResourceVersion
	h.s.Acknowledge(context.Background())
	if h.host(t).ResourceVersion != version {
		t.Fatal("reported the same install twice")
	}

	h.holds = true
	h.s.Acknowledge(context.Background())
	if got := servers(h.host(t).Status.Boot); len(got) != 1 || !got["ber1-edge-b"] {
		t.Fatalf("servers %v, want ber1-edge-b reported again once it holds the address", got)
	}

	peer := h.peer("ber1-edge-a", func() bool { return false })
	peer.SetInstalls(bootSecretData(keyID))
	peer.ready.Store(true)
	peer.Acknowledge(context.Background())
	boot := h.host(t).Status.Boot
	if got := servers(boot); len(got) != 2 || !got["ber1-edge-b"] || got["ber1-edge-a"] || boot.ServedTo != "" {
		t.Fatalf("status.boot %+v, want both edges' reports", boot)
	}
}

func TestAHandOutKeepsTheBootServersReports(t *testing.T) {
	h := newHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	h.s.ready.Store(true)
	h.holds = true
	h.s.Acknowledge(context.Background())
	h.neighbors["192.168.50.104"] = bootMAC

	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.104"); rec.Code != http.StatusOK {
		t.Fatalf("%d %q", rec.Code, rec.Body.String())
	}
	boot := h.host(t).Status.Boot
	if got := servers(boot); len(got) != 1 || !got["ber1-edge-b"] || boot.ServedTo != bootMAC {
		t.Fatalf("status.boot %+v", boot)
	}
}

func TestAnInstallIsNotReportedServableBeforeTheISOIsReady(t *testing.T) {
	h := newHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	h.holds = true

	h.s.Acknowledge(context.Background())
	if boot := h.host(t).Status.Boot; boot != nil {
		t.Fatalf("reported %+v with nothing to boot it with", boot)
	}
}

func (h *harness) announce(t *testing.T, body, from string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/cgi-bin/announce", strings.NewReader(body))
	req.RemoteAddr = from + ":40000"
	rec := httptest.NewRecorder()
	h.s.Handler().ServeHTTP(rec, req)
	return rec
}

const announcement = "uuid=" + hostUUID + "\nserial=PW1234\nproduct=Micro Computer (HK) Tech Limited Venus Series\n" +
	"nic=38:05:25:38:b5:b4 igc 0x125c\nnic=38:05:25:38:b5:b5 igc 0x125b\nnic=58:47:ca:70:00:01 i40e 0x1572\n"

func TestAnAnnouncementListsTheMachineAsACandidate(t *testing.T) {
	h := newHarness(t)
	if rec := h.announce(t, announcement, "192.168.50.120"); rec.Code != http.StatusOK {
		t.Fatalf("%d %q", rec.Code, rec.Body.String())
	}
	cand := &infrav1.RackLinuxCandidate{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, cand); err != nil {
		t.Fatal(err)
	}
	st := cand.Status
	if st.UUID != hostUUID || st.Serial != "PW1234" || st.Product != "Micro Computer (HK) Tech Limited Venus Series" ||
		len(st.NICs) != 3 || st.BootMAC != bootMAC || st.Site != "ber1" || st.SeenBy != "ber1-edge-b" ||
		st.Address != "192.168.50.120" || st.FirstSeen == nil || st.LastSeen == nil {
		t.Fatalf("status %+v", st)
	}

	cand.Status.DeclaredAs = "ber1-edge-a"
	if err := h.c.Status().Update(context.Background(), cand); err != nil {
		t.Fatal(err)
	}
	h.s.Now = func() time.Time { return testNow.Add(10 * time.Minute) }
	if rec := h.announce(t, announcement, "192.168.50.121"); rec.Code != http.StatusOK {
		t.Fatalf("%d", rec.Code)
	}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, cand); err != nil {
		t.Fatal(err)
	}
	if cand.Status.DeclaredAs != "ber1-edge-a" || !cand.Status.FirstSeen.Time.Equal(testNow) ||
		!cand.Status.LastSeen.Time.Equal(testNow.Add(10*time.Minute)) || cand.Status.Address != "192.168.50.121" {
		t.Fatalf("status after a second announcement %+v", cand.Status)
	}
}

// Anyone on the segment can announce, so an announcement under a machine's
// UUID that does not match what it first announced changes nothing but the
// candidate's conflict, and gets a stranger's MAC no seed.
func TestAnAnnouncementCannotChangeWhatAMachineFirstAnnounced(t *testing.T) {
	h := newHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	if rec := h.announce(t, announcement, "192.168.50.120"); rec.Code != http.StatusOK {
		t.Fatalf("%d %q", rec.Code, rec.Body.String())
	}

	h.s.Now = func() time.Time { return testNow.Add(time.Minute) }
	for name, forged := range map[string]string{
		"a stranger's NIC added": announcement + "nic=" + strangerMAC + " igc 0x125b\n",
		"a NIC swapped":          strings.Replace(announcement, "38:05:25:38:b5:b4", strangerMAC, 1),
		"another serial":         strings.Replace(announcement, "serial=PW1234", "serial=PW9999", 1),
	} {
		if rec := h.announce(t, forged, "192.168.50.103"); rec.Code != http.StatusConflict {
			t.Fatalf("%s: %d, want 409", name, rec.Code)
		}
		cand := &infrav1.RackLinuxCandidate{}
		if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, cand); err != nil {
			t.Fatal(err)
		}
		st := cand.Status
		if len(st.NICs) != 3 || st.BootMAC != bootMAC || st.Serial != "PW1234" || st.Address != "192.168.50.120" || !st.LastSeen.Time.Equal(testNow) {
			t.Fatalf("%s: changed what the machine announced: %+v", name, st)
		}
		if c := st.Conflict; c == nil || c.Address != "192.168.50.103" || c.SeenBy != "ber1-edge-b" || c.Reason == "" {
			t.Fatalf("%s: conflict %+v", name, c)
		}
	}

	h.neighbors["192.168.50.103"] = strangerMAC
	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.103"); rec.Code != http.StatusForbidden {
		t.Fatalf("the forged announcement's MAC got the seed: %d", rec.Code)
	}

	h.s.Now = func() time.Time { return testNow.Add(10 * time.Minute) }
	reordered := "uuid=" + hostUUID + "\nserial=PW1234\nproduct=Micro Computer (HK) Tech Limited Venus Series\n" +
		"nic=58:47:ca:70:00:01 i40e 0x1572\nnic=38:05:25:38:b5:b5 igc 0x125b\nnic=38:05:25:38:b5:b4 igc 0x125c\n"
	if rec := h.announce(t, reordered, "192.168.50.121"); rec.Code != http.StatusOK {
		t.Fatalf("the machine announcing itself again, NICs in another order: %d", rec.Code)
	}
}

// The seed goes only to the NICs the host took from its candidate, whatever
// the candidate lists since.
func TestTheSeedGoesOnlyToTheNICsPinnedOnTheHost(t *testing.T) {
	tampered := announcedCandidate()
	tampered.Status.NICs = append(tampered.Status.NICs, infrav1.RackLinuxCandidateNIC{MAC: strangerMAC, Driver: "igc", PCIDevice: "0x125b"})
	h := newHarness(t, publishedHost(keyID), tampered)
	h.s.SetInstalls(bootSecretData(keyID))
	h.neighbors["192.168.50.103"] = strangerMAC

	if rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.103"); rec.Code != http.StatusForbidden {
		t.Fatalf("a MAC only the candidate lists got the seed: %d", rec.Code)
	}
}

func TestAnAnnouncementThatIsNotExactlyTheExpectedLinesIsRefused(t *testing.T) {
	for name, body := range map[string]string{
		"no uuid":          "nic=38:05:25:38:b5:b5 igc 0x125b\n",
		"two uuids":        "uuid=" + hostUUID + "\nuuid=" + hostUUID + "\nnic=38:05:25:38:b5:b5 igc 0x125b\n",
		"no NIC":           "uuid=" + hostUUID + "\n",
		"unknown line":     announcement + "shell=$(reboot)\n",
		"upper UUID":       "uuid=" + strings.ToUpper(hostUUID) + "\nnic=38:05:25:38:b5:b5 igc 0x125b\n",
		"odd serial":       "uuid=" + hostUUID + "\nserial=a b\nnic=38:05:25:38:b5:b5 igc 0x125b\n",
		"too many NICs":    "uuid=" + hostUUID + "\n" + strings.Repeat("nic=38:05:25:38:b5:b5 igc 0x125b\n", 17),
		"an EK not base64": announcement + "ek=not base64\n",
		"an EK not a key":  announcement + "ek=" + base64.StdEncoding.EncodeToString([]byte("not a key")) + "\n",
		"two EKs":          announcement + "ek=" + testEK + "\nek=" + testEK + "\n",
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			if rec := h.announce(t, body, "192.168.50.120"); rec.Code != http.StatusBadRequest {
				t.Fatalf("%d, want 400", rec.Code)
			}
		})
	}
	h := newHarness(t)
	if rec := h.announce(t, announcement+strings.Repeat("x", MaxAnnouncementBytes), "192.168.50.120"); rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("an oversized announcement: %d", rec.Code)
	}
}

func TestTheBootServersListAtMost256Machines(t *testing.T) {
	var objs []client.Object
	for i := range MaxCandidates {
		objs = append(objs, &infrav1.RackLinuxCandidate{ObjectMeta: metav1.ObjectMeta{
			Name: fmt.Sprintf("%08x-0000-0000-0000-000000000000", i), Namespace: testNamespace}})
	}
	h := newHarness(t, objs...)
	if rec := h.announce(t, announcement, "192.168.50.120"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("a 257th machine: %d, want 429", rec.Code)
	}
	known := strings.Replace(announcement, hostUUID, objs[0].GetName(), 1)
	if rec := h.announce(t, known, "192.168.50.120"); rec.Code != http.StatusOK {
		t.Fatalf("a machine already listed: %d", rec.Code)
	}
}

type fakeTransfer struct {
	bytes.Buffer
	size int64
}

func (f *fakeTransfer) SetSize(n int64)                     { f.size = n }
func (f *fakeTransfer) RemoteAddr() net.UDPAddr             { return net.UDPAddr{} }
func (f *fakeTransfer) ReadFrom(r io.Reader) (int64, error) { return f.Buffer.ReadFrom(r) }

func TestTFTPServesTheSignedIPXEAndTheBootScriptOnly(t *testing.T) {
	h := newHarness(t)
	for _, name := range []string{IPXEShim, IPXE} {
		if err := os.WriteFile(filepath.Join(h.s.cfg.NetbootDir, name), []byte(name+" signed"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for name, want := range map[string]string{
		IPXEShim:    IPXEShim + " signed",
		"/" + IPXE:  IPXE + " signed",
		"boot.ipxe": "#!ipxe\nchain http://192.168.50.1:8480/hosts/${mac:hexhyp}.ipxe || chain http://192.168.50.1:8480/hosts/${uuid}.ipxe || exit 1\n",
	} {
		rf := &fakeTransfer{}
		if err := h.s.TFTPRead(name, rf); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if rf.String() != want || rf.size != int64(len(want)) {
			t.Fatalf("%s: %q (size %d)", name, rf.String(), rf.size)
		}
	}
	for _, name := range []string{"../etc/passwd", "hosts/38-05-25-38-b5-b5.ipxe", "grubx64.efi"} {
		if err := h.s.TFTPRead(name, &fakeTransfer{}); err == nil {
			t.Fatalf("%s was served", name)
		}
	}
}

func TestANeighborIsLookedUpOnlyOnceResolved(t *testing.T) {
	table := `IP address       HW type     Flags       HW address            Mask     Device
192.168.50.102   0x1         0x2         38:05:25:38:b5:b5     *        enp87s0
192.168.50.103   0x1         0x0         00:00:00:00:00:00     *        enp87s0
`
	if mac, ok := lookupNeighbor(strings.NewReader(table), net.ParseIP("192.168.50.102")); !ok || mac != bootMAC {
		t.Fatalf("%q %v", mac, ok)
	}
	for _, ip := range []string{"192.168.50.103", "192.168.50.104"} {
		if _, ok := lookupNeighbor(strings.NewReader(table), net.ParseIP(ip)); ok {
			t.Fatalf("%s resolved", ip)
		}
	}
}
