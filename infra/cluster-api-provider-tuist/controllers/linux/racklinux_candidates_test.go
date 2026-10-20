package linux

import (
	"context"
	"testing"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const ms01UUID = "44312e80-1dc6-11f1-853e-8f903547d200"

var candidatesEpoch = time.Date(2026, 9, 25, 10, 0, 0, 0, time.UTC)

type candidatesHarness struct {
	d *RackLinuxCandidates
	c client.Client
}

func newCandidatesHarness(t *testing.T, objs ...runtime.Object) *candidatesHarness {
	t.Helper()
	c := fake.NewClientBuilder().WithScheme(rackTestScheme(t)).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackLinuxHost{}, &infrav1.RackLinuxCandidate{}).Build()
	return &candidatesHarness{c: c, d: &RackLinuxCandidates{Client: c, Now: func() time.Time { return candidatesEpoch }}}
}

func announced(lastSeen time.Time, declaredAs string) *infrav1.RackLinuxCandidate {
	return &infrav1.RackLinuxCandidate{
		ObjectMeta: metav1.ObjectMeta{Name: ms01UUID, Namespace: rackTestNamespace},
		Status: infrav1.RackLinuxCandidateStatus{
			UUID: ms01UUID, BootMAC: "38:05:25:38:b5:b5", LastSeen: &metav1.Time{Time: lastSeen}, DeclaredAs: declaredAs,
			NICs: []infrav1.RackLinuxCandidateNIC{{MAC: "38:05:25:38:b5:b5", Driver: "igc", PCIDevice: "0x125b"}},
		},
	}
}

func declaring(hostname string) *infrav1.RackLinuxHost {
	host := edgeHost()
	host.Name = ms01UUID
	host.Spec.Hostname = hostname
	return host
}

func (h *candidatesHarness) candidate(t *testing.T) (*infrav1.RackLinuxCandidate, bool) {
	t.Helper()
	cand := &infrav1.RackLinuxCandidate{}
	err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: ms01UUID}, cand)
	if apierrors.IsNotFound(err) {
		return nil, false
	}
	if err != nil {
		t.Fatal(err)
	}
	return cand, true
}

// A machine a host declares by its UUID is marked with the host's hostname,
// and unmarked once no host declares it.
func TestRackLinuxCandidatesMarksADeclaredMachine(t *testing.T) {
	h := newCandidatesHarness(t, announced(candidatesEpoch, ""), declaring("ber1-store-a"))
	if err := h.d.tidy(context.Background()); err != nil {
		t.Fatal(err)
	}
	if cand, _ := h.candidate(t); cand.Status.DeclaredAs != "ber1-store-a" || cand.Status.BootMAC != "38:05:25:38:b5:b5" {
		t.Fatalf("status %+v", cand.Status)
	}

	h = newCandidatesHarness(t, announced(candidatesEpoch, "ber1-store-a"))
	if err := h.d.tidy(context.Background()); err != nil {
		t.Fatal(err)
	}
	if cand, _ := h.candidate(t); cand.Status.DeclaredAs != "" {
		t.Fatalf("declaredAs %q with no host declaring it", cand.Status.DeclaredAs)
	}
}

// A machine no boot server has heard from for a week is gone from the list.
func TestRackLinuxCandidatesDropsAMachineNotSeenForAWeek(t *testing.T) {
	h := newCandidatesHarness(t, announced(candidatesEpoch.Add(-8*24*time.Hour), ""))
	if err := h.d.tidy(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := h.candidate(t); ok {
		t.Fatal("kept a machine not heard from for a week")
	}

	h = newCandidatesHarness(t, announced(candidatesEpoch.Add(-6*24*time.Hour), ""))
	if err := h.d.tidy(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := h.candidate(t); !ok {
		t.Fatal("dropped a machine heard from this week")
	}
}

// A declared machine stays however long it has been quiet: its host takes its
// boot MAC and model from it.
func TestRackLinuxCandidatesKeepsADeclaredMachine(t *testing.T) {
	h := newCandidatesHarness(t, announced(candidatesEpoch.Add(-60*24*time.Hour), "ber1-store-a"), declaring("ber1-store-a"))
	if err := h.d.tidy(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := h.candidate(t); !ok {
		t.Fatal("dropped a declared machine")
	}
}
