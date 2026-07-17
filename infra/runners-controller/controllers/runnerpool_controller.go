// Package controllers contains the reconcilers for the Tuist
// runner-pool CRD.
package controllers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/metrics"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

// runnerPoolFinalizer gates RunnerPool deletion on a graceful drain
// of in-flight runners. Without it, deleting (or renaming, via a
// helm pool-topology change) a RunnerPool would let Kubernetes GC
// cascade-delete the owned Pods, killing runners mid-job. See
// reconcileDelete.
const runnerPoolFinalizer = "tuist.dev/runner-pool-drain"

// drainEligibleLabel marks a stale-image Pod the controller has
// selected to retire in the current roll wave. The Tuist server 410s a
// stale Pod only when it carries this label, so the controller — which
// sees Pod readiness and can bound concurrency — paces the rollout
// rather than the server draining every stale Pod on the same tick.
const drainEligibleLabel = "tuist.dev/drain-eligible"

// defaultRollMaxConcurrentPercent applies when a pool omits
// spec.rollout.maxConcurrentPercent.
const defaultRollMaxConcurrentPercent = 5

// tartKubeletVMCleanupFinalizer is tart-kubelet's Pod finalizer, which
// gates the Pod object's removal on the host tearing its Tart VM down.
// Source of truth is `podagent.PodFinalizer` in infra/tart-kubelet;
// redeclared here because the two live in separate Go modules.
//
// It is node-local: the only code that removes it is the podagent's
// DeletionTimestamp branch, and each podagent filters the Pod informer
// down to its OWN `spec.nodeName`. So when a Node disappears — the CAPI
// provider deletes the Node object after releasing the Mac mini, and
// MachineHealthCheck remediation churns them routinely — every Pod still
// bound to it keeps this finalizer with no agent left alive to remove it.
// The apiserver then holds the Pod object open forever, and the terminal
// reap below can't help: the Pod is neither alive nor
// DeletionTimestamp-free, so it matches no branch. See
// releaseOrphanedRunner.
const tartKubeletVMCleanupFinalizer = "tart-kubelet.tuist.dev/vm-cleanup"

// RunnerPoolReconciler maintains a fleet of runner Pods + per-Pod
// ServiceAccounts. Pods are owned directly by the RunnerPool (no
// RunnerAssignment intermediate). When a Pod hits a terminal
// phase, the reconciler creates a replacement on whichever host
// the previous Pod freed.
type RunnerPoolReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// APIReader is an uncached, direct-to-apiserver reader used to
	// confirm a Node is really gone before the orphan sweep deletes
	// anything bound to it. Set from `mgr.GetAPIReader()`.
	//
	// The cached client cannot answer this question safely. Pod and Node
	// informers are independent watch streams with no atomic cross-type
	// view, so a Node that exists can be transiently absent from the Node
	// cache while a Pod already bound to it is visible in the Pod cache —
	// exactly the shape of a fleet where minis join and are released
	// continuously. Believing the cache there means deleting a healthy
	// runner mid-job: every live macOS runner Pod carries tart-kubelet's
	// finalizer and no deletionTimestamp, so Node existence is the ONLY
	// thing separating "busy runner" from "wedged orphan" — there is no
	// second signal to fall back on.
	//
	// nil disables the sweep entirely (see confirmedOrphans). Failing
	// closed on unwired plumbing loses cleanup; failing open loses jobs.
	APIReader client.Reader

	// DispatchURL is the customer-server's runner dispatch endpoint
	// threaded into every Pod via env. Set from the manager's
	// --dispatch-url flag. Used as-is for macOS pools (Tart VMs
	// bypass CNI and reach the public ingress via vmnet/NAT).
	DispatchURL string

	// DispatchInternalURL is the in-cluster (Service-based)
	// dispatch endpoint, used for Linux pools whose Pods live on
	// the cluster's CNI and can't reach the public ingress IP
	// from inside (Hetzner Cloud LB has no hairpin). Optional;
	// when empty, Linux pools fall back to DispatchURL — which
	// will silently fail to reach the server in the hairpin case.
	DispatchInternalURL string

	// DindImage is the OCI ref for the dockerd sidecar stamped on
	// Linux runner Pods. The chart pins it; Renovate keeps it
	// bumped. Empty means Linux pods skip the sidecar — fine for
	// macOS-only installs.
	DindImage string

	// RegistryMirror is the in-cluster Docker Hub pull-through cache
	// URL stamped into the dind sidecar's dockerd as --registry-mirror
	// (with a matching --insecure-registry, since it's http in-cluster).
	// Empty leaves dockerd pulling docker.io directly.
	RegistryMirror string

	// ClusterDNSIP / ClusterDomain configure in-VM cluster DNS for
	// macOS pools: when ClusterDNSIP is set, macOS runner Pods carry
	// TUIST_CLUSTER_DNS_IP (+ TUIST_CLUSTER_DOMAIN) and
	// dispatch-poll.sh inside the Tart VM writes an
	// /etc/resolver/<domain> entry pointing at it, so the
	// dispatch-provided `cache_endpoint_url`
	// (`*.svc.cluster.local`) resolves. Linux Pods ride the CNI's
	// DNS and never need these. Empty disables the env injection.
	ClusterDNSIP  string
	ClusterDomain string
}

// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=tuist.dev,resources=runnerpools/status,verbs=get;update;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch;create;patch;delete
// +kubebuilder:rbac:groups="",resources=serviceaccounts,verbs=get;list;watch;create;delete

func (r *RunnerPoolReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pool", req.NamespacedName)

	pool := &tuistv1.RunnerPool{}
	if err := r.Get(ctx, req.NamespacedName, pool); err != nil {
		if apierrors.IsNotFound(err) {
			// Pool object is gone — drop its metric series so deleted
			// pools (including static, non-autoscaling ones the autoscaler
			// never tracks) stop reporting stale roll/allocation gauges.
			metrics.Clear(req.Name)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Graceful drain on delete/rename. A helm upgrade that drops or
	// renames a RunnerPool deletes the CR; because Pods carry an owner
	// reference to it, Kubernetes GC would cascade-delete them, busy
	// or not. The finalizer holds the CR in etcd (GC leaves owned Pods
	// alone while the owner still exists) until reconcileDelete has
	// drained the pool: idle Pods deleted now, mid-job Pods left to
	// finish their single-shot job. Only then is the finalizer
	// dropped, letting the CR and any remaining terminal Pods/SAs GC.
	if !pool.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, pool)
	}
	if controllerutil.AddFinalizer(pool, runnerPoolFinalizer) {
		if err := r.Update(ctx, pool); err != nil {
			return ctrl.Result{}, fmt.Errorf("add drain finalizer: %w", err)
		}
	}

	// Track image rolls. The server-side drain endpoint reads
	// `status.imageRolledAt` and gates HTTP 410 on a per-Pod time
	// slot derived from the Pod name, so stale Pods halt in waves
	// rather than all on the first poll after a digest-pin bump.
	// Setting on first reconcile (when `ObservedImage` is empty) is
	// fine — there are no stale Pods yet, and the timestamp just
	// establishes the t=0 baseline for any future roll.
	if pool.Status.ObservedImage != pool.Spec.Image {
		pool.Status.ObservedImage = pool.Spec.Image
		pool.Status.ImageRolledAt = metav1.Now()
	}

	// Count Pods owned by this pool that are alive (not in a
	// terminal phase, not being deleted). Terminal Pods aren't
	// counted toward `replicas` — they're on their way out and a
	// replacement is needed.
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods,
		client.InNamespace(pool.Namespace),
		client.MatchingLabels{"tuist.dev/runner-pool": pool.Name},
	); err != nil {
		return ctrl.Result{}, fmt.Errorf("list pods: %w", err)
	}

	// Orphan verdict for the sweep below. Resolved once per reconcile and
	// shared with the phase-count loop so a Pod stranded on a deleted Node
	// isn't reported as warm capacity it can no longer provide.
	orphans := r.confirmedOrphans(ctx, pods.Items)

	phaseReplicas := podPhaseReplicaCounts{}
	for i := range pods.Items {
		p := &pods.Items[i]
		if isAlive(p) && !orphans[p.Name] {
			phaseReplicas.add(p)
		}
	}
	defer func() {
		metrics.RecordPodPhases(pool.Name, phaseReplicas.pending, phaseReplicas.running, phaseReplicas.unknown)
	}()

	alive := 0
	reaped := 0
	orphaned := 0
	staleAlive := 0
	markedStale := 0
	newNotReady := 0
	var idleAlive []*corev1.Pod
	// Stale idle Pods are retired under the roll cap (below), not all at
	// once: Running ones (macOS) get the drain-eligible label so the
	// server 410s them; Pending ones (Linux warm pollers, or macOS that
	// rolled mid-boot) are reaped directly. Both share one budget so a
	// digest roll can't make the whole fleet pull the new image at once.
	var drainCandidates []*corev1.Pod
	var stalePendingCandidates []*corev1.Pod
	for i := range pods.Items {
		p := &pods.Items[i]

		// Pod stranded on a Node that no longer exists. Its VM died with
		// the host, so it is neither doing work nor capacity we can fill
		// a job with, whatever phase it last published. Nothing else will
		// ever clean it up: tart-kubelet's finalizer is node-local, and
		// upstream PodGC's orphan collection only issues a Delete, which
		// a finalizer blocks. Release it before the branches below, which
		// all assume a Pod whose host is still around to act on it.
		if orphans[p.Name] {
			if err := r.releaseOrphanedRunner(ctx, p); err != nil {
				logger.Error(err, "release orphaned runner; will retry next tick",
					"pod", p.Name, "node", p.Spec.NodeName)
				continue
			}
			logger.Info("released orphaned runner",
				"pod", p.Name,
				"node", p.Spec.NodeName,
				"phase", string(p.Status.Phase),
			)
			orphaned++
			continue
		}

		switch {
		case isAlive(p):
			alive++
			switch {
			case isStaleImage(p, pool):
				staleAlive++
				if p.Labels[drainEligibleLabel] == "true" {
					markedStale++
				} else if isIdle(p) {
					// Pending stale idle Pods (Linux warm pollers, macOS
					// rolled mid-boot) are reaped directly; Running ones
					// (macOS warm) get the drain-eligible label for the
					// server to 410. Both retire under the shared roll cap.
					if p.Status.Phase == corev1.PodPending {
						stalePendingCandidates = append(stalePendingCandidates, p)
					} else {
						drainCandidates = append(drainCandidates, p)
					}
				}
			default:
				// Current-image Pod. Idle ones are scale-down candidates;
				// not-yet-Ready ones are booting (a roll's replacement when
				// one is active) and consume roll-concurrency budget. Stale
				// Pods are excluded from idleAlive on purpose — they're
				// retired by the roll throttle, not scale-down.
				if isIdle(p) {
					idleAlive = append(idleAlive, p)
				}
				if !isReady(p) {
					newNotReady++
				}
			}
		case p.DeletionTimestamp.IsZero():
			// Terminal Pod (Succeeded/Failed) with no deletion in
			// flight. Reap the Pod and its sibling ServiceAccount.
			// Without explicit cleanup the namespace fills with
			// stopped Pods + orphaned SAs, and the projected-token
			// cache in tart-kubelet keeps re-validating SAs whose
			// Pods are already gone.
			//
			// Log the runner container's exit code + reason first: it is
			// the durable, image-independent fingerprint of HOW the job
			// ended, captured before the Pod is reaped. A runner that
			// "lost communication with the server" can then be classified
			// from the controller logs (which land in Loki) instead of
			// from the reaped Pod (long gone) or the runner image's vitals
			// (absent on older images): 0 = clean exit (the runner
			// finished; a lost-comms here is the GitHub completion
			// handshake, not a death), 137 + reason=OOMKilled = host
			// cgroup OOM, 137 + reason=Error = guest-internal OOM or in-VM
			// kill, signal 15 = SIGTERM/deletion, other = crash.
			if t := runnerTerminated(p); t != nil {
				logger.Info("runner pod terminated",
					"pod", p.Name,
					"phase", string(p.Status.Phase),
					"exitCode", t.ExitCode,
					"signal", t.Signal,
					"reason", t.Reason,
				)
			}
			if err := r.reapRunner(ctx, p); err != nil {
				logger.Error(err, "reap terminal runner; will retry", "pod", p.Name)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			reaped++
		}
	}

	// Image-roll throttle (runs before the gap-fill so a reaped Pending
	// Pod's current-image replacement is created this same reconcile).
	// Retire stale Pods up to a concurrency cap so a digest roll doesn't
	// make the whole fleet `tart pull` the new ~tens-of-GB image at once
	// and collapse the warm pool. In-flight = stale Pods already committed
	// to drain, plus — while a roll is active — current-image Pods not yet
	// Ready (booting replacements); we retire more only as those reach
	// Ready. Both paths share the budget: reap idle Pending Pods directly,
	// mark idle Running Pods drain-eligible for the server to 410.
	// Best-effort: a failed reap/patch just retries next tick.
	rollPct := int32(defaultRollMaxConcurrentPercent)
	if pool.Spec.Rollout != nil && pool.Spec.Rollout.MaxConcurrentPercent > 0 {
		rollPct = pool.Spec.Rollout.MaxConcurrentPercent
	}
	capN := rollConcurrencyCap(pool.Spec.Replicas, rollPct)
	rolling := markedStale
	if staleAlive > 0 {
		rolling += newNotReady
	}
	for _, p := range stalePendingCandidates {
		if rolling >= capN {
			break
		}
		if err := r.reapRunner(ctx, p); err != nil {
			logger.Error(err, "reap stale pending pod; will retry next tick", "pod", p.Name)
			continue
		}
		alive--
		phaseReplicas.remove(p)
		rolling++
	}
	for _, p := range drainCandidates {
		if rolling >= capN {
			break
		}
		if err := r.markDrainEligible(ctx, p); err != nil {
			logger.Error(err, "mark drain-eligible; will retry next tick", "pod", p.Name)
			continue
		}
		rolling++
	}
	metrics.RecordRoll(pool.Name, rolling, staleAlive, capN)

	gap := int(pool.Spec.Replicas) - alive
	overflow := 0
	if gap < 0 {
		overflow = -gap
		gap = 0
	}

	logger.Info("reconcile",
		"target", pool.Spec.Replicas,
		"observed", alive,
		"reaped", reaped,
		"orphaned", orphaned,
		"gap", gap,
		"overflow", overflow,
		"idleAlive", len(idleAlive),
	)

	for i := 0; i < gap; i++ {
		if err := r.createRunner(ctx, pool); err != nil {
			logger.Error(err, "create runner; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		phaseReplicas.pending++
	}

	// Scale-down: alive > target. Delete IDLE Pods first — those
	// without `tuist.dev/runner-pool-owner` are warm-polling and
	// not currently running a customer job, so terminating them is
	// safe. Owned Pods (currently running a job) are never deleted
	// by the reconciler; the autoscaler's targets must be reached
	// over time, as owned Pods finish their jobs and exit.
	scaledDown := 0
	for i := 0; i < overflow && i < len(idleAlive); i++ {
		p := idleAlive[i]
		if err := r.reapAlivePod(ctx, p); err != nil {
			logger.Error(err, "scale-down delete; will retry", "pod", p.Name)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		phaseReplicas.remove(p)
		scaledDown++
	}

	observed := alive - scaledDown + gap
	pool.Status.ObservedReplicas = int32(observed)
	pool.Status.LastReconcile = metav1.Now()
	if err := r.Status().Update(ctx, pool); err != nil {
		if !apierrors.IsConflict(err) && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("status update: %w", err)
		}
	}

	// Steady-state requeue: re-run every 60 s as a safety net for
	// missed events. Pod-event-driven reconcile via Owns() is the
	// primary trigger; this is the catch-all.
	return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
}

// reconcileDelete drains a RunnerPool that's being deleted before
// releasing the finalizer. Idle Pods are reaped immediately; Pods
// running a job (carrying the `tuist.dev/runner-pool-owner` label)
// are left to finish their single-shot lifecycle. The CR stays
// Terminating until no live Pod remains, so GC never cascade-deletes
// a mid-job runner. Terminal Pods and the per-Pod SAs are collected
// by GC alongside the CR once the finalizer clears — except for
// orphans, which the sweep has to release explicitly because a held
// finalizer blocks the GC this path otherwise leans on.
func (r *RunnerPoolReconciler) reconcileDelete(ctx context.Context, pool *tuistv1.RunnerPool) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pool", client.ObjectKeyFromObject(pool))

	if !controllerutil.ContainsFinalizer(pool, runnerPoolFinalizer) {
		// Already drained, or never managed by us — let GC proceed.
		return ctrl.Result{}, nil
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods,
		client.InNamespace(pool.Namespace),
		client.MatchingLabels{"tuist.dev/runner-pool": pool.Name},
	); err != nil {
		return ctrl.Result{}, fmt.Errorf("list pods: %w", err)
	}

	// The drain needs the same orphan sweep as the steady-state path, and
	// needs it first. A Pod whose host is gone is neither draining nor
	// collectable, and both of the branches below get it wrong: a busy-
	// looking orphan counts as `running` forever, holding the CR in
	// Terminating and wedging the `helm --wait` that a pool rename or
	// removal triggers; a terminal one is left to a GC that a held
	// finalizer blocks, stranding exactly the Pod this controller exists
	// to release. Deleting the CR is also the one path where nothing ever
	// reconciles again to catch up later.
	orphans := r.confirmedOrphans(ctx, pods.Items)

	running := 0
	drainedIdle := 0
	orphaned := 0
	for i := range pods.Items {
		p := &pods.Items[i]
		switch {
		case orphans[p.Name]:
			if err := r.releaseOrphanedRunner(ctx, p); err != nil {
				logger.Error(err, "release orphaned runner while draining; will retry",
					"pod", p.Name, "node", p.Spec.NodeName)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			logger.Info("released orphaned runner while draining",
				"pod", p.Name, "node", p.Spec.NodeName, "phase", string(p.Status.Phase))
			orphaned++
		case !isAlive(p):
			// Terminal or already deleting — GC takes it with the CR.
		case isIdle(p):
			if err := r.reapRunner(ctx, p); err != nil {
				logger.Error(err, "drain idle pod; will retry", "pod", p.Name)
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			drainedIdle++
		default:
			running++
		}
	}

	if running > 0 {
		// Mid-job runners still finishing. Hold the finalizer and
		// re-check; single-shot Pods turn over to terminal on exit.
		// Bounded in practice by the GitHub Actions job timeout.
		logger.Info("draining pool; waiting on in-flight runners",
			"running", running, "drainedIdle", drainedIdle, "orphaned", orphaned)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	controllerutil.RemoveFinalizer(pool, runnerPoolFinalizer)
	if err := r.Update(ctx, pool); err != nil {
		return ctrl.Result{}, fmt.Errorf("remove drain finalizer: %w", err)
	}
	logger.Info("pool drained; finalizer released",
		"drainedIdle", drainedIdle, "orphaned", orphaned)
	return ctrl.Result{}, nil
}

// createRunner provisions one Pod + per-Pod ServiceAccount pair,
// both owned by the RunnerPool. Pod and SA share the same name so
// the dispatch endpoint can look up "which Pod is this SA mounted
// on" from the validated SA name alone.
func (r *RunnerPoolReconciler) createRunner(ctx context.Context, pool *tuistv1.RunnerPool) error {
	suffix, err := randHex(4)
	if err != nil {
		return fmt.Errorf("generate suffix: %w", err)
	}
	name := fmt.Sprintf("%s-runner-%s", pool.Name, suffix)

	sa := podtemplate.BuildServiceAccount(pool, name)
	if err := controllerutil.SetControllerReference(pool, sa, r.Scheme); err != nil {
		return fmt.Errorf("sa owner ref: %w", err)
	}
	if err := r.Create(ctx, sa); err != nil && !apierrors.IsAlreadyExists(err) {
		return fmt.Errorf("create sa: %w", err)
	}

	pod, err := podtemplate.Build(pool, name, name, r.DispatchURL, r.DispatchInternalURL, r.DindImage, r.RegistryMirror, r.ClusterDNSIP, r.ClusterDomain)
	if err != nil {
		return fmt.Errorf("build pod: %w", err)
	}
	if err := controllerutil.SetControllerReference(pool, pod, r.Scheme); err != nil {
		return fmt.Errorf("pod owner ref: %w", err)
	}
	if err := r.Create(ctx, pod); err != nil && !apierrors.IsAlreadyExists(err) {
		return fmt.Errorf("create pod: %w", err)
	}

	return nil
}

// reapRunner deletes a Pod and its same-named ServiceAccount.
// Both are owned by the RunnerPool as siblings — deleting the
// Pod alone leaves the SA behind. Pod and SA share a name by
// construction (see createRunner), so we issue both deletes by
// name. NotFound on either is treated as success: the goal is
// "nothing left," not "I'm the one that deleted it."
//
// Called for both terminal Pods (Succeeded/Failed → natural
// turnover) and stale Pending Pods (image roll → recycle on
// current image). The cleanup contract is the same.
func (r *RunnerPoolReconciler) reapRunner(ctx context.Context, pod *corev1.Pod) error {
	if err := r.Delete(ctx, pod); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete pod %s: %w", pod.Name, err)
	}
	sa := &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: pod.Namespace,
			Name:      pod.Name,
		},
	}
	if err := r.Delete(ctx, sa); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete sa %s: %w", pod.Name, err)
	}
	return nil
}

