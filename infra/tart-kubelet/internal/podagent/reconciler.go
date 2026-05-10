// Package podagent watches Pods scheduled to this Node and translates
// them into Tart VMs. Pod ↔ VM is 1:1; multi-container Pods are
// rejected at admission time (init containers, sidecars, ephemeral
// containers all unsupported on this runtime).
package podagent

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/envresolver"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/satoken"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// PodFinalizer blocks API-server deletion of a Pod until tart-kubelet
// has stopped + deleted the underlying Tart VM. Without it, kubectl
// force-delete (gracePeriodSeconds=0) or a reconciler crash mid-Stop
// orphans the VM: kubectl reports the Pod gone while the VM keeps
// running on the host until GC sweeps it. The standard finalizer
// pattern lets us guarantee VM teardown completes before the Pod
// disappears from the API server's perspective.
const PodFinalizer = "tart-kubelet.tuist.dev/vm-cleanup"

// Reconciler is the controller-runtime reconciler for Pods on this
// Node. The cached client here is fine: the manager runs a single
// Pods informer that we filter by NodeName.
//
// The Resolver inside is pre-wired with the manager's APIReader so
// Secret/ConfigMap reads bypass the cache (no cluster-wide Secrets
// informer just to read a few refs per Pod).
type Reconciler struct {
	CachedClient client.Client
	NodeName     string
	Tart         *tart.Client
	Resolver     *envresolver.Resolver
	Store        *Store

	// TokenMinter mints projected ServiceAccount tokens for Pods
	// whose Spec.AutomountServiceAccountToken is true. Optional —
	// when nil, no token is staged (the env file is the only file
	// shared into the VM).
	TokenMinter satoken.Minter

	// GC reclaims disk when a Tart pull errors with no-space. Optional
	// — when nil, the reconciler just surfaces the error.
	GC *Collector
}

// SetupWithManager wires the reconciler with two predicates:
//   - NodeName match: only Pods k8s scheduled here.
//   - Handleable shape: skip multi-container / init / ephemeral Pods.
//     DaemonSets from kube-system land on this Node anyway (they
//     tolerate every taint); we don't want them in our reconcile
//     queue spamming TartCreateFailed events.
func (r *Reconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Pod{}, builder.WithPredicates(predicate.NewPredicateFuncs(func(o client.Object) bool {
			pod, ok := o.(*corev1.Pod)
			if !ok || pod.Spec.NodeName != r.NodeName {
				return false
			}
			return podIsHandled(pod)
		}))).
		Complete(r)
}

