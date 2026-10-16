package macos

import (
	"context"
	"sort"
	"testing"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// A RackPDU's change wakes the hosts plugged into it, so a host does not wait
// out its poll to find its PDU Ready.
func TestRackPDUChangeWakesTheHostsOnIt(t *testing.T) {
	other := rackHost("mini-03", func(h *infrav1.RackHost) {
		h.Spec.Power = &infrav1.PowerOutletRef{PDU: "ber1-pdu-a", Outlet: "1"}
	})
	elsewhere := pduHost("mini-04")
	elsewhere.Namespace = "other"
	r := newRackHostReconciler(t, nil, pduHost("mini-01"), pduHost("mini-02"), other, elsewhere, rackHost("mini-05"))

	reqs := r.rackHostsForRackPDU(context.Background(), readyPDU(true))

	var names []string
	for _, req := range reqs {
		names = append(names, req.Namespace+"/"+req.Name)
	}
	sort.Strings(names)
	if len(names) != 2 || names[0] != testNamespace+"/mini-01" || names[1] != testNamespace+"/mini-02" {
		t.Fatalf("RackPDU ber1-pdu-b woke %v, want the two hosts on it", names)
	}
}