// liveNodeNames returns the names of every Node currently registered in
// the cluster.
//
// ok is false when the view is unusable, and callers must then skip the
// orphan sweep entirely rather than treat what they have as authoritative.
// Both failure modes collapse to "every Pod looks orphaned", and acting on
// that would delete the whole fleet mid-job: a List error is the obvious
// one, and an empty list is the subtle one (a Node informer that hasn't
// synced yet reads as zero Nodes, not as an error). A cluster with no Nodes
// at all has no runner Pods to sweep, so refusing to act on an empty view
// costs nothing.
func (r *RunnerPoolReconciler) liveNodeNames(ctx context.Context) (map[string]struct{}, bool) {
	nodes := &corev1.NodeList{}
	if err := r.List(ctx, nodes); err != nil {
		return nil, false
	}
	if len(nodes.Items) == 0 {
		return nil, false
	}
	names := make(map[string]struct{}, len(nodes.Items))
	for i := range nodes.Items {
		names[nodes.Items[i].Name] = struct{}{}
	}
	return names, true
}

// isOrphaned reports whether pod is bound to a Node absent from the
// cached Node view. An unscheduled Pod (no nodeName yet) is not orphaned
// — it is waiting for a host, which is the normal Pending state for a
// warm poller that hasn't been placed.
//
// This is only the cheap first pass. A cached miss is a suspicion, not a
// verdict: see confirmedOrphans, which re-checks every hit against the
// apiserver before anything is deleted.
func isOrphaned(pod *corev1.Pod, liveNodes map[string]struct{}) bool {
	if pod.Spec.NodeName == "" {
		return false
	}
	_, live := liveNodes[pod.Spec.NodeName]
	return !live
}

