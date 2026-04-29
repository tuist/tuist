// Command vk-applesilicon registers a virtual Node backed by the Mac
// mini fleet (CAPI-managed) and translates Pods scheduled onto that
// Node into Tart VMs running on one of the Mac minis.
//
// Why we don't use the upstream virtual-kubelet library: its v1.12
// release pulls a tangle of k8s.io/apiserver internals that don't
// build cleanly with our pinned k8s + Go toolchain. The shape we
// need is small enough to implement with controller-runtime's Pod
// watcher + a periodic Node-status updater.
package main

import (
	"context"
	"flag"
	"os"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/tuist/tuist/infra/vk-applesilicon/internal/hosts"
	"github.com/tuist/tuist/infra/vk-applesilicon/internal/vkprovider"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	_ = clientgoscheme.AddToScheme(scheme)
}

func main() {
	var (
		nodeName     string
		namespace    string
		sshKeyPath   string
		sshUser      string
		hostCPU      int
		hostMemoryMB int
		metricsAddr  string
		probeAddr    string
	)
	flag.StringVar(&nodeName, "node-name", envOr("VK_NODE_NAME", "tuist-macos-fleet"), "Virtual Node name")
	flag.StringVar(&namespace, "namespace", envOr("VK_NAMESPACE", "default"), "Namespace where ScalewayAppleSiliconMachines live")
	flag.StringVar(&sshKeyPath, "ssh-key", envOr("VK_SSH_KEY_PATH", "/etc/vk-applesilicon/ssh/id_ed25519"), "Path to per-fleet SSH private key")
	flag.StringVar(&sshUser, "ssh-user", envOr("VK_SSH_USER", "m1"), "SSH login on each Mac mini")
	flag.IntVar(&hostCPU, "host-cpu", 8, "CPU cores per Mac mini (capacity advertising)")
	flag.IntVar(&hostMemoryMB, "host-memory-mb", 16384, "Memory MB per Mac mini (capacity advertising)")
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	sshKey, err := os.ReadFile(sshKeyPath)
	if err != nil {
		setupLog.Error(err, "read ssh key", "path", sshKeyPath)
		os.Exit(1)
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), manager.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	disc := &hosts.Discovery{
		Client:          mgr.GetClient(),
		Namespace:       namespace,
		DefaultCPU:      hostCPU,
		DefaultMemoryMB: hostMemoryMB,
		DefaultSSHUser:  sshUser,
	}

	provider := vkprovider.New(nodeName, sshKey, disc.Hosts)
	defer provider.Stop()

	// 1. Pod controller: any Pod scheduled to our virtual Node fires
	//    Create / Delete on the provider.
	if err := (&podReconciler{
		Client:   mgr.GetClient(),
		Provider: provider,
		NodeName: nodeName,
	}).setup(mgr); err != nil {
		setupLog.Error(err, "setup pod reconciler")
		os.Exit(1)
	}

	// 2. Node maintainer: ensures the virtual Node object exists +
	//    refreshes its status on a heartbeat.
	if err := mgr.Add(&nodeMaintainer{
		Client:    mgr.GetClient(),
		NodeName:  nodeName,
		Provider:  provider,
		Heartbeat: 30 * time.Second,
	}); err != nil {
		setupLog.Error(err, "add node maintainer")
		os.Exit(1)
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up healthz")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up readyz")
		os.Exit(1)
	}

	setupLog.Info("starting vk-applesilicon", "node", nodeName, "namespace", namespace)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// === Pod reconciler =========================================================

type podReconciler struct {
	client.Client
	Provider *vkprovider.Provider
	NodeName string
}

func (r *podReconciler) setup(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Pod{}, builder.WithPredicates(predicate.NewPredicateFuncs(func(o client.Object) bool {
			pod, ok := o.(*corev1.Pod)
			return ok && pod.Spec.NodeName == r.NodeName
		}))).
		Complete(r)
}

func (r *podReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("pod", req.NamespacedName)

	pod := &corev1.Pod{}
	if err := r.Get(ctx, req.NamespacedName, pod); err != nil {
		if apierrors.IsNotFound(err) {
			// Pod was deleted; provider may still hold state for it.
			tomb := &corev1.Pod{}
			tomb.Namespace = req.Namespace
			tomb.Name = req.Name
			_ = r.Provider.DeletePod(ctx, tomb)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !pod.DeletionTimestamp.IsZero() {
		if err := r.Provider.DeletePod(ctx, pod); err != nil {
			logger.Error(err, "delete pod failed; will retry")
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		return ctrl.Result{}, nil
	}

	// CreatePod is idempotent (provider tracks state by Pod key).
	if err := r.Provider.CreatePod(ctx, pod); err != nil {
		logger.Error(err, "create pod failed; will retry")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Sync Pod status from the underlying Tart VM.
	status, err := r.Provider.GetPodStatus(ctx, pod.Namespace, pod.Name)
	if err != nil || status == nil {
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}
	pod.Status = *status
	if err := r.Status().Update(ctx, pod); err != nil {
		logger.Error(err, "status update")
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}
	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

// === Node maintainer ========================================================

type nodeMaintainer struct {
	Client    client.Client
	NodeName  string
	Provider  *vkprovider.Provider
	Heartbeat time.Duration
}

func (m *nodeMaintainer) Start(ctx context.Context) error {
	if err := m.ensureNode(ctx); err != nil {
		return err
	}
	t := time.NewTicker(m.Heartbeat)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			if err := m.refreshStatus(ctx); err != nil {
				log.FromContext(ctx).Error(err, "refresh node status")
			}
		}
	}
}

func (m *nodeMaintainer) ensureNode(ctx context.Context) error {
	node := &corev1.Node{}
	err := m.Client.Get(ctx, types.NamespacedName{Name: m.NodeName}, node)
	if apierrors.IsNotFound(err) {
		node.Name = m.NodeName
		m.Provider.ConfigureNode(ctx, node)
		return m.Client.Create(ctx, node)
	}
	return err
}

func (m *nodeMaintainer) refreshStatus(ctx context.Context) error {
	node := &corev1.Node{}
	if err := m.Client.Get(ctx, types.NamespacedName{Name: m.NodeName}, node); err != nil {
		return err
	}
	m.Provider.ConfigureNode(ctx, node)
	// Heartbeat: bump LastHeartbeatTime on Ready condition.
	for i, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady {
			node.Status.Conditions[i].LastHeartbeatTime = metav1.Now()
		}
	}
	return m.Client.Status().Update(ctx, node)
}

// silence resource import unused (we only need it for the side-effect of
// type registration in vkprovider's ConfigureNode).
var _ = resource.MustParse
