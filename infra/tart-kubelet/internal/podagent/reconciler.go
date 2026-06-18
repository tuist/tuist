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
	"net"
	"strconv"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
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
	// NodeIP is the routable address of the Mac mini host. Pods that
	// opt into scraping via the `prometheus.io/scrape` annotation
	// advertise this IP as their PodIP and run a host-side forwarder
	// here on the annotated port — keeping Alloy's existing pod-IP
	// based autodiscovery working without a route into the Tart VM's
	// NAT-private network. Empty when discovery failed at boot; the
	// forwarder + PodIP rewrite both no-op in that case so the rest
	// of the reconciler still functions.
	NodeIP string

	// ScrapeAllowedCIDRs restricts which client addresses the
	// per-Pod metrics forwarder accepts. NodeIP can in practice be
	// a public IP on Scaleway, so the bind address alone isn't a
	// security boundary; this allowlist is. Empty defers to
	// DefaultScrapeAllowedCIDRs at forwarder construction.
	ScrapeAllowedCIDRs []*net.IPNet

	Tart     *tart.Client
	Resolver *envresolver.Resolver
	Store    *Store

	// TokenMinter mints projected ServiceAccount tokens for Pods
	// whose Spec.AutomountServiceAccountToken is true. Optional —
	// when nil, no token is staged (the env file is the only file
	// shared into the VM).
	TokenMinter satoken.Minter

	// GC reclaims disk when a Tart pull errors with no-space. Optional
	// — when nil, the reconciler just surfaces the error.
	GC *Collector

	// Recorder emits Pod Events (e.g. "CreatingVM") so the
	// Scheduled→Running gap — previously a silent dead zone with no
	// events between the scheduler placing the Pod and the VM getting
	// an IP — is visible in `kubectl describe`. Optional; nil skips
	// event emission.
	Recorder record.EventRecorder
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
		// finalizer and force-complete the API object deletion. Order
		// matters: the Pod must not disappear from kubectl's view
		// while the VM is still running on the host.
		//
		// This branch must run BEFORE the terminal-phase early-return
		// below: when a Pod's VM exits cleanly we publish
		// Phase=Succeeded, and shortly after the owning controller
		// issues a Delete on it. Both conditions (terminal phase AND
		// DeletionTimestamp set) hold simultaneously from that moment
		// on. If the terminal-phase check ran first, the reconciler
		// would short-circuit and never remove the finalizer — Pods
		// would sit forever in `Terminating` with the finalizer
		// holding them open and the runners-controller's reap path
		// (which correctly skips Pods that already have a
		// DeletionTimestamp) unable to do anything about it. We
		// shipped exactly that bug for several days; the fix is the
		// ordering you see here.
		if err := r.deletePod(ctx, pod); err != nil {
			logger.Error(err, "delete failed; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		if err := r.completePodDeletion(ctx, pod); err != nil {
			if apierrors.IsConflict(err) || apierrors.IsNotFound(err) {
				return ctrl.Result{}, nil
			}
			logger.Error(err, "complete pod deletion; will retry")
			return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
		}
		return ctrl.Result{}, nil
	}

	// Pod already moved to a terminal phase (we marked it Succeeded
	// after the VM exited, or someone else marked it Failed). Do
	// nothing here: re-running createPod would clone+boot a fresh
	// VM for a Pod the workload controller is about to garbage-
	// collect, and the watcher needs the Pod to stay in the
	// terminal phase long enough to observe the transition. Finalizer
	// removal happens via the DeletionTimestamp branch above the
	// moment the owning controller issues a Delete on the Pod.
	if pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
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
		// Patch landed. Requeue explicitly instead of relying solely on
		// the watch to re-fire: a missed or delayed watch event would
		// otherwise leave the Pod Pending with no VM and nothing to
		// re-trigger provisioning until the informer's resync (hours) —
		// the stranded-Pending failure mode seen in prod.
		return ctrl.Result{Requeue: true}, nil
	}

	// If a previous reconcile recorded a RunHandle and the
	// `tart run` process has since exited, surface the right
	// terminal phase here. Two cases:
	//
	//   - `exitErr == nil` is the clean-shutdown path:
	//     dispatch-poll.sh ran a single GitHub Actions job and
	//     issued `shutdown -h now` in the guest, which propagates
	//     back as a zero-status `tart run`. That's a successful
	//     single-shot — PodSucceeded, not Failed. Counting it as
	//     Failed pollutes the failure telemetry and feeds spurious
	//     alerts.
	//   - `exitErr != nil` is the genuine failure path: the guest
	//     crashed 30s into a multi-minute boot, well past Run's 5s
	//     sanity window, or `tart run` itself died. PodFailed so
	//     the owning ReplicaSet schedules a replacement Pod with
	//     a fresh VM.
	//
	// Either way the host-side teardown is the same (delete the
	// Store entry); only the published Phase differs.
	if entry := r.Store.Get(pod.Namespace, pod.Name); entry != nil && entry.Run != nil {
		if exitErr, exited := entry.Run.Exited(); exited {
			_ = r.deleteByKey(ctx, pod.Namespace, pod.Name)

			status := &corev1.PodStatus{Reason: "TartRunExited"}
			if exitErr == nil {
				logger.Info("tart run exited cleanly; marking pod succeeded",
					"vm", entry.VMName, "log", entry.Run.LogPath)
				status.Phase = corev1.PodSucceeded
				status.Message = fmt.Sprintf("tart run exited cleanly (see %s)", entry.Run.LogPath)
			} else {
				logger.Info("tart run exited with error; marking pod failed",
					"vm", entry.VMName, "log", entry.Run.LogPath, "err", exitErr)
				status.Phase = corev1.PodFailed
				status.Message = fmt.Sprintf("tart run exited: %v (see %s)", exitErr, entry.Run.LogPath)
			}

			_ = r.publishStatus(ctx, pod, status)
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

	// First time we provision this Pod's VM. Record the gap from Pod
	// creation to provisioning start — the previously-unmeasured window
	// where a scheduled Pod sits Pending before its VM is even started
	// (the prod bottleneck) — and emit a matching event so the
	// Scheduled→Running gap is no longer a silent dead zone.
	pool := pod.Labels["tuist.dev/runner-pool"]
	if pool == "" {
		pool = "unknown"
	}
	podProvisionDelaySeconds.WithLabelValues(pool).Observe(time.Since(pod.CreationTimestamp.Time).Seconds())
	if r.Recorder != nil {
		r.Recorder.Event(pod, corev1.EventTypeNormal, "CreatingVM", "starting Tart VM provisioning (clone + run)")
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

	// Bind to the Node IP rather than 0.0.0.0 so the forwarder is
	// only reachable from the cluster network — anything Alloy can
	// see, but not random clients on the host's other interfaces
	// (BMC, public WAN if any). The Pod also declares a hostPort:9091
	// in its container spec which makes the scheduler enforce
	// uniqueness across Pods on the same Node, so the bind here is
	// guaranteed not to clash with another scrape-opted-in Pod —
	// belt-and-braces, podStatus drops the PodIP rewrite when this
	// errors out so a runtime collision still means "no Alloy traffic
	// to this Pod" rather than "Alloy scrapes the wrong VM."
	listenAddr := fmt.Sprintf("%s:%d", r.NodeIP, port)
	allowed := r.ScrapeAllowedCIDRs
	if len(allowed) == 0 {
		allowed = DefaultScrapeAllowedCIDRs()
	}
	fw, err := NewForwarder(listenAddr, resolve, ForwarderOptions{AllowedCIDRs: allowed})
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
	// VM teardown only. The caller removes the finalizer and force-
	// completes the API object deletion afterward.
	return r.deleteByKey(ctx, pod.Namespace, pod.Name)
}

func (r *Reconciler) completePodDeletion(ctx context.Context, pod *corev1.Pod) error {
	if controllerutil.RemoveFinalizer(pod, PodFinalizer) {
		if err := r.CachedClient.Update(ctx, pod); err != nil {
			return err
		}
	}

	// The API server usually removes a terminating Pod once its
	// finalizers are gone, but a stale object can keep the hostPort and
	// topology slot occupied indefinitely. Make deletion explicit after
	// VM cleanup so rollouts cannot get stuck behind old Pod objects.
	return r.CachedClient.Delete(ctx, pod, client.GracePeriodSeconds(0))
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
	if r.NodeIP != "" {
		hostIP = r.NodeIP
	}
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
		// First time we see an IP for this VM is the
		// Pending→Running transition — observe the boot duration
		// once per VM. recoverState-materialised entries set
		// StartTS to "now" rather than the original clone time,
		// so an entry without an original StartTS lookalike
		// (BootObserved already true after recovery) is suppressed
		// — observing a "boot" we never witnessed would skew the
		// histogram toward zero.
		if !entry.BootObserved && !entry.StartTS.IsZero() {
			pool := pod.Labels["tuist.dev/runner-pool"]
			if pool == "" {
				pool = "unknown"
			}
			vmBootDurationSeconds.WithLabelValues(pool).Observe(time.Since(entry.StartTS.Time).Seconds())
			entry.BootObserved = true
		}
		// For Pods that opt into scraping we report the host IP as
		// the Pod IP so existing pod-IP-based discovery (Alloy's
		// annotationAutodiscovery, Service endpoints, kube-state-
		// metrics) targets the host-side forwarder rather than the
		// VM's NAT-private address. Spin the forwarder up here too
		// — first podStatus after VM boot is when an upstream IP
		// becomes available. The PodIP rewrite is gated on the
		// forwarder actually starting: a bind failure (eg. another
		// Pod already on this host won the hostPort race) leaves
		// PodIP at the unreachable VM IP so Alloy harmlessly
		// times out instead of mis-scraping the other Pod's VM.
		// The Pod stays Ready because the BEAM is up regardless of
		// scraping plumbing — Oban consumption doesn't depend on it.
		status.PodIP = ip
		if _, scraped := metricsPortFromPod(pod); scraped && r.NodeIP != "" {
			if err := r.startMetricsForwarder(pod, entry); err != nil {
				log.FromContext(ctx).Error(err, "start metrics forwarder; leaving PodIP at VM IP so Alloy doesn't mis-scrape",
					"pod", pod.Namespace+"/"+pod.Name)
			} else {
				status.PodIP = r.NodeIP
			}
		}
		status.Conditions = []corev1.PodCondition{
			{Type: corev1.PodReady, Status: corev1.ConditionTrue},
		}
		// tart-kubelet runs the Pod as a single VM with no per-container
		// CRI, so the API server receives no containerStatuses on its own
		// and `kubectl get pods` reads 0/N READY for a healthy VM. Mirror
		// the Ready condition above into synthesized statuses so the READY
		// column reflects the running workload.
		status.ContainerStatuses = runningContainerStatuses(pod, entry.VMName, entry.StartTS)
	} else {
		// VM process is alive but IP isn't yet available — the
		// guest is still booting. Pending is the right read.
		status.Phase = corev1.PodPending
	}
	return status, nil
}

// runningContainerStatuses synthesizes the per-container statuses for a
// Pod whose Tart VM is up and serving. tart-kubelet has no per-container
// runtime to source them from, so without this a healthy VM reports 0/N
// READY in `kubectl get pods` even though its Pod Ready condition is
// true. The statuses mirror that condition: VM running with an IP means
// the workload is serving, so each container reads Ready + Running. Pod
// ↔ VM is 1:1 (multi-container Pods are rejected at admission), so this
// is effectively a single status.
func runningContainerStatuses(pod *corev1.Pod, vmName string, startedAt metav1.Time) []corev1.ContainerStatus {
	started := true
	statuses := make([]corev1.ContainerStatus, 0, len(pod.Spec.Containers))
	for _, c := range pod.Spec.Containers {
		statuses = append(statuses, corev1.ContainerStatus{
			Name:         c.Name,
			Image:        c.Image,
			ContainerID:  "tart://" + vmName,
			Ready:        true,
			Started:      &started,
			RestartCount: 0,
			State: corev1.ContainerState{
				Running: &corev1.ContainerStateRunning{StartedAt: startedAt},
			},
		})
	}
	return statuses
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
//
// MetricsForwarder is the host-side TCP relay (host_ip:port →
// vm_ip:port) for Pods that opt into Prometheus scraping via the
// `prometheus.io/scrape` annotation. nil for Pods without the
// annotation and for entries materialised by recoverState — the
// next reconcile-and-restart cycle will set one up.
type Entry struct {
	VMName  string
	StartTS metav1.Time
	Run     *tart.RunHandle
	// BootObserved is true after we've recorded
	// `tart_kubelet_vm_boot_duration_seconds` for this VM. The
	// histogram observes once per VM (at the Pending→Running
	// transition), not per reconcile — observing on every
	// podStatus would skew the distribution toward `0` for
	// long-lived VMs that get reconciled hundreds of times.
	BootObserved     bool
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