// confirmedOrphans returns, by Pod name, the Pods bound to a Node that
// really is gone. Computed once per reconcile and shared by every loop
// that needs the verdict, so the apiserver sees at most one Get per
// suspect Node however many Pods were stranded on it.
//
// Two-pass on purpose. The cached NodeList is the cheap filter that keeps
// the steady state (no orphans) free; every Pod it flags is then confirmed
// against the apiserver, whose Get is authoritative and linearizable where
// the informer's absence is merely "nothing delivered yet". Only a definite
// NotFound counts as gone: a transient error, an RBAC regression, or a
// timeout all leave the Pod alone, because the cost of waiting a tick is a
// Pod cleaned up late, and the cost of guessing wrong is a job killed.
//
// Returns empty (sweep disabled) when the Node view is unusable or the
// APIReader is unwired.
func (r *RunnerPoolReconciler) confirmedOrphans(ctx context.Context, pods []corev1.Pod) map[string]bool {
	orphans := map[string]bool{}
	if r.APIReader == nil {
		return orphans
	}
	liveNodes, ok := r.liveNodeNames(ctx)
	if !ok {
		return orphans
	}

	gone := map[string]bool{}
	for i := range pods {
		p := &pods[i]
		if !isOrphaned(p, liveNodes) {
			continue
		}
		node := p.Spec.NodeName
		verdict, checked := gone[node]
		if !checked {
			verdict = r.nodeConfirmedGone(ctx, node)
			gone[node] = verdict
		}
		if verdict {
			orphans[p.Name] = true
		}
	}
	return orphans
}

