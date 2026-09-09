package v1alpha1

import (
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// zz_generated.deepcopy.go is written by controller-gen through
// `mise run capi-scaleway-applesilicon:generate`. A pointer field added to a
// status without a matching block there is shallow-copied by `*out = *in`, so
// the copy aliases the original, which silently breaks controller-runtime's
// cache isolation: a reconciler mutating what it believes is its own copy
// corrupts the cached object and the patch baseline computed from it. The
// generator gets this right; a type declaring its own DeepCopyInto, which the
// generator then skips entirely, does not. The compiler catches neither, so
// assert it here: every pointer must survive a round trip through DeepCopy with
// its own backing memory.
//
// These pointers live on the embedded HostAgentStatus, which BOTH macOS machine
// kinds carry, so the assertion is made once on that block and then once per
// kind: a kind that embedded it without a generated DeepCopyInto of its own
// would alias every one of them.
func TestHostAgentStatusDeepCopyDoesNotAliasPointers(t *testing.T) {
	reason := "TartKubeletUpdateExceededRetries"
	message := "tart-kubelet update failed 5 times"
	failedAt := metav1.NewTime(time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC))

	original := &HostAgentStatus{
		FailureReason:         &reason,
		FailureMessage:        &message,
		LastUpdateFailureTime: &failedAt,
	}
	copied := original.DeepCopy()

	pointers := []struct {
		name          string
		sameAddress   bool
		mutateCopy    func()
		originalValue func() any
		want          any
	}{
		{
			name:          "FailureReason",
			sameAddress:   copied.FailureReason == original.FailureReason,
			mutateCopy:    func() { *copied.FailureReason = "mutated" },
			originalValue: func() any { return *original.FailureReason },
			want:          reason,
		},
		{
			name:          "FailureMessage",
			sameAddress:   copied.FailureMessage == original.FailureMessage,
			mutateCopy:    func() { *copied.FailureMessage = "mutated" },
			originalValue: func() any { return *original.FailureMessage },
			want:          message,
		},
		{
			name:          "LastUpdateFailureTime",
			sameAddress:   copied.LastUpdateFailureTime == original.LastUpdateFailureTime,
			mutateCopy:    func() { *copied.LastUpdateFailureTime = metav1.NewTime(time.Unix(0, 0)) },
			originalValue: func() any { return original.LastUpdateFailureTime.Time },
			want:          failedAt.Time,
		},
	}

	for _, p := range pointers {
		t.Run(p.name, func(t *testing.T) {
			if p.sameAddress {
				t.Fatalf("%s: copy shares the original's pointer; add a DeepCopyInto block for it", p.name)
			}
			p.mutateCopy()
			if got := p.originalValue(); got != p.want {
				t.Fatalf("%s: mutating the copy changed the original to %v; want %v", p.name, got, p.want)
			}
		})
	}
}

// The per-kind halves of the assertion above: each machine status embeds
// HostAgentStatus, and each must deep-copy it rather than share it.
func TestMachineStatusesDeepCopyTheirHostAgentStatus(t *testing.T) {
	reason := "TartKubeletUpdateExceededRetries"
	failedAt := metav1.NewTime(time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC))
	agent := HostAgentStatus{FailureReason: &reason, LastUpdateFailureTime: &failedAt}

	t.Run("ScalewayAppleSiliconMachineStatus", func(t *testing.T) {
		original := &ScalewayAppleSiliconMachineStatus{HostAgentStatus: *agent.DeepCopy()}
		assertHostAgentUnaliased(t, original.DeepCopy().HostAgentStatus, original.HostAgentStatus)
	})

	t.Run("StaticAppleSiliconMachineStatus", func(t *testing.T) {
		original := &StaticAppleSiliconMachineStatus{HostAgentStatus: *agent.DeepCopy()}
		assertHostAgentUnaliased(t, original.DeepCopy().HostAgentStatus, original.HostAgentStatus)
	})
}

func assertHostAgentUnaliased(t *testing.T, copied, original HostAgentStatus) {
	t.Helper()
	if copied.FailureReason == original.FailureReason {
		t.Fatal("FailureReason is shared with the original; the embedded HostAgentStatus was shallow-copied")
	}
	if copied.LastUpdateFailureTime == original.LastUpdateFailureTime {
		t.Fatal("LastUpdateFailureTime is shared with the original; the embedded HostAgentStatus was shallow-copied")
	}
}
