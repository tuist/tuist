package controllers

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
)

// PodGCReconciler is the safety net that turns "the runner Pod
// reached a terminal phase" into "the assignment, the SA, and the
// Pod are all gone". The RunnerAssignmentReconciler also notices
// terminal Pods through its Owns(&Pod{}) watch and deletes the
// assignment — but if that reconciler is busy or the assignment
// CR has already been deleted out from under us (manual `kubectl
// delete`), this controller catches the orphan Pods + SAs. It
// only filters on Pods carrying the `tuist.dev/runner` label so
// it doesn't trample anything else in the namespace.
//
// Owner refs cascade Pod + SA deletion when the assignment goes,
// so the primary action here is "delete the assignment". For
// orphans (Pod whose owning assignment is already gone), we
// delete the Pod directly to ensure the namespace doesn't
// accumulate Succeeded Pods.
type PodGCReconciler struct {
	client.Client
}

// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;delete
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerassignments,verbs=get;list;watch;delete

func (r *PodGCReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pod", req.NamespacedName)

	pod := &corev1.Pod{}
	if err := r.Get(ctx, req.NamespacedName, pod); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Only act on terminal phases. Pending / Running Pods belong
	// to the assignment reconciler — interfering here would race
	// the steady-state status update.
	if pod.Status.Phase != corev1.PodSucceeded && pod.Status.Phase != corev1.PodFailed {
		return ctrl.Result{}, nil
	}

	// Find the owning RunnerAssignment via owner refs. If none
	// exists, the Pod is an orphan (manual kubectl create, or the
	// assignment was force-deleted) — delete the Pod so it doesn't
	// linger in Succeeded.
	ownerName := ""
	for _, o := range pod.OwnerReferences {
		if o.Kind == "RunnerAssignment" && o.APIVersion == tuistv1.GroupVersion.String() {
			ownerName = o.Name
			break
		}
	}
	if ownerName == "" {
		logger.Info("orphan terminal runner Pod; deleting")
		if err := r.Delete(ctx, pod); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("delete orphan pod: %w", err)
		}
		return ctrl.Result{}, nil
	}

	// Owning assignment exists: delete it. Owner refs cascade Pod
	// + SA deletion. We delete the assignment (not the Pod) so
	// the assignment's finalizer fires and the SA gets explicitly
	// reaped — owner-ref GC is async and orphans-by-policy can
	// leave SAs alive otherwise.
	a := &tuistv1.RunnerAssignment{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: pod.Namespace, Name: ownerName}, a); err != nil {
		if apierrors.IsNotFound(err) {
			// Assignment is already gone; delete the now-orphaned Pod.
			if err := r.Delete(ctx, pod); err != nil && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, fmt.Errorf("delete pod after assignment gone: %w", err)
			}
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}
	if !a.DeletionTimestamp.IsZero() {
		// Already being deleted; assignment finalizer will reap.
		return ctrl.Result{}, nil
	}
	logger.Info("terminal runner Pod; deleting owning assignment", "assignment", ownerName)
	if err := r.Delete(ctx, a); err != nil && !apierrors.IsNotFound(err) {
		return ctrl.Result{}, fmt.Errorf("delete assignment: %w", err)
	}
	return ctrl.Result{}, nil
}

// runnerLabelPredicate filters the Pod watch down to Pods we care
// about: those carrying `tuist.dev/runner=true`. Without this we
// reconcile every Pod in the namespace — fine in tuist-runners
// today, but a footgun if the namespace ever hosts non-runner
// workloads.
func runnerLabelPredicate() predicate.Predicate {
	return predicate.NewPredicateFuncs(func(obj client.Object) bool {
		v, ok := obj.GetLabels()["tuist.dev/runner"]
		return ok && v == "true"
	})
}

func (r *PodGCReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		Named("podgc").
		For(&corev1.Pod{}, builder.WithPredicates(runnerLabelPredicate())).
		Complete(r)
}