// nodeConfirmedGone asks the apiserver directly whether a Node exists.
// Only an explicit NotFound is treated as gone; every other outcome
// (including errors) reports "still there" so callers leave the Pod be.
func (r *RunnerPoolReconciler) nodeConfirmedGone(ctx context.Context, name string) bool {
	err := r.APIReader.Get(ctx, client.ObjectKey{Name: name}, &corev1.Node{})
	return apierrors.IsNotFound(err)
}

// releaseOrphanedRunner force-completes the removal of a Pod whose Node
// is gone, by stripping tart-kubelet's node-local finalizer before the
// usual reap. Removing the finalizer is safe precisely because the host
// is gone: the finalizer exists to keep the Pod object visible until the
// VM is torn down, and a released Mac mini takes its VMs with it, so
// there is nothing left to wait for. We strip only tart-kubelet's own
// finalizer and leave any other intact, so this can't bulldoze a
// finalizer whose owner is still alive to honour it.
//
// Ordering matters: the finalizer patch has to land before the Delete,
// or the Pod just re-enters the same wedged state (deletionTimestamp
// set, finalizer held, no agent to remove it) that stranded it here. The
// Delete is what the apiserver needs to actually collect the object; on
// a Pod already carrying a deletionTimestamp, dropping the finalizer
// completes the deletion on its own and reapRunner's Delete no-ops on
// NotFound while still collecting the sibling ServiceAccount.
func (r *RunnerPoolReconciler) releaseOrphanedRunner(ctx context.Context, pod *corev1.Pod) error {
	if controllerutil.ContainsFinalizer(pod, tartKubeletVMCleanupFinalizer) {
		// Optimistic lock: a blind merge patch rewrites the whole
		// finalizer array, which would silently drop a finalizer added
		// concurrently. Conflict just means re-read and retry next tick.
		patch := client.MergeFromWithOptions(pod.DeepCopy(), client.MergeFromWithOptimisticLock{})
		controllerutil.RemoveFinalizer(pod, tartKubeletVMCleanupFinalizer)
		if err := r.Patch(ctx, pod, patch); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("strip vm-cleanup finalizer from %s: %w", pod.Name, err)
		}
	}
	return r.reapRunner(ctx, pod)
}

