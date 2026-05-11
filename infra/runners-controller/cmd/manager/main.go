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
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/controllers"
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
		metricsAddr string
		probeAddr   string
		dispatchURL string
		watchedNS   string
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.StringVar(&dispatchURL, "dispatch-url", envOr("TUIST_RUNNER_DISPATCH_URL", ""),
		"URL the runner Pod's VM polls for its JIT config. Threaded into every Pod via env. Required.")
	flag.StringVar(&watchedNS, "namespace", envOr("TUIST_RUNNERS_NAMESPACE", "tuist-runners"),
		"Namespace the controller watches. Defaults to tuist-runners.")

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
		Client:      mgr.GetClient(),
		Scheme:      mgr.GetScheme(),
		DispatchURL: dispatchURL,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup RunnerPool reconciler")
		os.Exit(1)
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

// Compile-time check that we're not accidentally pulling unused
// imports if the GC reconciler wires move around.
var _ client.Client = (*controllers.RunnerPoolReconciler)(nil).Client
var _ corev1.Pod
