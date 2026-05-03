// Command tart-kubelet runs on a Mac mini, joins it to the cluster as
// a real Node, and translates Pods scheduled to that Node into Tart
// VMs. It is "kubelet, but for Tart" — same shape, none of cAdvisor's
// hard Linux-isms, no CSI.
//
// One process per Mac mini, started by launchd as root. Reads its
// kubeconfig from disk (provisioned by the CAPI provider during host
// bootstrap), watches the API server for Pods scheduled to its
// hostname-derived Node, and drives `tart` locally to execute them.
package main

import (
	"context"
	"flag"
	"os"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	cache "sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/envresolver"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/nodeagent"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/podagent"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
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
		hostCPU      int
		hostMemoryMB int
		maxPods      int
		metricsAddr  string
		probeAddr    string
		tartBinary   string
	)
	flag.StringVar(&nodeName, "node-name", envOr("TART_KUBELET_NODE_NAME", ""), "Node name to register as. Defaults to os.Hostname() when empty.")
	flag.IntVar(&hostCPU, "host-cpu", 8, "CPU cores to advertise on the Node.")
	flag.IntVar(&hostMemoryMB, "host-memory-mb", 16384, "Memory MB to advertise on the Node.")
	flag.IntVar(&maxPods, "max-pods", 8, "Max concurrent Pods (= concurrent Tart VMs) on this Node.")
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint.")
	flag.StringVar(&tartBinary, "tart-binary", "/opt/homebrew/bin/tart", "Path to the local tart CLI.")

	// `--kubeconfig` is registered automatically by controller-runtime's
	// init() (sigs.k8s.io/controller-runtime/pkg/client/config). Defining
	// our own flag of the same name here would panic with `flag
	// redefined`; rely on theirs and let the launchd plist pass the path.
	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	if nodeName == "" {
		hostname, err := os.Hostname()
		if err != nil {
			setupLog.Error(err, "resolve hostname for default node name")
			os.Exit(1)
		}
		nodeName = hostname
	}

	// controller-runtime's GetConfigOrDie resolves config via (in order):
	//   1. `--kubeconfig` flag value (set by launchd plist)
	//   2. KUBECONFIG env
	//   3. in-cluster service-account mount (won't apply on Mac mini)
	//   4. ~/.kube/config
	cfg := ctrl.GetConfigOrDie()

	// Narrow the cache: we only ever care about Pods scheduled to this
	// Node and the Node object itself. Cluster-wide watches on a node-
	// embedded agent are wasteful; this keeps memory + apiserver load
	// small per Mac mini.
	mgr, err := ctrl.NewManager(cfg, manager.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		Cache: cache.Options{
			ByObject: map[client.Object]cache.ByObject{
				&corev1.Pod{}: {
					Field: pickPodsForNode(nodeName),
				},
				&corev1.Node{}: {
					Field: pickThisNode(nodeName),
				},
			},
		},
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	tartClient := tart.New()
	tartClient.Binary = tartBinary

	resolver := &envresolver.Resolver{K8s: mgr.GetAPIReader()}

	store := podagent.NewStore()

	gcCollector := &podagent.Collector{
		K8s:      mgr.GetAPIReader(),
		Tart:     tartClient,
		NodeName: nodeName,
		Interval: 5 * time.Minute,
		Store:    store,
	}
	if err := mgr.Add(gcCollector); err != nil {
		setupLog.Error(err, "add gc collector")
		os.Exit(1)
	}

	// Hydrate the Pod ↔ VM map from on-host state before reconciles
	// fire. After a kubelet restart the in-memory store is empty but
	// any Tart VMs from before the restart are still running
	// (`nohup`-detached). Without this pass the next Reconcile would
	// see "no entry for this Pod", check `tart get`, find the existing
	// VM, and stop+delete it as stale — killing a healthy workload on
	// every kubelet update. We do this synchronously, before
	// mgr.Start, using a fresh non-cached client.
	if err := recoverState(cfg, scheme, tartClient, store, nodeName); err != nil {
		setupLog.Error(err, "state recovery failed; reconciles may treat existing VMs as stale")
	}

	if err := (&podagent.Reconciler{
		CachedClient: mgr.GetClient(),
		NodeName:     nodeName,
		Tart:         tartClient,
		Resolver:     resolver,
		Store:        store,
		GC:           gcCollector,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup pod reconciler")
		os.Exit(1)
	}

	if err := mgr.Add(&nodeagent.Maintainer{
		Client:    mgr.GetClient(),
		NodeName:  nodeName,
		CPU:       hostCPU,
		MemoryMB:  hostMemoryMB,
		MaxPods:   maxPods,
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

	setupLog.Info("starting tart-kubelet", "node", nodeName)
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

// pickPodsForNode narrows the Pod informer with a server-side field
// selector — the API server filters by spec.nodeName before sending us
// anything. Same trick the upstream kubelet uses.
func pickPodsForNode(nodeName string) fields.Selector {
	return fields.SelectorFromSet(fields.Set{"spec.nodeName": nodeName})
}

// pickThisNode narrows the Node informer to just our Node.
func pickThisNode(nodeName string) fields.Selector {
	return fields.SelectorFromSet(fields.Set{"metadata.name": nodeName})
}

// recoverState rebuilds the Pod ↔ VM map by intersecting the host's
// current Tart VMs with the Pods scheduled to this Node. Any Pod whose
// VM name is present in `tart list` is recorded in the Store so the
// reconciler treats the VM as live instead of attempting to
// re-provision it.
//
// Best-effort. A miss (no Tart VM matching a scheduled Pod) is left
// alone — the reconciler will recreate it. A spurious extra Tart VM
// (no matching Pod) is also left; the reconciler garbage-collects on
// Pod deletion in steady state, and an explicit `tart-kubelet gc`
// pass can be added later if drift becomes a real problem.
func recoverState(
	cfg *clientcmdConfig,
	scheme *runtime.Scheme,
	tartClient *tart.Client,
	store *podagent.Store,
	nodeName string,
) error {
	c, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	vms, err := tartClient.List(ctx)
	if err != nil {
		return err
	}
	// Probe each local VM with `tart ip` — that's the only reliable
	// liveness signal under Tart 2.32 (the on-disk State field stays
	// "stopped" for backgrounded VMs even when they're running).
	// Stopped clones (left over from a previous kubelet kill) get
	// skipped here; createPod will pick them up and start them.
	live := make(map[string]bool, len(vms))
	for _, vm := range vms {
		if vm.Source != "local" {
			continue
		}
		if ip, ipErr := tartClient.IP(ctx, vm.Name); ipErr == nil && ip != "" {
			live[vm.Name] = true
		}
	}

	pods := &corev1.PodList{}
	if err := c.List(ctx, pods, client.MatchingFields{"spec.nodeName": nodeName}); err != nil {
		return err
	}

	matched := 0
	for i := range pods.Items {
		pod := &pods.Items[i]
		vmName := podagent.VMNameForPod(pod)
		if !live[vmName] {
			continue
		}
		startTS := pod.Status.StartTime
		if startTS == nil {
			now := metav1.Now()
			startTS = &now
		}
		store.Put(pod.Namespace, pod.Name, &podagent.Entry{
			VMName:  vmName,
			StartTS: *startTS,
		})
		matched++
	}
	setupLog.Info("recovered VM state", "node", nodeName, "tart_vms", len(vms), "matched_pods", matched)
	return nil
}

// clientcmdConfig is an alias so the signature of recoverState reads
// without dragging the rest-config dep into the main signature line.
type clientcmdConfig = rest.Config
