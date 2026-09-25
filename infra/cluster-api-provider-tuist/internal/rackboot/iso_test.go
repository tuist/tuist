package rackboot

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/kdomanski/iso9660"
)

// testISO is an installer ISO with what netbooting needs from it.
func testISO(t *testing.T, kernel string) ([]byte, string) {
	t.Helper()
	w, err := iso9660.NewWriter()
	if err != nil {
		t.Fatal(err)
	}
	defer w.Cleanup()
	for path, content := range map[string]string{
		"casper/vmlinuz":       kernel,
		"casper/initrd":        "initrd\n",
		"EFI/boot/bootx64.efi": "shim\n",
		"README.diskdefines":   "ubuntu\n",
	} {
		if err := w.AddFile(strings.NewReader(content), path); err != nil {
			t.Fatal(err)
		}
	}
	var buf bytes.Buffer
	if err := w.WriteTo(&buf, "UBUNTU"); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(buf.Bytes())
	return buf.Bytes(), hex.EncodeToString(sum[:])
}

type isoOrigin struct {
	*httptest.Server
	requests atomic.Int32
}

func serveISO(t *testing.T, listen string, iso []byte, sha string) *isoOrigin {
	t.Helper()
	o := &isoOrigin{}
	l, err := net.Listen("tcp4", listen)
	if err != nil {
		t.Fatal(err)
	}
	o.Server = httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		o.requests.Add(1)
		switch r.URL.Path {
		case "/ubuntu.iso", "/releases/ubuntu.iso":
			_, _ = w.Write(iso)
		case "/ubuntu.iso.sha256":
			_, _ = io.WriteString(w, sha+"\n")
		default:
			http.NotFound(w, r)
		}
	}))
	o.Listener.Close()
	o.Listener = l
	o.Start()
	t.Cleanup(o.Close)
	return o
}

func isoHarness(t *testing.T, sha string) *harness {
	t.Helper()
	h := newHarness(t)
	h.s.cfg.ISOSHA256 = sha
	h.s.PeerNet = func() *net.IPNet { return nil }
	return h
}

func TestPrepareISOVerifiesTheISOAndServesItsInstaller(t *testing.T) {
	iso, sha := testISO(t, "kernel\n")
	origin := serveISO(t, "127.0.0.1:0", iso, sha)
	h := isoHarness(t, sha)
	h.s.cfg.ISOURL = origin.URL + "/releases/ubuntu.iso"
	stale := filepath.Join(h.s.cfg.StateDir, "http", "hosts", "38-05-25-38-b5-b5")
	if err := os.MkdirAll(stale, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := h.s.PrepareISO(context.Background()); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]string{"/ubuntu/vmlinuz": "kernel\n", "/ubuntu/initrd": "initrd\n", "/ubuntu/shimx64.efi": "shim\n"} {
		rec := h.get(t, path, "192.168.50.102")
		if rec.Code != http.StatusOK || rec.Body.String() != want {
			t.Fatalf("%s: %d %q", path, rec.Code, rec.Body.String())
		}
	}
	if rec := h.get(t, "/ubuntu/ubuntu.iso", "192.168.50.102"); rec.Code != http.StatusOK || rec.Body.Len() != len(iso) {
		t.Fatalf("the ISO: %d, %d bytes", rec.Code, rec.Body.Len())
	}
	if rec := h.get(t, "/ubuntu/README.diskdefines", "192.168.50.102"); rec.Code != http.StatusNotFound {
		t.Fatalf("served a file netbooting does not need: %d", rec.Code)
	}
	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Fatalf("an earlier boot server's seeds are still on disk: %v", err)
	}

	requests := origin.requests.Load()
	if err := h.s.PrepareISO(context.Background()); err != nil {
		t.Fatal(err)
	}
	if origin.requests.Load() != requests {
		t.Fatal("downloaded the ISO again although it was verified")
	}
}

func TestPrepareISORefusesAnISOThatDoesNotVerify(t *testing.T) {
	iso, _ := testISO(t, "kernel\n")
	_, other := testISO(t, "another kernel\n")
	origin := serveISO(t, "127.0.0.1:0", iso, other)
	h := isoHarness(t, other)
	h.s.cfg.ISOURL = origin.URL + "/releases/ubuntu.iso"

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := h.s.PrepareISO(ctx); err == nil {
		t.Fatal("prepared an ISO that does not match its checksum")
	}
	if _, err := os.Stat(filepath.Join(h.s.cfg.StateDir, "http", "ubuntu", "ubuntu.iso")); !os.IsNotExist(err) {
		t.Fatalf("kept the ISO: %v", err)
	}
	if rec := h.get(t, "/ubuntu/vmlinuz", "192.168.50.102"); rec.Code != http.StatusNotFound {
		t.Fatalf("serves a kernel: %d", rec.Code)
	}
}

