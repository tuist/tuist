package rackboot

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed/rackseedtest"
)

// newInternetHarness is the boot server machines reach over the internet,
// which no machine is a neighbor of.
func newInternetHarness(t *testing.T, objs ...client.Object) *harness {
	t.Helper()
	h := newHarness(t, objs...)
	h.s = NewServer(Config{Internet: true, Listen: ":8480", Namespace: testNamespace, SecretName: "fleet-boot", Site: "internet", Node: "internet"}, h.c, h.c, logr.Discard())
	h.s.Now = func() time.Time { return testNow }
	return h
}

func checkCode(b64 string) string {
	der, _ := base64.StdEncoding.DecodeString(b64)
	return rackseed.CheckCode(der)
}

// Only a machine declared with the check code of the TPM it announces
// becomes a candidate: anyone on the internet reaches this server.
func TestTheInternetBootServerTakesOnlyDeclaredMachinesAnnouncements(t *testing.T) {
	withoutCode := publishedHost(keyID)
	h := newInternetHarness(t, withoutCode)
	body := announcement + "ek=" + testEK + "\n"
	for name, tc := range map[string]struct {
		body string
		code string
	}{
		"declared without a check code": {body, ""},
		"announcing no TPM":             {announcement, checkCode(testEK)},
		"another TPM":                   {body, checkCode(func() string { ek, _ := rackseedtest.New().EK(); return base64.StdEncoding.EncodeToString(ek) }())},
	} {
		host := h.host(t)
		host.Spec.TPMCheckCode = tc.code
		if err := h.c.Update(context.Background(), host); err != nil {
			t.Fatal(err)
		}
		if rec := h.announce(t, tc.body, "203.0.113.7"); rec.Code != http.StatusForbidden {
			t.Errorf("%s: %d %q", name, rec.Code, rec.Body.String())
		}
	}
	stranger := strings.Replace(body, hostUUID, "00000000-0000-0000-0000-000000000001", 1)
	if rec := h.announce(t, stranger, "203.0.113.7"); rec.Code != http.StatusForbidden {
		t.Errorf("an undeclared machine: %d %q", rec.Code, rec.Body.String())
	}
	if list := (&infrav1.RackLinuxCandidateList{}); h.c.List(context.Background(), list) == nil && len(list.Items) != 0 {
		t.Fatalf("refused announcements made candidates: %+v", list.Items)
	}

	host := h.host(t)
	host.Spec.TPMCheckCode = strings.ToUpper(checkCode(testEK))
	if err := h.c.Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
	if rec := h.announce(t, body, "203.0.113.7"); rec.Code != http.StatusOK {
		t.Fatalf("the declared machine: %d %q", rec.Code, rec.Body.String())
	}
	cand := &infrav1.RackLinuxCandidate{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: hostUUID}, cand); err != nil || cand.Status.EK != testEK {
		t.Fatalf("candidate %+v %v", cand.Status, err)
	}
}

// Over the internet a seed goes out only sealed to the host's pinned TPM:
// nothing there is a neighbor to hand a plain seed to.
func TestTheInternetBootServerHandsOutOnlySealedSeeds(t *testing.T) {
	h := newInternetHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	srv := httptest.NewServer(h.s.Handler())
	t.Cleanup(srv.Close)
	if _, err := seedAsker(srv, nil).Ask(context.Background(), "38-05-25-38-b5-b5"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("a host with no pinned TPM got its seed over the internet: %v", err)
	}

	h = newInternetHarness(t, tpmHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	srv = httptest.NewServer(h.s.Handler())
	t.Cleanup(srv.Close)
	got, err := seedAsker(srv, hostTPM).Ask(context.Background(), "38-05-25-38-b5-b5")
	if err != nil || !strings.Contains(string(got), "tuist-install-id: "+keyID) {
		t.Fatalf("the pinned TPM: %q %v", got, err)
	}
	if boot := h.host(t).Status.Boot; boot == nil || !boot.Attested {
		t.Fatalf("status.boot %+v", boot)
	}
}

// The internet boot server serves nothing to netboot.
func TestTheInternetBootServerServesNoNetboot(t *testing.T) {
	h := newInternetHarness(t, publishedHost(keyID))
	h.s.SetInstalls(bootSecretData(keyID))
	for _, path := range []string{"/hosts/38-05-25-38-b5-b5.ipxe", "/hosts/38-05-25-38-b5-b5/user-data", "/ubuntu/vmlinuz"} {
		if rec := h.get(t, path, "203.0.113.7"); rec.Code != http.StatusNotFound && rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("%s: %d", path, rec.Code)
		}
	}
}