// reapAlivePod is the scale-down path. Same shape as
// reapRunner (delete Pod + sibling SA) but we hit it from
// the autoscaler-driven branch where the Pod is still alive and
// merely idle. kubelet handles graceful container shutdown for us
// once Pod.DeletionTimestamp is set.
func (r *RunnerPoolReconciler) reapAlivePod(ctx context.Context, pod *corev1.Pod) error {
	return r.reapRunner(ctx, pod)
}

type podPhaseReplicaCounts struct {
	pending int
	running int
	unknown int
}

func (c *podPhaseReplicaCounts) add(pod *corev1.Pod) {
	switch pod.Status.Phase {
	case corev1.PodPending:
		c.pending++
	case corev1.PodRunning:
		c.running++
	default:
		c.unknown++
	}
}

func (c *podPhaseReplicaCounts) remove(pod *corev1.Pod) {
	switch pod.Status.Phase {
	case corev1.PodPending:
		if c.pending > 0 {
			c.pending--
		}
	case corev1.PodRunning:
		if c.running > 0 {
			c.running--
		}
	default:
		if c.unknown > 0 {
			c.unknown--
		}
	}
}

// isAlive returns true for Pods that should count toward `replicas`:
// not in a terminal phase, not pending deletion.
func isAlive(pod *corev1.Pod) bool {
	if !pod.DeletionTimestamp.IsZero() {
		return false
	}
	switch pod.Status.Phase {
	case corev1.PodSucceeded, corev1.PodFailed:
		return false
	default:
		return true
	}
}