// A fresh edge fetches the ISO from another edge over the edges' link. The
// test's link is 127.0.0.0/30, this edge 127.0.0.2 and the other 127.0.0.1.
func peerLink() *net.IPNet {
	return &net.IPNet{IP: net.IPv4(127, 0, 0, 2), Mask: net.CIDRMask(30, 32)}
}

func TestAFreshEdgeFetchesTheISOFromAnotherEdgeRatherThanTheInternet(t *testing.T) {
	iso, sha := testISO(t, "kernel\n")
	peer := serveISO(t, "127.0.0.1:0", iso, sha)
	internet := serveISO(t, "127.0.0.1:0", iso, sha)
	h := isoHarness(t, sha)
	h.s.cfg.ISOURL = internet.URL + "/releases/ubuntu.iso"
	h.s.cfg.HTTPPort, _ = strconv.Atoi(peer.URL[strings.LastIndex(peer.URL, ":")+1:])
	h.s.PeerNet = peerLink

	if err := h.s.PrepareISO(context.Background()); err != nil {
		t.Fatal(err)
	}
	if peer.requests.Load() != 2 || internet.requests.Load() != 0 {
		t.Fatalf("%d requests to the other edge, %d to the internet", peer.requests.Load(), internet.requests.Load())
	}
}

func TestAnEdgeOfferingAnotherISOIsPassedOverForTheInternet(t *testing.T) {
	iso, sha := testISO(t, "kernel\n")
	older, olderSHA := testISO(t, "older kernel\n")
	peer := serveISO(t, "127.0.0.1:0", older, olderSHA)
	internet := serveISO(t, "127.0.0.1:0", iso, sha)
	h := isoHarness(t, sha)
	h.s.cfg.ISOURL = internet.URL + "/releases/ubuntu.iso"
	h.s.cfg.HTTPPort, _ = strconv.Atoi(peer.URL[strings.LastIndex(peer.URL, ":")+1:])
	h.s.PeerNet = peerLink

	if err := h.s.PrepareISO(context.Background()); err != nil {
		t.Fatal(err)
	}
	if peer.requests.Load() != 1 || internet.requests.Load() != 1 {
		t.Fatalf("%d requests to the other edge, %d to the internet", peer.requests.Load(), internet.requests.Load())
	}
	if rec := h.get(t, "/ubuntu/vmlinuz", "192.168.50.102"); rec.Body.String() != "kernel\n" {
		t.Fatalf("serves %q", rec.Body.String())
	}
}

func TestAnEdgeOffersTheOtherEdgesItsVerifiedISOAndNothingElse(t *testing.T) {
	iso, sha := testISO(t, "kernel\n")
	origin := serveISO(t, "127.0.0.1:0", iso, sha)
	h := isoHarness(t, sha)
	h.s.cfg.ISOURL = origin.URL + "/releases/ubuntu.iso"
	offer := httptest.NewServer(h.s.PeerHandler())
	defer offer.Close()

	if resp, err := http.Get(offer.URL + "/ubuntu.iso.sha256"); err != nil || resp.StatusCode != http.StatusNotFound {
		t.Fatalf("offered an ISO before verifying one: %v %v", resp, err)
	}
	if err := h.s.PrepareISO(context.Background()); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]int{"/ubuntu.iso": len(iso), "/ubuntu.iso.sha256": len(sha) + 1} {
		resp, err := http.Get(offer.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK || len(body) != want {
			t.Fatalf("%s: %d, %d bytes", path, resp.StatusCode, len(body))
		}
	}
	for _, path := range []string{"/ubuntu/vmlinuz", "/hosts/38-05-25-38-b5-b5.ipxe", "/cgi-bin/announce"} {
		resp, err := http.Get(offer.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("%s offered to the other edges: %d", path, resp.StatusCode)
		}
	}
}

func TestPeerCandidatesAreTheOtherAddressesOfTheEdgesLink(t *testing.T) {
	for cidr, want := range map[string]string{
		"10.255.255.1/29": "10.255.255.2 10.255.255.3 10.255.255.4 10.255.255.5 10.255.255.6",
		"10.255.255.2/30": "10.255.255.1",
		"10.255.255.2/24": "",
		"10.255.255.2/31": "",
	} {
		ip, n, _ := net.ParseCIDR(cidr)
		n.IP = ip
		if got := strings.Join(PeerCandidates(n), " "); got != want {
			t.Fatalf("%s: %q, want %q", cidr, got, want)
		}
	}
}
