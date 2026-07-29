package controllers

import (
	"context"
	"io"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/runners-controller/internal/sessions"
)

const (
	// deathLogTailLines / deathLogLimitBytes bound how much of an
	// abnormally-ended runner's log we re-emit. The runner container is
	// otherwise quiet (job output goes to GitHub server-side), so its
	// stdout is just the periodic RUNNER_VITALS samples plus the _diag
	// tail — a couple hundred lines covers the run-up to a death without
	// flooding the controller's own log stream.
	deathLogTailLines  = 200
	deathLogLimitBytes = 64 * 1024
)

// PodLifecycleReconciler watches runner Pods and reports
// terminal-phase transitions to the Tuist server's
// `/api/internal/runners/pods/stopped` endpoint. The server uses
// these signals to close per-Pod billing sessions in
// `runner_sessions`.
//
// Anchoring billing close on K8s (rather than the
// `workflow_job.completed` webhook) removes GitHub delivery
// latency / loss from the billing path: a webhook landing minutes
// late could otherwise extend the billed window past the customer's
// actual Pod runtime. The K8s `containerStatuses[].state.terminated.finishedAt`
// timestamp is the moment the runner container's process exited —
// no GH involvement.
//
// Concurrent with `RunnerPoolReconciler` (same For() type, separate
// workqueue). Whichever reconciler observes the terminal transition
// first emits its side-effect; both are idempotent.
type PodLifecycleReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// SessionsClient ships `stopped` events to the Tuist server.
	// Injected so tests can stand up an httptest.Server without
	// reaching for in-cluster machinery.
	SessionsClient *sessions.Client

	// Logs reads runner container logs via the `pods/log` subresource
	// (which the controller-runtime client.Client can't serve). When a
	// runner Pod ends abnormally, its final RUNNER_VITALS/_diag trail
	// lives only in the kubelet's container log, which is GC'd the
	// moment the reap deletes the Pod — and alloy doesn't reliably win
	// that race on a churning node, so mid-job deaths leave nothing in
	// Loki. This re-emits that tail to the controller's own (durable,
	// long-lived) stdout before the reap. nil disables capture; the
	// billing path still runs.
	Logs kubernetes.Interface

	// Now defaults to time.Now; overridable for deterministic
	// fallback-timestamp tests when the Pod carries no
	// finishedAt / deletionTimestamp.
	Now func() time.Time

	// reported tracks pod_names we've already POSTed a stopped
	// event for. Bounded by Pod churn — in production the
	// runners-controller's reap path removes terminal Pods within
	// 60 s, so the working set stays in the low thousands per
	// fleet per day. On controller restart the cache is empty and
	// we'll re-emit on the next reconcile; the server's
	// idempotency + under-bill bias makes that safe.
	reported sync.Map

	// captured tracks pod_names whose death log we've already
	// re-emitted, so repeated reconciles for the same terminal Pod
	// don't duplicate the trail. Same churn-bounded lifetime as
	// `reported`.
	captured sync.Map
}

// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=pods/log,verbs=get

