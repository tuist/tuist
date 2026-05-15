// Command tuist-runners-controller reconciles RunnerPool CRDs into
// Pod + ServiceAccount pairs that the Tuist server's dispatch
// endpoint can authenticate via the Kubernetes TokenReview API.
//
// Runs as one Deployment in the chart's release namespace. Uses
// controller-runtime's leader election so multiple replicas don't
// race on Pod creation.
package main

import (
	"flag"
	"os"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/clientcmd"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/controllers"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	_ = clientgoscheme.AddToScheme(scheme)
	_ = tuistv1.AddToScheme(scheme)
}

func main() {
	var (
		metricsAddr         string
		probeAddr           string
		dispatchURL         string
		dispatchInternalURL string
		scalingSignalsURL   string
		watchedNS           string
		mgmtKubeconfig      string
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.StringVar(&dispatchURL, "dispatch-url", envOr("TUIST_RUNNER_DISPATCH_URL", ""),
		"Externally-reachable dispatch URL the runner Pod's VM polls for its JIT config. Used by macOS Tart VMs (bypass CNI via vmnet). Required.")
	flag.StringVar(&dispatchInternalURL, "dispatch-internal-url", envOr("TUIST_RUNNER_DISPATCH_INTERNAL_URL", ""),
		"In-cluster (Service-based) dispatch URL injected into Linux pool Pods. Linux Pods can't reach the public ingress IP from inside the cluster (Hetzner Cloud LB has no hairpin). Optional; falls back to --dispatch-url when empty.")
	flag.StringVar(&scalingSignalsURL, "scaling-signals-url", envOr("TUIST_SCALING_SIGNALS_URL", ""),
		"URL the autoscaler reconciler GETs for fleet load signals (`?fleet=<name>` appended). Optional; if empty, autoscaling is silently disabled (existing macOS pools work unchanged).")
	flag.StringVar(&watchedNS, "namespace", envOr("TUIST_RUNNERS_NAMESPACE", "tuist-runners"),
		"Namespace the controller watches. Defaults to tuist-runners.")
	flag.StringVar(&mgmtKubeconfig, "mgmt-kubeconfig", envOr("TUIST_MGMT_KUBECONFIG", ""),
		"Path to a kubeconfig file for the management cluster (the one running CAPI controllers). When set, the autoscaler also patches the bound `MachineDeployment.spec.replicas` after each pool scale event. Optional; without it, pools that reference an MD log a warning and the MD layer stays static.")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	if dispatchURL == "" {
		setupLog.Error(nil, "--dispatch-url required")
		os.Exit(1)
	}

	cfg := ctrl.GetConfigOrDie()

	mgr, err := ctrl.NewManager(cfg, manager.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         true,
		LeaderElectionID:       "runners-controller.tuist.dev",
		// Watch only the runners namespace. The controller has no
		// reason to inspect Pods / SAs anywhere else, and
		// narrowing the cache cuts memory + apiserver load.
		Cache: cache.Options{
			DefaultNamespaces: map[string]cache.Config{watchedNS: {}},
		},
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	if err := (&controllers.RunnerPoolReconciler{
		Client:              mgr.GetClient(),
		Scheme:              mgr.GetScheme(),
		DispatchURL:         dispatchURL,
		DispatchInternalURL: dispatchInternalURL,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup RunnerPool reconciler")
		os.Exit(1)
	}

	// Autoscaler reconciler runs alongside the primary one. When
	// the scaling URL isn't configured (the v1 macOS-only chart
	// shape) we skip wiring it up — autoscaling pools fail open
	// (no scaling-driven changes), static pools work as before.
	if scalingSignalsURL != "" {
		var mgmtClient client.Client
		if mgmtKubeconfig != "" {
			mc, err := buildMgmtClient(mgmtKubeconfig)
			if err != nil {
				setupLog.Error(err, "build management-cluster client; MD scaling will be disabled")
			} else {
				mgmtClient = mc
				setupLog.Info("management-cluster kubeconfig loaded; MD scaling enabled")
			}
		}
		if err := (&controllers.AutoscalerReconciler{
			Client:        mgr.GetClient(),
			Scheme:        mgr.GetScheme(),
			SignalsClient: scaling.NewClient(scalingSignalsURL),
			MgmtClient:    mgmtClient,
		}).SetupWithManager(mgr); err != nil {
			setupLog.Error(err, "setup Autoscaler reconciler")
			os.Exit(1)
		}
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up readiness check")
		os.Exit(1)
	}

	setupLog.Info("starting runners-controller", "namespace", watchedNS)
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

// buildMgmtClient constructs a controller-runtime client.Client
// against the management cluster's API server, given the path to a
// kubeconfig file mounted on the Pod. We use the default scheme
// (clientgoscheme) since the only management-cluster type we touch
// (`cluster.x-k8s.io/v1beta1.MachineDeployment`) is handled via
// unstructured — pulling the full CAPI module to set one int field
// isn't worth the dep cost.
func buildMgmtClient(kubeconfigPath string) (client.Client, error) {
	cfg, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		return nil, err
	}
	return client.New(cfg, client.Options{Scheme: scheme})
}

// Compile-time check that we're not accidentally pulling unused
// imports if the GC reconciler wires move around. The previous
// form dereferenced a nil *RunnerPoolReconciler at package-init
// time and segfaulted before main() ran; these versions are
// type-only (no value evaluation, no nil deref).
var (
	_ client.Client = (client.Client)(nil)
	_               = controllers.RunnerPoolReconciler{}
	_               = controllers.AutoscalerReconciler{}
	_               = corev1.Pod{}
)
