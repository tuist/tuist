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
	"strconv"
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
	// NodeIP is the routable address of the Mac mini host. Pods that
	// opt into scraping via the `prometheus.io/scrape` annotation
	// advertise this IP as their PodIP and run a host-side forwarder
	// here on the annotated port — keeping Alloy's existing pod-IP
	// based autodiscovery working without a route into the Tart VM's
	// NAT-private network. Empty when discovery failed at boot; the
	// forwarder + PodIP rewrite both no-op in that case so the rest
	// of the reconciler still functions.
	NodeIP   string
	Tart     *tart.Client
	Resolver *envresolver.Resolver
	Store    *Store

	// GC reclaims disk when a Tart pull errors with no-space. Optional
	// — when nil, the reconciler just surfaces the error.
	GC *Collector
}

// MetricsScrapeAnnotation is the pod annotation that tells
// tart-kubelet to expose the Pod's metrics endpoint on the host so
// in-cluster scrapers (Alloy, kube-prometheus-stack, etc.) can reach
// it. Mirrors the convention the rest of the Tuist Helm chart uses
// for Linux Pods, which is also what the Grafana k8s-monitoring
// chart's annotationAutodiscovery is configured to look for.
const MetricsScrapeAnnotation = "prometheus.io/scrape"

// MetricsPortAnnotation is the pod annotation declaring which port
// inside the Pod (= inside the Tart VM) serves /metrics. The
// host-side forwarder listens on the same port number on
// 0.0.0.0:<port>, so a Pod's annotated port doubles as the host
// listen port — at most one VM-pod runs per Mac mini in steady
// state (topologySpread on the Pod), making collisions a non-issue.
const MetricsPortAnnotation = "prometheus.io/port"

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

	// Start the metrics forwarder lazily on first podStatus rather
	// than here — the VM hasn't booted yet, IP() returns empty, and
	// the forwarder needs at least an upstream to dial when the
	// scraper hits it.
	return nil
}

// startMetricsForwarder spins up the host-side TCP relay declared by
// the Pod's `prometheus.io/scrape` annotation. Idempotent: a second
// call when the forwarder is already running returns nil. No-op when
// the annotation is absent or NodeIP isn't known.
func (r *Reconciler) startMetricsForwarder(pod *corev1.Pod, entry *Entry) error {
	if entry.MetricsForwarder != nil {
		return nil
	}
	if r.NodeIP == "" {
		return nil
	}
	port, ok := metricsPortFromPod(pod)
	if !ok {
		return nil
	}

	vmName := entry.VMName
	resolve := func() (string, error) {
		ctx, cancel := contextWithTimeout(5 * time.Second)
		defer cancel()
		ip, err := r.Tart.IP(ctx, vmName)
		if err != nil {
			return "", err
		}
		if ip == "" {
			return "", fmt.Errorf("vm %s has no IP yet", vmName)
		}
		return fmt.Sprintf("%s:%d", ip, port), nil
	}

	listenAddr := fmt.Sprintf("0.0.0.0:%d", port)
	fw, err := NewForwarder(listenAddr, resolve)
	if err != nil {
		return fmt.Errorf("start metrics forwarder for %s/%s on %s: %w", pod.Namespace, pod.Name, listenAddr, err)
	}
	entry.MetricsForwarder = fw
	return nil
}

// metricsPortFromPod reads the scrape opt-in + port annotations.
// Returns (port, true) when both are set and the port parses; the
// caller treats false as "Pod does not opt in".
func metricsPortFromPod(pod *corev1.Pod) (int, bool) {
	if pod.Annotations[MetricsScrapeAnnotation] != "true" {
		return 0, false
	}
	raw := pod.Annotations[MetricsPortAnnotation]
	if raw == "" {
		return 0, false
	}
	port, err := strconv.Atoi(raw)
	if err != nil || port <= 0 || port > 65535 {
		return 0, false
	}
	return port, true
}

// contextWithTimeout is split out so the production resolver can use
// context.Background as the parent (the resolver is invoked from a
// scraper-driven goroutine and must outlive the reconcile that
// started it).
func contextWithTimeout(d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), d)
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

	if entry.MetricsForwarder != nil {
		entry.MetricsForwarder.Stop()
		entry.MetricsForwarder = nil
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
// Tart 2.32's `get` doesn't update state for backgrounded VMs, so we
// use `tart ip` as the liveness probe — non-empty IP ⇒ running.
func (r *Reconciler) podStatus(ctx context.Context, pod *corev1.Pod) (*corev1.PodStatus, error) {
	entry := r.Store.Get(pod.Namespace, pod.Name)
	if entry == nil {
		return nil, nil
	}

	hostIP := r.NodeName
	if r.NodeIP != "" {
		hostIP = r.NodeIP
	}
	status := &corev1.PodStatus{
		StartTime: &entry.StartTS,
		HostIP:    hostIP,
	}

	ip, err := r.Tart.IP(ctx, entry.VMName)
	if err == nil && ip != "" {
		status.Phase = corev1.PodRunning
		// For Pods that opt into scraping we report the host IP as
		// the Pod IP so existing pod-IP-based discovery (Alloy's
		// annotationAutodiscovery, Service endpoints, kube-state-
		// metrics) targets the host-side forwarder rather than the
		// VM's NAT-private address. Spin the forwarder up here too
		// — first podStatus after VM boot is when an upstream IP
		// becomes available.
		if _, scraped := metricsPortFromPod(pod); scraped && r.NodeIP != "" {
			if err := r.startMetricsForwarder(pod, entry); err != nil {
				log.FromContext(ctx).Error(err, "start metrics forwarder",
					"pod", pod.Namespace+"/"+pod.Name)
			}
			status.PodIP = r.NodeIP
		} else {
			status.PodIP = ip
		}
		status.Conditions = []corev1.PodCondition{
			{Type: corev1.PodReady, Status: corev1.ConditionTrue},
		}
	} else {
		status.Phase = corev1.PodPending
	}
	return status, nil
}

func (r *Reconciler) publishStatus(ctx context.Context, pod *corev1.Pod, status *corev1.PodStatus) error {
	pod.Status = *status
	return r.CachedClient.Status().Update(ctx, pod)
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
//
// MetricsForwarder is the host-side TCP relay (host_ip:port →
// vm_ip:port) for Pods that opt into Prometheus scraping via the
// `prometheus.io/scrape` annotation. nil for Pods without the
// annotation and for entries materialised by recoverState — the
// next reconcile-and-restart cycle will set one up.
type Entry struct {
	VMName           string
	StartTS          metav1.Time
	Run              *tart.RunHandle
	MetricsForwarder *Forwarder
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
