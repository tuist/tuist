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
	"time"

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
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
	"github.com/tuist/tuist/infra/runners-controller/internal/sessions"
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
		sessionsURL         string
		watchedNS           string
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.StringVar(&dispatchURL, "dispatch-url", envOr("TUIST_RUNNER_DISPATCH_URL", ""),
		"Externally-reachable dispatch URL the runner Pod's VM polls for its JIT config. Used by macOS Tart VMs (bypass CNI via vmnet). Required.")
	flag.StringVar(&dispatchInternalURL, "dispatch-internal-url", envOr("TUIST_RUNNER_DISPATCH_INTERNAL_URL", ""),
		"In-cluster (Service-based) dispatch URL injected into Linux pool Pods. Linux Pods can't reach the public ingress IP from inside the cluster (Hetzner Cloud LB has no hairpin). Optional; falls back to --dispatch-url when empty.")
	flag.StringVar(&scalingSignalsURL, "scaling-signals-url", envOr("TUIST_SCALING_SIGNALS_URL", ""),
		"URL the autoscaler reconciler GETs for fleet load signals (`?fleet=<name>` appended). Optional; if empty, autoscaling is silently disabled (existing macOS pools work unchanged).")
	flag.StringVar(&sessionsURL, "sessions-url", envOr("TUIST_RUNNER_SESSIONS_URL", ""),
		"URL prefix the pod-lifecycle reconciler POSTs Pod terminal-phase events to (`/pods/stopped` is appended). Required for billing; until configured, the server falls back to its safety clamp.")
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
		signalsClient := scaling.NewClient(scalingSignalsURL)
		// Cache just under the poll interval so the fleet-aware pass
		// (which fetches every sibling shape's signals each reconcile)
		// collapses an N-shape fleet's N² requests down to ~N per cycle.
		signalsClient.CacheTTL = 4 * time.Second
		if err := (&controllers.AutoscalerReconciler{
			Client:        mgr.GetClient(),
			Scheme:        mgr.GetScheme(),
			SignalsClient: signalsClient,
		}).SetupWithManager(mgr); err != nil {
			setupLog.Error(err, "setup Autoscaler reconciler")
			os.Exit(1)
		}
	}

	// Pod-lifecycle reconciler watches runner Pods for terminal-
	// phase transitions and reports them to the Tuist server so
	// billing sessions close off K8s-authoritative timestamps
	// rather than the flaky `workflow_job.completed` webhook. When
	// the URL isn't configured we skip wiring it up — the server
	// keeps its max-lifetime safety clamp, which bounds the
	// over-bill while we get the controller plumbed in.
	if sessionsURL != "" {
		if err := (&controllers.PodLifecycleReconciler{
			Client:         mgr.GetClient(),
			Scheme:         mgr.GetScheme(),
			SessionsClient: sessions.NewClient(sessionsURL),
		}).SetupWithManager(mgr); err != nil {
			setupLog.Error(err, "setup PodLifecycle reconciler")
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
