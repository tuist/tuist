package linux

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed/rackseedtest"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

func testEK(t *testing.T) []byte {
	t.Helper()
	ek, err := rackseedtest.New().EK()
	if err != nil {
		t.Fatal(err)
	}
	return ek
}

// A host takes its TPM from what the machine first announced, with its
// hardware, and keeps it.
func TestRackLinuxHostPinsTheTPMTheMachineFirstAnnounced(t *testing.T) {
	ek := testEK(t)
	host := svcHost()
	host.Spec.BootMAC = ""
	announced := announcedSvc()
	announced.Status.EK = base64.StdEncoding.EncodeToString(ek)
	h := newInstallHarness(t, host, announced)
	h.r.ReadHostEK = func(context.Context, *infrav1.RackLinuxHost) ([]byte, error) {
		t.Fatal("read the TPM of a host whose machine announced it")
		return nil, nil
	}

	got := h.reconcile(t, svcUUID)
	tpm := got.Status.TPM
	if tpm == nil || tpm.EK != announced.Status.EK || tpm.Fingerprint != rackseed.Fingerprint(ek) || tpm.Source != infrav1.RackLinuxHostTPMFromAnnouncement {
		t.Fatalf("tpm %+v", tpm)
	}
	if !conditions.IsTrue(got, TPMPinnedCondition) {
		t.Fatalf("TPMPinned %+v", conditions.Get(got, TPMPinnedCondition))
	}

	cand := &infrav1.RackLinuxCandidate{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: svcUUID}, cand); err != nil {
		t.Fatal(err)
	}
	cand.Status.EK = base64.StdEncoding.EncodeToString(testEK(t))
	if err := h.c.Update(context.Background(), cand); err != nil {
		t.Fatal(err)
	}
	if got := h.reconcile(t, svcUUID); got.Status.TPM.EK != announced.Status.EK {
		t.Fatalf("tpm %+v, want the one first pinned", got.Status.TPM)
	}
}

// An installed host whose machine announced no TPM has it read over SSH,
// which holds the host to the key its install was given, once.
func TestRackLinuxHostReadsTheTPMOfAnInstalledHost(t *testing.T) {
	ek := testEK(t)
	h := newInstallHarness(t, svcHost())
	h.api.devices = []tailnet.Device{svcDevice("dev-1", "2026-09-01T00:00:00Z", true)}
	reads := 0
	h.r.ReadHostEK = func(_ context.Context, host *infrav1.RackLinuxHost) ([]byte, error) {
		reads++
		if host.Status.Tailnet == nil || host.Status.Tailnet.DeviceID != "dev-1" {
			t.Fatalf("read the TPM of %+v", host.Status.Tailnet)
		}
		return ek, nil
	}

	got := h.reconcile(t, svcUUID)
	if tpm := got.Status.TPM; tpm == nil || tpm.Source != infrav1.RackLinuxHostTPMFromHost || tpm.Fingerprint != rackseed.Fingerprint(ek) {
		t.Fatalf("tpm %+v", tpm)
	}
	h.reconcile(t, svcUUID)
	if reads != 1 || !conditions.IsTrue(got, TPMPinnedCondition) {
		t.Fatalf("read %d times; TPMPinned %+v", reads, conditions.Get(got, TPMPinnedCondition))
	}
}

// A host whose TPM cannot be read is asked again a while later, not on
// every reconcile.
func TestRackLinuxHostReadsATPMThatFailedAgainLater(t *testing.T) {
	h := newInstallHarness(t, svcHost())
	h.api.devices = []tailnet.Device{svcDevice("dev-1", "2026-09-01T00:00:00Z", true)}
	reads := 0
	h.r.ReadHostEK = func(context.Context, *infrav1.RackLinuxHost) ([]byte, error) {
		reads++
		return nil, errors.New("rack-node: no TPM with an RSA endorsement key")
	}

	got := h.reconcile(t, svcUUID)
	c := conditions.Get(got, TPMPinnedCondition)
	if got.Status.TPM != nil || c == nil || c.Status != corev1.ConditionFalse || c.Reason != "ReadFailed" || !strings.Contains(c.Message, "no TPM") {
		t.Fatalf("tpm %+v TPMPinned %+v", got.Status.TPM, c)
	}
	h.now = h.now.Add(time.Minute)
	h.reconcile(t, svcUUID)
	if reads != 1 {
		t.Fatalf("read %d times within a minute", reads)
	}
	h.now = h.now.Add(rackTPMReadRetry)
	h.reconcile(t, svcUUID)
	if reads != 2 {
		t.Fatalf("read %d times, want again after %s", reads, rackTPMReadRetry)
	}
}

// A host that is not running an install of its own is not read.
func TestRackLinuxHostDoesNotReadTheTPMOfAHostItInstalls(t *testing.T) {
	for name, objs := range map[string]func() *infrav1.RackLinuxHost{
		"reinstalling": reinstalling,
		"not joined":   svcHost,
	} {
		t.Run(name, func(t *testing.T) {
			h := newInstallHarness(t, objs())
			if name == "reinstalling" {
				h.api.devices = []tailnet.Device{svcDevice("dev-1", "2026-09-01T00:00:00Z", true)}
			}
			h.r.ReadHostEK = func(context.Context, *infrav1.RackLinuxHost) ([]byte, error) {
				t.Fatal("read the TPM of a host being installed")
				return nil, nil
			}
			got := h.reconcile(t, svcUUID)
			if c := conditions.Get(got, TPMPinnedCondition); c == nil || c.Reason != "NotPinned" {
				t.Fatalf("TPMPinned %+v", c)
			}
		})
	}
}

// harnessEK is the TPM an installed host of the install harness reads as.
var harnessEK = func() []byte {
	ek, err := rackseedtest.New().EK()
	if err != nil {
		panic(err)
	}
	return ek
}()