func (r *Reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pod", req.NamespacedName)

	pod := &corev1.Pod{}
	if err := r.CachedClient.Get(ctx, req.NamespacedName, pod); err != nil {
		if apierrors.IsNotFound(err) {
			// API-server already removed the Pod (the only way this
			// fires today is if the Pod was created without our
			// finalizer or someone yanked it manually). Best-effort
			// VM cleanup still runs from the in-memory Store.
			r.deleteByKey(ctx, req.Namespace, req.Name)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Pod already moved to a terminal phase (we marked it Succeeded
	// after the VM exited, or someone else marked it Failed). Do
	// nothing here: re-running createPod would clone+boot a fresh
	// VM for a Pod the workload controller is about to garbage-
	// collect, and the watcher needs the Pod to stay in the
	// terminal phase long enough to observe the transition. The
	// finalizer comes off via the DeletionTimestamp branch below
	// when the controller eventually deletes the Pod.
	if pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
		return ctrl.Result{}, nil
	}

	if !pod.DeletionTimestamp.IsZero() {
		// Pod is being deleted. Run VM teardown, then drop our
		// finalizer so the API server can complete deletion. Order
		// matters: we must not remove the finalizer until the VM
		// is gone, otherwise the Pod disappears from kubectl's view
		// while the VM is still running on the host.
		if err := r.deletePod(ctx, pod); err != nil {
			logger.Error(err, "delete failed; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		if controllerutil.RemoveFinalizer(pod, PodFinalizer) {
			if err := r.CachedClient.Update(ctx, pod); err != nil {
				if apierrors.IsConflict(err) || apierrors.IsNotFound(err) {
					return ctrl.Result{}, nil
				}
				logger.Error(err, "remove finalizer; will retry")
				return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
			}
		}
		return ctrl.Result{}, nil
	}

	// Add our finalizer on the first reconcile after admission so
	// the API server blocks the eventual deletion until our VM
	// teardown finishes. Idempotent — controllerutil.AddFinalizer
	// no-ops if the finalizer is already present.
	if controllerutil.AddFinalizer(pod, PodFinalizer) {
		if err := r.CachedClient.Update(ctx, pod); err != nil {
			if apierrors.IsConflict(err) {
				// Someone else updated the Pod; let the next
				// reconcile pick up the latest version.
				return ctrl.Result{Requeue: true}, nil
			}
			return ctrl.Result{}, fmt.Errorf("add finalizer: %w", err)
		}
		// Patch landed; let the watch fire the next reconcile with
		// the updated object so we don't risk acting on a stale copy.
		return ctrl.Result{}, nil
	}

	// If a previous reconcile recorded a RunHandle and the
	// `tart run` process has since exited (e.g. the guest crashed
	// 30s into a multi-minute boot, well past Run's 5s sanity
	// window), surface it as a Pod failure right here. Without this
	// check podStatus would just keep returning Pending on the IP
	// poll forever and helm --wait would hang for the full
	// --timeout. Marking the Pod Failed lets the owning ReplicaSet
	// schedule a replacement Pod with a fresh VM.
	if entry := r.Store.Get(pod.Namespace, pod.Name); entry != nil && entry.Run != nil {
		if exitErr, exited := entry.Run.Exited(); exited {
			logger.Info("tart run exited; marking pod failed",
				"vm", entry.VMName, "log", entry.Run.LogPath, "err", exitErr)
			_ = r.deleteByKey(ctx, pod.Namespace, pod.Name)
			_ = r.publishStatus(ctx, pod, &corev1.PodStatus{
				Phase:   corev1.PodFailed,
				Reason:  "TartRunExited",
				Message: fmt.Sprintf("tart run exited: %v (see %s)", exitErr, entry.Run.LogPath),
			})
			return ctrl.Result{}, nil
		}
	}

	if err := r.createPod(ctx, pod); err != nil {
		logger.Error(err, "create failed; will retry")
		// Surface the failure to the API server immediately so
		// `kubectl describe pod` shows it.
		_ = r.publishStatus(ctx, pod, &corev1.PodStatus{
			Phase:   corev1.PodPending,
			Message: err.Error(),
			Reason:  "TartCreateFailed",
		})
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	status, err := r.podStatus(ctx, pod)
	if err != nil || status == nil {
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}
	if err := r.publishStatus(ctx, pod, status); err != nil {
		logger.Error(err, "status update")
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}
	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

// createPod is idempotent. The Store guards against double-creates,
// and the underlying `tart` calls are themselves idempotent (`pull`
// caches, `clone` errors if the VM exists — we detect via Store).
// The SetupWithManager predicate filters Pods that don't fit
// tart-kubelet's contract before they reach this method.
func (r *Reconciler) createPod(ctx context.Context, pod *corev1.Pod) error {

	if existing := r.Store.Get(pod.Namespace, pod.Name); existing != nil {
		return nil
	}

	c := pod.Spec.Containers[0]
	env, err := r.Resolver.Resolve(ctx, pod, c)
	if err != nil {
		return fmt.Errorf("resolve env: %w", err)
	}

	vmName := VMNameForPod(pod)
	envDir, err := r.Tart.StageEnvFile(vmName, env)
	if err != nil {
		return err
	}

	// Mint + stage a projected SA token alongside the env file when
	// the Pod opts in via AutomountServiceAccountToken. The VM's
	// dispatch-poll script reads it as the Bearer credential for
	// the Tuist server's dispatch endpoint, which validates the
	// token via TokenReview and reads the SA's `tuist.dev/runner-pool`
	// label to resolve which pool to mint a JIT runner for.
	if r.TokenMinter != nil && shouldAutomountSAToken(pod) {
		token, err := r.TokenMinter.Mint(ctx, pod)
		if err != nil {
			return fmt.Errorf("mint sa token: %w", err)
		}
		if err := r.Tart.StageServiceAccountToken(vmName, token); err != nil {
			return fmt.Errorf("stage sa token: %w", err)
		}
	}

	// Reuse an existing local clone if one is on disk: a kubelet
	// restart kills the running VM (launchctl bootout signals the
	// process group) but the cloned image stays. Re-running it skips
	// the multi-minute pull + clone cycle.
	existingClone, _ := r.Tart.Get(ctx, vmName)

	if existingClone == nil {
		if err := r.Tart.Pull(ctx, c.Image); err != nil {
			// On disk-pressure failures, free space (orphan VMs / stale
			// OCI caches from terminated Pods) and retry once. Without
			// this the host fills with leftovers and every subsequent
			// reconcile fails the same way until something cleans up
			// by hand.
			if r.GC != nil && IsNoSpaceError(err) {
				r.GC.RunOnce(ctx)
				if err2 := r.Tart.Pull(ctx, c.Image); err2 != nil {
					return fmt.Errorf("tart pull (after gc): %w", err2)
				}
			} else {
				return fmt.Errorf("tart pull: %w", err)
			}
		}
		if err := r.Tart.Clone(ctx, c.Image, vmName); err != nil {
			return fmt.Errorf("tart clone: %w", err)
		}
	}

	// Resize the cloned VM to match the Pod's resource requests.
	// The image is built small (~4 vCPU / 8 GB) so it fits on a
	// 16 GB image-builder host; at deploy time the host is bigger
	// and the customer wants the VM to use whatever the Pod
	// requested. `tart set` is a no-op when the VM already matches.
	cpu, memMB := vmResourcesFromPod(c)
	if cpu > 0 || memMB > 0 {
		if err := r.Tart.Set(ctx, vmName, cpu, memMB); err != nil {
			return fmt.Errorf("tart set: %w", err)
		}
	}

	// Record the Pod ↔ VM mapping before kicking the VM off so the
	// rest of the system (deletePod, GC, recoverState) can keep
	// track of it even if `tart run` exits oddly. Without this an
	// early-exit Run leaves the VM Tart-side without a Store entry,
	// and the GC loop would happily reap it on the next pass —
	// exactly the orphan we used to clean up reactively.
	entry := &Entry{
		VMName:  vmName,
		StartTS: metav1.Now(),
	}
	r.Store.Put(pod.Namespace, pod.Name, entry)

	handle, err := r.Tart.Run(ctx, vmName, []string{"env:" + envDir + ":ro"})
	if err != nil {
		// Roll back the Store entry — the VM either never started
		// (cmd.Start error) or `tart run` exited immediately, so
		// there is no live VM for podStatus to observe and no
		// background process for deletePod to tear down.
		r.Store.Delete(pod.Namespace, pod.Name)
		return fmt.Errorf("tart run: %w", err)
	}
	entry.Run = handle
	return nil
}

func (r *Reconciler) deletePod(ctx context.Context, pod *corev1.Pod) error {
	// VM teardown only. The caller (Reconcile, on DeletionTimestamp)
	// removes the finalizer afterward, which lets the API server
	// complete deletion on its own — the controller-runtime-idiomatic
	// shape. No `client.Delete` here: the chart's tart-kubelet
	// ClusterRole grants update/patch on Pods (the real-kubelet
	// surface) but not delete, and we don't need it.
	return r.deleteByKey(ctx, pod.Namespace, pod.Name)
}

func (r *Reconciler) deleteByKey(ctx context.Context, namespace, name string) error {
	entry := r.Store.Get(namespace, name)
	if entry == nil {
		return nil
	}

	_ = r.Tart.Stop(ctx, entry.VMName, 30*time.Second)
	if err := r.Tart.Delete(ctx, entry.VMName); err != nil {
		return fmt.Errorf("tart delete: %w", err)
	}
	_ = r.Tart.CleanupVMUserData(entry.VMName)
	r.Store.Delete(namespace, name)
	return nil
}

// podStatus reads the underlying VM and translates to a Pod status.
//
// Liveness signal layering:
//   - `tart ip` returns the last-leased address even *after* the VM
//     halts — relying on it alone leaves a halted VM stuck Running
//     forever (the runner image's dispatch-poll exits and shuts the
//     guest down after one job; without a fresh signal the warm
//     pool never refills).
//   - `tart list`'s State field is unreliable for backgrounded VMs
//     under Tart 2.32 — it stays "stopped" while the VM is running.
//   - `pgrep tart run <name>` flips the moment the VM exits and is
//     the only signal that does, so it's the canonical liveness
//     probe. We still call `tart ip` afterwards to pick up the IP
//     for the podIP field while the VM is up.
//
// PodSucceeded vs PodFailed: a clean shutdown (the runner image's
// `shutdown -h now` after a successful job) is Succeeded; a `tart
// run` exit caught in-flight (RunHandle.Exited at line 141 above)
// is Failed because we caught the process error code. Both
// transitions wake the watcher; the distinction is reflected in
// `kubectl describe`.
func (r *Reconciler) podStatus(ctx context.Context, pod *corev1.Pod) (*corev1.PodStatus, error) {
	entry := r.Store.Get(pod.Namespace, pod.Name)
	if entry == nil {
		return nil, nil
	}

	hostIP := r.NodeName
	status := &corev1.PodStatus{
		StartTime: &entry.StartTS,
		HostIP:    hostIP,
	}

	running, err := r.Tart.IsRunning(ctx, entry.VMName)
	if err != nil {
		// pgrep failed unexpectedly — leave the Pod Running on
		// the optimistic read so we don't flap on a transient
		// host hiccup. The next reconcile retries.
		status.Phase = corev1.PodRunning
		return status, nil
	}

	if !running {
		// VM exited cleanly. Tear down the Tart clone + Store
		// entry so the host state mirrors what the API server
		// will see post-update, then mark the Pod Succeeded so
		// the watcher refills the warm pool.
		_ = r.deleteByKey(ctx, pod.Namespace, pod.Name)
		status.Phase = corev1.PodSucceeded
		status.Reason = "TartRunExited"
		return status, nil
	}

	if ip, ipErr := r.Tart.IP(ctx, entry.VMName); ipErr == nil && ip != "" {
		status.Phase = corev1.PodRunning
		status.PodIP = ip
		status.Conditions = []corev1.PodCondition{
			{Type: corev1.PodReady, Status: corev1.ConditionTrue},
		}
	} else {
		// VM process is alive but IP isn't yet available — the
		// guest is still booting. Pending is the right read.
		status.Phase = corev1.PodPending
	}
	return status, nil
}

func (r *Reconciler) publishStatus(ctx context.Context, pod *corev1.Pod, status *corev1.PodStatus) error {
	pod.Status = *status
	return r.CachedClient.Status().Update(ctx, pod)
}

// shouldAutomountSAToken mirrors kubelet's automount logic: the
// PodSpec's AutomountServiceAccountToken overrides the SA's
// default, falling back to true when neither is set explicitly
// (the apiserver's behavior). We only stage a token for Pods
// that actually want one — most workloads on tart-kubelet today
// don't, and minting + writing for them is wasted IO.
func shouldAutomountSAToken(pod *corev1.Pod) bool {
	if pod.Spec.AutomountServiceAccountToken != nil {
		return *pod.Spec.AutomountServiceAccountToken
	}
	return false
}

// podIsHandled returns true for Pods that fit tart-kubelet's contract:
// exactly one app container, no init or ephemeral containers. DaemonSets
// from kube-system that tolerate every taint will land on this Node;
// we skip them silently rather than fail-and-event-spam.
func podIsHandled(pod *corev1.Pod) bool {
	if len(pod.Spec.Containers) != 1 {
		return false
	}
	if len(pod.Spec.InitContainers) > 0 {
		return false
	}
	if len(pod.Spec.EphemeralContainers) > 0 {
		return false
	}
	return true
}

// vmResourcesFromPod returns the (cpu_cores, memory_mb) the VM
// should be sized to before `tart run`. Reads the first
// container's resources, preferring `limits` (a hard cap, the
// safer "this is the most we want this VM to consume") and
// falling back to `requests` (used by kube-scheduler for
// placement, often equal to limits in practice).
//
// Returns 0/0 when the Pod doesn't request anything specific —
// the caller skips `tart set` and the VM keeps the image's baked
// defaults. CPU is rounded down (millicores -> integer cores;
// 4000m -> 4); memory is rounded down to whole megabytes
// (Tart's `--memory` flag is integer MB).
func vmResourcesFromPod(c corev1.Container) (cpu int, memoryMB int) {
	cpu = pickIntCPU(c.Resources.Limits, c.Resources.Requests)
	memoryMB = pickIntMemoryMB(c.Resources.Limits, c.Resources.Requests)
	return cpu, memoryMB
}

func pickIntCPU(lists ...corev1.ResourceList) int {
	for _, list := range lists {
		if q, ok := list[corev1.ResourceCPU]; ok {
			// MilliValue() returns millicores as int64; integer
			// division by 1000 truncates toward zero. Quantity.Value()
			// rounds half-up which would over-promise on fractional
			// requests like 3500m -> 4 cores.
			return int(q.MilliValue() / 1000)
		}
	}
	return 0
}

func pickIntMemoryMB(lists ...corev1.ResourceList) int {
	for _, list := range lists {
		if q, ok := list[corev1.ResourceMemory]; ok {
			// Value() returns bytes; convert to MB.
			return int(q.Value() / (1024 * 1024))
		}
	}
	return 0
}

// VMNameForPod produces a Tart-safe VM name. Tart accepts alphanum +
// dashes; Pod names are already DNS-1123 (lowercase alphanum + dashes)
// so we join namespace + name. When the join exceeds Tart's 63-char
// cap we keep the first (max - 9) bytes and append `-` + an 8-char
// SHA-256 prefix of the full namespace/name. Plain truncation would
// collapse two Pods that diverge after byte 63 onto the same VM name;
// the hash suffix preserves uniqueness without making short names ugly.
//
// Exported so the kubelet's startup recovery pass can match running
// Tart VMs back to the Pods that created them after an agent restart.
func VMNameForPod(pod *corev1.Pod) string {
	name := pod.Namespace + "-" + pod.Name
	const max = 63
	if len(name) <= max {
		return name
	}
	sum := sha256.Sum256([]byte(pod.Namespace + "/" + pod.Name))
	suffix := "-" + hex.EncodeToString(sum[:4])
	return name[:max-len(suffix)] + suffix
}

// === In-memory Pod ↔ VM map ================================================

// Entry is the kubelet-side bookkeeping for one running Pod.
//
// Run is the handle to the backgrounded `tart run` process. It is
// nil for entries materialised by recoverState after a kubelet
// restart — those VMs are still running on the host but the
// process is no longer a child of this kubelet, so we can't observe
// its exit. The reconciler treats `Run == nil` as "trust IP probe
// alone" and skips the post-launch exit check.
type Entry struct {
	VMName  string
	StartTS metav1.Time
	Run     *tart.RunHandle
}

// Store is a tiny thread-safe map. Backed by in-memory state — on
// kubelet restart it's repopulated by listing Tart VMs and matching
// names to Pods (handled in main.go's reconcile-on-startup pass).
type Store struct {
	mu    sync.RWMutex
	items map[string]*Entry
}

// NewStore returns an empty Store.
func NewStore() *Store { return &Store{items: map[string]*Entry{}} }

func key(namespace, name string) string { return namespace + "/" + name }

// Get returns the entry or nil.
func (s *Store) Get(namespace, name string) *Entry {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.items[key(namespace, name)]
}

// Put records an entry.
func (s *Store) Put(namespace, name string, e *Entry) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[key(namespace, name)] = e
}

// Delete drops an entry.
func (s *Store) Delete(namespace, name string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.items, key(namespace, name))
}

// Snapshot returns a copy of the current items.
func (s *Store) Snapshot() map[string]*Entry {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make(map[string]*Entry, len(s.items))
	for k, v := range s.items {
		out[k] = v
	}
	return out
}
