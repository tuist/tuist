package controllers

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

// RunnerAssignmentReconciler materializes the per-Pod artifacts —
// ServiceAccount + Pod — for a RunnerAssignment, and reflects the
// Pod's lifecycle back into the assignment's Status.Phase. The
// SA is the trust anchor for dispatch-endpoint authentication;
// the dispatch endpoint validates the SA's projected token via
// TokenReview and looks up the SA's `tuist.dev/runner-pool`
// label to resolve which pool the request belongs to.
type RunnerAssignmentReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// DispatchURL is the customer-server's runner dispatch
	// endpoint, threaded into every Pod via env. Set from the
	// manager's --dispatch-url flag (helm value).
	DispatchURL string
}

// +kubebuilder:rbac:groups=tuist.dev,resources=runnerassignments,verbs=get;list;watch;update;patch;delete
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerassignments/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerassignments/finalizers,verbs=update
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;delete
// +kubebuilder:rbac:groups="",resources=serviceaccounts,verbs=get;list;watch;create;delete

const assignmentFinalizer = "tuist.dev/runner-assignment"

func (r *RunnerAssignmentReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("assignment", req.NamespacedName)

	a := &tuistv1.RunnerAssignment{}
	if err := r.Get(ctx, req.NamespacedName, a); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !a.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, a)
	}

	if !controllerutil.ContainsFinalizer(a, assignmentFinalizer) {
		controllerutil.AddFinalizer(a, assignmentFinalizer)
		if err := r.Update(ctx, a); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: a.Namespace, Name: a.Spec.PoolRef.Name}, pool); err != nil {
		if apierrors.IsNotFound(err) {
			logger.Info("pool gone; deleting assignment")
			return ctrl.Result{}, r.Delete(ctx, a)
		}
		return ctrl.Result{}, err
	}

	podName, saName := podtemplate.AssignmentResources(a.Name)

	if err := r.ensureServiceAccount(ctx, pool, a, saName); err != nil {
		return ctrl.Result{}, fmt.Errorf("ensure SA: %w", err)
	}

	pod, err := r.ensurePod(ctx, pool, a, podName, saName)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("ensure Pod: %w", err)
	}

	// Reflect Pod state into Assignment.Status.
	updated := a.DeepCopy()
	updated.Status.PodName = podName
	updated.Status.PodUID = string(pod.UID)
	updated.Status.ServiceAccountName = saName
	updated.Status.Phase = mapPodPhase(pod.Status.Phase)
	if updated.Status.Phase != a.Status.Phase ||
		updated.Status.PodUID != a.Status.PodUID ||
		updated.Status.PodName != a.Status.PodName ||
		updated.Status.ServiceAccountName != a.Status.ServiceAccountName {
		if err := r.Status().Update(ctx, updated); err != nil && !apierrors.IsConflict(err) {
			return ctrl.Result{}, fmt.Errorf("status update: %w", err)
		}
	}

	// Once the Pod hits a terminal phase the GC watcher takes
	// over (deletes the assignment, which cascades to Pod + SA
	// via owner refs). Until then, we don't need a steady tick:
	// Pod events drive us via the watch.
	if updated.Status.Phase == tuistv1.PhaseTerminated {
		return ctrl.Result{}, r.Delete(ctx, a)
	}
	return ctrl.Result{}, nil
}

func (r *RunnerAssignmentReconciler) reconcileDelete(ctx context.Context, a *tuistv1.RunnerAssignment) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Delete owned Pod + SA. We rely on owner refs for
	// cascade-delete in the typical case, but stamping an
	// explicit delete here covers the foreground-deletion
	// edge: clean up when the assignment was deleted directly
	// (e.g. by an operator) rather than via pool cascade.
	podName, saName := podtemplate.AssignmentResources(a.Name)
	for _, kv := range []struct {
		obj  client.Object
		kind string
	}{
		{&corev1.Pod{}, "Pod"},
		{&corev1.ServiceAccount{}, "ServiceAccount"},
	} {
		key := types.NamespacedName{Namespace: a.Namespace, Name: podName}
		if kv.kind == "ServiceAccount" {
			key.Name = saName
		}
		if err := r.Get(ctx, key, kv.obj); err != nil {
			if !apierrors.IsNotFound(err) {
				return ctrl.Result{}, err
			}
			continue
		}
		if err := r.Delete(ctx, kv.obj); err != nil && !apierrors.IsNotFound(err) {
			logger.Error(err, "delete during finalize", "kind", kv.kind, "key", key)
			return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
		}
	}

	if controllerutil.RemoveFinalizer(a, assignmentFinalizer) {
		if err := r.Update(ctx, a); err != nil {
			if apierrors.IsConflict(err) || apierrors.IsNotFound(err) {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{}, err
		}
	}
	return ctrl.Result{}, nil
}

func (r *RunnerAssignmentReconciler) ensureServiceAccount(ctx context.Context, pool *tuistv1.RunnerPool, a *tuistv1.RunnerAssignment, saName string) error {
	sa := &corev1.ServiceAccount{}
	err := r.Get(ctx, types.NamespacedName{Namespace: a.Namespace, Name: saName}, sa)
	if err == nil {
		return nil
	}
	if !apierrors.IsNotFound(err) {
		return err
	}
	sa = podtemplate.BuildServiceAccount(pool, saName)
	if err := controllerutil.SetControllerReference(a, sa, r.Scheme); err != nil {
		return fmt.Errorf("owner ref: %w", err)
	}
	return r.Create(ctx, sa)
}

func (r *RunnerAssignmentReconciler) ensurePod(ctx context.Context, pool *tuistv1.RunnerPool, a *tuistv1.RunnerAssignment, podName, saName string) (*corev1.Pod, error) {
	pod := &corev1.Pod{}
	err := r.Get(ctx, types.NamespacedName{Namespace: a.Namespace, Name: podName}, pod)
	if err == nil {
		return pod, nil
	}
	if !apierrors.IsNotFound(err) {
		return nil, err
	}
	pod = podtemplate.Build(pool, podName, saName, r.DispatchURL)
	if err := controllerutil.SetControllerReference(a, pod, r.Scheme); err != nil {
		return nil, fmt.Errorf("owner ref: %w", err)
	}
	if err := r.Create(ctx, pod); err != nil {
		return nil, err
	}
	return pod, nil
}

func mapPodPhase(p corev1.PodPhase) tuistv1.AssignmentPhase {
	switch p {
	case corev1.PodPending, "":
		return tuistv1.PhasePending
	case corev1.PodRunning:
		return tuistv1.PhaseRunning
	case corev1.PodSucceeded, corev1.PodFailed:
		return tuistv1.PhaseTerminated
	default:
		return tuistv1.PhasePending
	}
}

func (r *RunnerAssignmentReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&tuistv1.RunnerAssignment{}).
		Owns(&corev1.Pod{}).
		Owns(&corev1.ServiceAccount{}).
		Complete(r)
}
