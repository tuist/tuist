// Package podagent watches Pods scheduled to this Node and translates
// them into Tart VMs. Pod ↔ VM is 1:1; multi-container Pods are
// rejected at admission time (init containers, sidecars, ephemeral
// containers all unsupported on this runtime).
package podagent

import (
	"context"
	"fmt"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/envresolver"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

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
}

// SetupWithManager wires the reconciler with a NodeName predicate so
// we only see Pods k8s scheduled here.
func (r *Reconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Pod{}, builder.WithPredicates(predicate.NewPredicateFuncs(func(o client.Object) bool {
			pod, ok := o.(*corev1.Pod)
			return ok && pod.Spec.NodeName == r.NodeName
		}))).
		Complete(r)
}

func (r *Reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pod", req.NamespacedName)

	pod := &corev1.Pod{}
	if err := r.CachedClient.Get(ctx, req.NamespacedName, pod); err != nil {
		if apierrors.IsNotFound(err) {
			// Pod was deleted; tear down the VM if we still hold it.
			r.deleteByKey(ctx, req.Namespace, req.Name)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !pod.DeletionTimestamp.IsZero() {
		if err := r.deletePod(ctx, pod); err != nil {
			logger.Error(err, "delete failed; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		return ctrl.Result{}, nil
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
func (r *Reconciler) createPod(ctx context.Context, pod *corev1.Pod) error {
	if len(pod.Spec.Containers) != 1 {
		return fmt.Errorf("pod %s/%s has %d containers; tart-kubelet expects exactly 1",
			pod.Namespace, pod.Name, len(pod.Spec.Containers))
	}

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

	if err := r.Tart.Pull(ctx, c.Image); err != nil {
		return fmt.Errorf("tart pull: %w", err)
	}

	// If a stale clone of the same name exists from a previous boot
	// (kubelet restart, host reboot mid-clone), drop it — we'll
	// recreate cleanly. `Get` returns (nil,nil) for missing VMs.
	if vm, _ := r.Tart.Get(ctx, vmName); vm != nil {
		_ = r.Tart.Stop(ctx, vmName, 5*time.Second)
		_ = r.Tart.Delete(ctx, vmName)
	}

	if err := r.Tart.Clone(ctx, c.Image, vmName); err != nil {
		return fmt.Errorf("tart clone: %w", err)
	}

	if err := r.Tart.Run(ctx, vmName, []string{"env:" + envDir + ":ro"}); err != nil {
		return fmt.Errorf("tart run: %w", err)
	}

	r.Store.Put(pod.Namespace, pod.Name, &Entry{
		VMName:  vmName,
		StartTS: metav1.Now(),
	})
	return nil
}

func (r *Reconciler) deletePod(ctx context.Context, pod *corev1.Pod) error {
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
// Tart 2.32's `get` doesn't update state for backgrounded VMs, so we
// use `tart ip` as the liveness probe — non-empty IP ⇒ running.
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

	ip, err := r.Tart.IP(ctx, entry.VMName)
	if err == nil && ip != "" {
		status.Phase = corev1.PodRunning
		status.PodIP = ip
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

// VMNameForPod produces a Tart-safe VM name. Tart accepts alphanum +
// dashes; Pod names are already DNS-1123 (lowercase alphanum + dashes)
// so we just join namespace + name with a length cap.
//
// Exported so the kubelet's startup recovery pass can match running
// Tart VMs back to the Pods that created them after an agent restart.
func VMNameForPod(pod *corev1.Pod) string {
	name := pod.Namespace + "-" + pod.Name
	const max = 63
	if len(name) > max {
		name = name[:max]
	}
	return name
}

// === In-memory Pod ↔ VM map ================================================

// Entry is the kubelet-side bookkeeping for one running Pod.
type Entry struct {
	VMName  string
	StartTS metav1.Time
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