func (r *PodLifecycleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pod", req.NamespacedName)

	pod := &corev1.Pod{}
	if err := r.Get(ctx, req.NamespacedName, pod); err != nil {
		if apierrors.IsNotFound(err) {
			// Pod is fully gone from the apiserver. If we never
			// reported it stopped (controller raced the reap), the
			// server-side max-lifetime safety clamp in
			// `Tuist.Runners.Billing` bounds the over-bill — we
			// have no finishedAt to send at this point anyway.
			// Drop the reported entry so a re-created Pod with the
			// same name (unlikely; names carry a random suffix)
			// gets a fresh emission.
			r.reported.Delete(req.NamespacedName.String())
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !isEnding(pod) {
		return ctrl.Result{}, nil
	}

	// Forensics backstop, independent of and ahead of the billing
	// dedup below: re-emit an abnormally-ended runner's final log to
	// the controller's own durable stdout before the reap deletes the
	// Pod. Best-effort — never fails or requeues the reconcile.
	r.captureDeathLog(ctx, pod)

	key := req.NamespacedName.String()
	if _, already := r.reported.Load(key); already {
		// Already POSTed — the server is idempotent, but skipping
		// avoids chatter between reconciles for the same Pod.
		return ctrl.Result{}, nil
	}

	endedAt := r.endedAt(pod)
	if err := r.SessionsClient.Stopped(ctx, pod.Name, endedAt); err != nil {
		// Transient — leave unreported, retry on the next event /
		// requeue. The server's max-lifetime clamp absorbs
		// permanent failures.
		logger.Error(err, "report pod stopped; will retry")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	r.reported.Store(key, struct{}{})
	logger.V(1).Info("reported pod stopped", "endedAt", endedAt)
	return ctrl.Result{}, nil
}

// isEnding returns true when the Pod has either transitioned into
// a terminal phase or been marked for deletion. Both branches mean
// "the runner container is no longer doing customer work" — the
// authoritative signal to stop billing.
func isEnding(pod *corev1.Pod) bool {
	if !pod.DeletionTimestamp.IsZero() {
		return true
	}
	switch pod.Status.Phase {
	case corev1.PodSucceeded, corev1.PodFailed:
		return true
	}
	return false
}

// endedAt resolves the most accurate "stopped at" timestamp the Pod
// exposes. Preference order:
//
//  1. Latest `state.terminated.finishedAt` across all containers.
//     This is the exact moment the runner process exited; biased
//     toward "later container's finish" so a multi-container Pod
//     (sidecars) doesn't under-attribute the runner's work.
//  2. The Pod's `deletionTimestamp` — when the controller initiated
//     deletion. Slightly under-bills compared to the actual
//     terminated finishedAt the kubelet would later write, which
//     is the safe direction.
//  3. Current wall-clock as last resort. Hit only when a Pod is
//     somehow in a terminal phase with no terminated containers
//     and no deletion timestamp — defensive only.
func (r *PodLifecycleReconciler) endedAt(pod *corev1.Pod) time.Time {
	var latest time.Time
	for _, cs := range pod.Status.ContainerStatuses {
		if cs.State.Terminated == nil {
			continue
		}
		if finished := cs.State.Terminated.FinishedAt.Time; !finished.IsZero() {
			if latest.IsZero() || finished.After(latest) {
				latest = finished
			}
		}
	}
	if !latest.IsZero() {
		return latest
	}
	if !pod.DeletionTimestamp.IsZero() {
		return pod.DeletionTimestamp.Time
	}
	return r.now()
}

func (r *PodLifecycleReconciler) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}

// captureDeathLog re-emits an abnormally-ended runner's container log
// to the controller's own stdout, so the final RUNNER_VITALS/_diag
// trail survives the reap that deletes the Pod (and the kubelet log
// with it). Best-effort: a disabled capturer, a healthy exit, an
// already-captured Pod, or an unreadable log all return without
// touching the billing path or requeueing.
func (r *PodLifecycleReconciler) captureDeathLog(ctx context.Context, pod *corev1.Pod) {
	if r.Logs == nil || !abnormalEnd(pod) {
		return
	}
	key := pod.Namespace + "/" + pod.Name
	if _, seen := r.captured.Load(key); seen {
		return
	}

	logger := log.FromContext(ctx)
	tail, err := r.fetchRunnerLog(ctx, pod.Namespace, pod.Name)
	if err != nil {
		// Leave unmarked so a later event (e.g. the deletion) retries
		// while the kubelet log still exists. A persistent failure just
		// means the trail was already gone — nothing we can recover.
		logger.V(1).Info("capture runner death log failed", "pod", pod.Name, "err", err)
		return
	}

	// Mark captured even when empty so an irrecoverable (never-written
	// or already-reaped) log isn't re-fetched on every reconcile.
	r.captured.Store(key, struct{}{})
	if tail == "" {
		return
	}
	logger.Info("runner death log captured",
		"pod", pod.Name,
		"pool", pod.Labels["tuist.dev/runner-pool"],
		"endedAt", r.endedAt(pod),
		"deathLog", tail,
	)
}

// fetchRunnerLog returns the tail of the `runner` container's log,
// bounded by line count and bytes so a runaway log can't flood the
// controller's stream.
func (r *PodLifecycleReconciler) fetchRunnerLog(ctx context.Context, namespace, name string) (string, error) {
	tail := int64(deathLogTailLines)
	limit := int64(deathLogLimitBytes)
	req := r.Logs.CoreV1().Pods(namespace).GetLogs(name, &corev1.PodLogOptions{
		Container:  "runner",
		TailLines:  &tail,
		LimitBytes: &limit,
	})
	stream, err := req.Stream(ctx)
	if err != nil {
		return "", err
	}
	defer stream.Close()
	body, err := io.ReadAll(stream)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

// abnormalEnd reports whether the runner container ended in a way
// worth preserving its log for. A clean ephemeral run exits 0 (job
// done, or no JIT claimed) and is skipped — note a workflow that fails
// its own tests still exits the runner 0, so this targets runner
// *infrastructure* deaths, not job outcomes. A non-zero/secondary-
// killed exit, or a Pod reaped while the runner never recorded a clean
// exit (the "lost communication" / torn-down-microVM shape), is
// abnormal.
func abnormalEnd(pod *corev1.Pod) bool {
	if rs := runnerContainerStatus(pod); rs != nil && rs.State.Terminated != nil {
		return rs.State.Terminated.ExitCode != 0
	}
	return pod.Status.Phase == corev1.PodFailed || !pod.DeletionTimestamp.IsZero()
}

func runnerContainerStatus(pod *corev1.Pod) *corev1.ContainerStatus {
	for i := range pod.Status.ContainerStatuses {
		if pod.Status.ContainerStatuses[i].Name == "runner" {
			return &pod.Status.ContainerStatuses[i]
		}
	}
	return nil
}

func (r *PodLifecycleReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		// Distinct controller name so this reconciler's workqueue
		// is independent of the RunnerPoolReconciler's. Both watch
		// the same Pod set but care about different transitions.
		Named("pod-lifecycle").
		For(&corev1.Pod{}, builder.WithPredicates(runnerLabelPredicate())).
		Complete(r)
}