// isIdle returns true for alive Pods that have NOT yet claimed a
// customer's workflow_job. Two independent signals say "claimed",
// and either one is enough to treat the Pod as busy:
//
//   - The Tuist server stamps `tuist.dev/runner-pool-owner=<account>`
//     on the Pod when it claims a queue entry. This is the primary
//     signal, but it's best-effort: the server degrades to "running
//     without the label" rather than dropping a job if the apiserver
//     patch keeps failing (Tuist.Runners.patch_pod_labels), so the
//     label can be absent on a genuinely-claimed Pod.
//   - On Linux (split shape) the `poller` init container exits as
//     soon as it stages the JIT for a claim, so a terminated poller
//     means the Pod has claimed (or is draining on a 410) and the
//     runner is about to run — independent of whether the label
//     stamp landed. This closes the window where a just-claimed Pod
//     is briefly Pending while the runner container starts and an
//     unlucky reconcile would otherwise see it as idle and reap it.
//
// macOS Pods have no poller init container, so they fall back to the
// label signal alone (their single Tart-VM container never produces
// this transition). Scale-down, drain, and the stale-Pending reap
// all key off this so we never kill a runner mid-job.
func isIdle(pod *corev1.Pod) bool {
	if v, ok := pod.Labels["tuist.dev/runner-pool-owner"]; ok && v != "" {
		return false
	}
	return !pollerTerminated(pod)
}

