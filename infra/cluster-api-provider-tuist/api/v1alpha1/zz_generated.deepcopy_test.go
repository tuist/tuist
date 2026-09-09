package v1alpha1

import (
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// zz_generated.deepcopy.go is written by controller-gen through
// `mise run capi-scaleway-applesilicon:generate`. A pointer, map or slice field
// added to a spec or status without a matching block there is shallow-copied by
// `*out = *in`, so the copy aliases the original, which silently breaks
// controller-runtime's cache isolation: a reconciler mutating what it believes
// is its own copy corrupts the cached object and the patch baseline computed
// from it. The generator gets this right, but only for the types it covers: one
// declaring its own DeepCopyInto is skipped entirely, and regenerating then
// produces no diff to catch it. The compiler catches neither, so assert it
// here: every reference field must survive a round trip through DeepCopy with
// its own backing memory.
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

// FailoverIP declared its own DeepCopy methods, which is what kept it out of
// zz_generated.deepcopy.go until they were removed in favour of generated ones.
func TestFailoverIPDeepCopyDoesNotAliasReferences(t *testing.T) {
	reconciledAt := metav1.NewTime(time.Date(2026, 9, 9, 12, 0, 0, 0, time.UTC))

	original := &FailoverIP{
		Spec: FailoverIPSpec{
			IP:               "203.0.113.10",
			Vendor:           "ovh",
			NodePoolSelector: map[string]string{"node.cluster.x-k8s.io/pool": "kura-ovh-fr-par"},
			DemuxSelector:    map[string]string{"app.kubernetes.io/component": "peer-demux"},
		},
		Status: FailoverIPStatus{LastReconciledAt: &reconciledAt},
	}
	copied := original.DeepCopy()

	t.Run("LastReconciledAt", func(t *testing.T) {
		if copied.Status.LastReconciledAt == original.Status.LastReconciledAt {
			t.Fatal("copy shares the original's pointer; add a DeepCopyInto block for it")
		}
		*copied.Status.LastReconciledAt = metav1.NewTime(time.Unix(0, 0))
		if got := original.Status.LastReconciledAt.Time; !got.Equal(reconciledAt.Time) {
			t.Fatalf("mutating the copy changed the original to %v; want %v", got, reconciledAt.Time)
		}
	})

	selectors := []struct {
		name     string
		copied   map[string]string
		original map[string]string
		key      string
		want     string
	}{
		{
			name:     "NodePoolSelector",
			copied:   copied.Spec.NodePoolSelector,
			original: original.Spec.NodePoolSelector,
			key:      "node.cluster.x-k8s.io/pool",
			want:     "kura-ovh-fr-par",
		},
		{
			name:     "DemuxSelector",
			copied:   copied.Spec.DemuxSelector,
			original: original.Spec.DemuxSelector,
			key:      "app.kubernetes.io/component",
			want:     "peer-demux",
		},
	}

	for _, s := range selectors {
		t.Run(s.name, func(t *testing.T) {
			s.copied[s.key] = "mutated"
			if got := s.original[s.key]; got != s.want {
				t.Fatalf("writing to the copy changed the original to %q; want %q", got, s.want)
			}
		})
	}
}
