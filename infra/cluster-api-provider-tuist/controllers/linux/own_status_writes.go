package linux

import (
	"maps"
	"slices"

	"k8s.io/apimachinery/pkg/api/equality"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

// ignoreOwnStatusWrites keeps a machine reconciler from waking on its own
// status writes. Each pass patches status (a bootstrap attempt counted, a phase
// set), and without this filter that patch is the next pass's trigger, so the
// RequeueAfter a failing path returns never applies: the machine retries as fast
// as the API server answers. Everything else still wakes it: spec (generation),
// labels, annotations (CAPI's pause), finalizers, owner references (CAPI linking
// the Machine) and the start of a deletion.
func ignoreOwnStatusWrites() predicate.Predicate {
	return predicate.Funcs{
		UpdateFunc: func(e event.UpdateEvent) bool {
			if e.ObjectOld == nil || e.ObjectNew == nil {
				return true
			}
			before, after := e.ObjectOld, e.ObjectNew
			return before.GetGeneration() != after.GetGeneration() ||
				!maps.Equal(before.GetLabels(), after.GetLabels()) ||
				!maps.Equal(before.GetAnnotations(), after.GetAnnotations()) ||
				!slices.Equal(before.GetFinalizers(), after.GetFinalizers()) ||
				!equality.Semantic.DeepEqual(before.GetOwnerReferences(), after.GetOwnerReferences()) ||
				!equality.Semantic.DeepEqual(before.GetDeletionTimestamp(), after.GetDeletionTimestamp())
		},
	}
}