// pollerTerminated reports whether the Linux `poller` init container
// has exited. The poller exits 0 the instant it stages a claimed
// JIT (or drains on a 410), so its termination is a label-independent
// "this Pod is no longer warm-polling" signal. Returns false when
// there is no poller container status yet (still Waiting/Running) or
// at all (macOS single-container Pods).
func pollerTerminated(pod *corev1.Pod) bool {
	for _, cs := range pod.Status.InitContainerStatuses {
		if cs.Name == "poller" {
			return cs.State.Terminated != nil
		}
	}
	return false
}

// runnerTerminated returns the terminated state of the `runner`
// container, or nil if the container is absent or has no recorded
// termination. Prefers the current terminated state; falls back to the
// last termination. The exitCode + reason are the post-mortem
// fingerprint logged on reap (see the terminal branch in Reconcile).
func runnerTerminated(pod *corev1.Pod) *corev1.ContainerStateTerminated {
	for i := range pod.Status.ContainerStatuses {
		cs := &pod.Status.ContainerStatuses[i]
		if cs.Name != "runner" {
			continue
		}
		if cs.State.Terminated != nil {
			return cs.State.Terminated
		}
		return cs.LastTerminationState.Terminated
	}
	return nil
}

// isStaleImage returns true when the Pod's runner container image
// no longer matches the RunnerPool's spec.image — i.e., the chart
// has rolled the image pin since this Pod was created. Used to
// recycle Pending Pods on the next reconcile so a fresh image rolls
// out without an operator-driven `kubectl delete pod` dance.
func isStaleImage(pod *corev1.Pod, pool *tuistv1.RunnerPool) bool {
	if len(pod.Spec.Containers) == 0 {
		return false
	}
	return pod.Spec.Containers[0].Image != pool.Spec.Image
}

// isReady reports whether the Pod's Ready condition is True. macOS Pods
// have no per-container readiness (tart-kubelet runs the VM as one
// opaque unit), but tart-kubelet sets the PodReady condition once the
// guest has an IP — so this works for both runtimes.
func isReady(pod *corev1.Pod) bool {
	for _, c := range pod.Status.Conditions {
		if c.Type == corev1.PodReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

// rollConcurrencyCap is max(1, floor(pct/100 * replicas)): at least one
// Pod may always roll (so a rollout never wedges), at most ~pct% of the
// pool mid-roll at once.
func rollConcurrencyCap(replicas, pct int32) int {
	if replicas <= 0 || pct <= 0 {
		return 1
	}
	n := int(replicas) * int(pct) / 100
	if n < 1 {
		return 1
	}
	return n
}

// markDrainEligible stamps drainEligibleLabel on a stale Pod so the
// server will 410-drain it. Idempotent; a merge patch avoids clobbering
// concurrent label writes (e.g. the server's owner stamp).
func (r *RunnerPoolReconciler) markDrainEligible(ctx context.Context, pod *corev1.Pod) error {
	if pod.Labels[drainEligibleLabel] == "true" {
		return nil
	}
	patch := client.MergeFrom(pod.DeepCopy())
	if pod.Labels == nil {
		pod.Labels = map[string]string{}
	}
	pod.Labels[drainEligibleLabel] = "true"
	return r.Patch(ctx, pod, patch)
}

// runnerLabelPredicate filters the Pod watch down to Pods carrying
// `tuist.dev/runner=true` so the reconciler isn't woken by
// unrelated Pods that might land in the namespace.
func runnerLabelPredicate() predicate.Predicate {
	return predicate.NewPredicateFuncs(func(obj client.Object) bool {
		v, ok := obj.GetLabels()["tuist.dev/runner"]
		return ok && v == "true"
	})
}

func (r *RunnerPoolReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&tuistv1.RunnerPool{}).
		Owns(&corev1.Pod{}, builder.WithPredicates(runnerLabelPredicate())).
		Owns(&corev1.ServiceAccount{}).
		Complete(r)
}

func randHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
