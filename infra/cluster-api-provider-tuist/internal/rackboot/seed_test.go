package rackboot

import (
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed/rackseedtest"
)

var (
	hostTPM = rackseedtest.New()
	testEK  = func() string {
		ek, err := hostTPM.EK()
		if err != nil {
			panic(err)
		}
		return base64.StdEncoding.EncodeToString(ek)
	}()
)

// tpmHost is publishedHost with hostTPM pinned.
func tpmHost(key string) *infrav1.RackLinuxHost {
	host := publishedHost(key)
	ek, _ := base64.StdEncoding.DecodeString(testEK)
	host.Status.TPM = &infrav1.RackLinuxHostTPM{EK: testEK, Fingerprint: rackseed.Fingerprint(ek), Source: infrav1.RackLinuxHostTPMFromAnnouncement, PinnedAt: metav1.NewTime(testNow.Add(-time.Hour))}
	return host
}

// serve runs the boot server's handler on a loopback address, which the
// neighbor table maps to mac.
func (h *harness) serve(t *testing.T, mac string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(h.s.Handler())
	t.Cleanup(srv.Close)
	h.neighbors["127.0.0.1"] = mac
	return srv
}

func seedAsker(srv *httptest.Server, tpm rackseed.TPM) *rackseed.Asker {
	return &rackseed.Asker{Client: srv.Client(), Server: srv.URL, OpenTPM: func() (rackseed.TPM, error) {
		if tpm == nil {
			return nil, rackseed.ErrNoTPM
		}
		return tpm, nil
	}}
}

func TestAnAnnouncementCarriesTheTPMsEndorsementKey(t *testing.T) {
	h := newHarness(t)
	if rec := h.announce(t, announcement+"ek="+testEK+"\n", "192.168.50.120"); rec.Code != http.StatusOK {
		t.Fatalf("%d %q", rec.Code, rec.Body.String())
	}
	cand := &infrav1.RackLinuxCandidate{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, cand); err != nil {
		t.Fatal(err)
	}
	ek, _ := base64.StdEncoding.DecodeString(testEK)
	if cand.Status.EK != testEK || cand.Status.EKFingerprint != rackseed.Fingerprint(ek) {
		t.Fatalf("status %+v", cand.Status)
	}

	other, _ := rackseedtest.New().EK()
	for name, body := range map[string]string{
		"without the EK": announcement,
		"another EK":     announcement + "ek=" + base64.StdEncoding.EncodeToString(other) + "\n",
	} {
		if rec := h.announce(t, body, "192.168.50.103"); rec.Code != http.StatusConflict {
			t.Fatalf("%s: %d, want 409", name, rec.Code)
		}
	}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, cand); err != nil {
		t.Fatal(err)
	}
	if cand.Status.EK != testEK || cand.Status.Conflict == nil {
		t.Fatalf("status %+v", cand.Status)
	}
}

// A pinned host's seed goes out only sealed to its TPM, to whoever asks,
// since nothing else can open it; a plain request for it gets the stick's
// loader, which asks through the TPM.
func TestAPinnedHostsSeedGoesOutOnlySealedToItsTPM(t *testing.T) {
	h := newHarness(t, tpmHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	h.neighbors["192.168.50.104"] = bootMAC

	rec := h.get(t, "/hosts/38-05-25-38-b5-b5/user-data", "192.168.50.104")
	if rec.Code != http.StatusOK || strings.Contains(rec.Body.String(), keyID) || !strings.Contains(rec.Body.String(), "/tools/rack-node") {
		t.Fatalf("a plain request for a pinned host's seed: %d %q", rec.Code, rec.Body.String())
	}
	if boot := h.host(t).Status.Boot; boot != nil {
		t.Fatalf("handing out the loader recorded %+v", boot)
	}

	srv := h.serve(t, strangerMAC)
	if _, err := seedAsker(srv, nil).Ask(context.Background(), "38-05-25-38-b5-b5"); !errors.Is(err, rackseed.ErrNoTPM) {
		t.Fatalf("a machine without a TPM: %v", err)
	}
	if _, err := seedAsker(srv, rackseedtest.New()).Ask(context.Background(), "38-05-25-38-b5-b5"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("another TPM: %v", err)
	}
	if boot := h.host(t).Status.Boot; boot != nil {
		t.Fatalf("a refused request recorded %+v", boot)
	}

	got, err := seedAsker(srv, hostTPM).Ask(context.Background(), "38-05-25-38-b5-b5")
	if err != nil || !strings.Contains(string(got), "tuist-install-id: "+keyID) {
		t.Fatalf("the host's TPM: %q %v", got, err)
	}
	boot := h.host(t).Status.Boot
	if boot == nil || boot.KeyID != keyID || !boot.Attested || boot.ServedAt == nil || boot.ServedTo != strangerMAC {
		t.Fatalf("status.boot %+v", boot)
	}
	h.neighbors["127.0.0.1"] = otherNIC
	if _, err := seedAsker(srv, hostTPM).Ask(context.Background(), "38-05-25-38-b5-b5"); err != nil {
		t.Fatalf("the host's TPM asking again from another NIC: %v", err)
	}
}

func TestAHostWithoutAPinnedTPMGetsItsSeedOnlyOnItsNICs(t *testing.T) {
	h := newHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))

	srv := h.serve(t, strangerMAC)
	if _, err := seedAsker(srv, hostTPM).Ask(context.Background(), "38-05-25-38-b5-b5"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("a stranger's MAC: %v", err)
	}
	h.neighbors["127.0.0.1"] = otherNIC
	got, err := seedAsker(srv, nil).Ask(context.Background(), "38-05-25-38-b5-b5")
	if err != nil || !strings.Contains(string(got), "tuist-install-id: "+keyID) {
		t.Fatalf("the host's NIC: %q %v", got, err)
	}
	if boot := h.host(t).Status.Boot; boot == nil || boot.Attested || boot.ServedTo != otherNIC {
		t.Fatalf("status.boot %+v", boot)
	}
	if _, err := seedAsker(srv, nil).Ask(context.Background(), "aa-bb-cc-dd-ee-ff"); !errors.Is(err, rackseed.ErrNotPublished) {
		t.Fatalf("a MAC with nothing published: %v", err)
	}
}

func TestTheBootServerServesRackNode(t *testing.T) {
	h := newHarness(t)
	if rec := h.get(t, "/tools/rack-node", "192.168.50.104"); rec.Code != http.StatusNotFound {
		t.Fatalf("without a binary: %d", rec.Code)
	}
	path := filepath.Join(t.TempDir(), "rack-node-linux-amd64")
	if err := os.WriteFile(path, []byte("\x7fELF rack-node"), 0o755); err != nil {
		t.Fatal(err)
	}
	h.s.cfg.NodeBinary = path
	if rec := h.get(t, "/tools/rack-node", "192.168.50.104"); rec.Code != http.StatusOK || rec.Body.String() != "\x7fELF rack-node" {
		t.Fatalf("%d %q", rec.Code, rec.Body.String())
	}
}
