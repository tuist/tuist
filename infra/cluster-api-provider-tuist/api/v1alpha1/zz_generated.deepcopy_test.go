package v1alpha1

import (
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// controller-tools is not a dependency of this module, so zz_generated.deepcopy.go
// is maintained by hand. A pointer field added to the status without a matching
// block there is shallow-copied by `*out = *in`, so the copy aliases the
// original — which silently breaks controller-runtime's cache isolation: a
// reconciler mutating what it believes is its own copy corrupts the cached
// object and the patch baseline computed from it. The compiler cannot catch it,
// so assert it here: every pointer must survive a round trip through DeepCopy
// with its own backing memory.
func TestScalewayAppleSiliconMachineStatusDeepCopyDoesNotAliasPointers(t *testing.T) {
	reason := "TartKubeletUpdateExceededRetries"
	message := "tart-kubelet update failed 5 times"
	failedAt := metav1.NewTime(time.Date(2026, 8, 10, 12, 0, 0, 0, time.UTC))

	original := &ScalewayAppleSiliconMachineStatus{
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
