package main

import (
	"context"
	"errors"
	"flag"
	"os"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/kura-controller/controllers"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(kurav1alpha1.AddToScheme(scheme))
}

func main() {
	var metricsAddr string
	var probeAddr string
	var enableLeaderElection bool
	var watchNamespace string
	var grpcClusterIssuer string
	var publicTLSSecretName string
	var publicTLSDNSNames string
	var stableZone, stableOwner string
	var stableDrain time.Duration
	var otlpTracesEndpoint string
	var deploymentEnvironment string
	var connectivityDiagnosticsInstances string

	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true, "Single-leader election")
	flag.StringVar(&watchNamespace, "watch-namespace", "", "Namespace to watch for KuraInstance resources")
	flag.StringVar(&grpcClusterIssuer, "grpc-cluster-issuer", "", "cert-manager ClusterIssuer backing the per-instance public-host certificate (leaves public TLS unprovisioned when empty)")
	flag.StringVar(&publicTLSSecretName, "public-tls-secret-name", "", "Shared wildcard TLS Secret every public Ingress terminates on (falls back to a per-instance certificate when empty or not yet issued)")
	flag.StringVar(&publicTLSDNSNames, "public-tls-dns-names", "", "Comma-separated names for the shared wildcard Certificate the controller maintains (e.g. *.kura.tuist.dev); leave empty to manage that Certificate elsewhere")
	flag.StringVar(&otlpTracesEndpoint, "otlp-traces-endpoint", "", "Default OTLP traces endpoint injected into managed Kura pods when they do not set one explicitly")
	flag.StringVar(&deploymentEnvironment, "deployment-environment", "production", "Deployment environment injected into managed Kura pods for OpenTelemetry and Sentry")
	flag.StringVar(&connectivityDiagnosticsInstances, "connectivity-diagnostics-instances", "", "Comma-separated exact KuraInstance names enabling built-in connectivity telemetry in watch-namespace")

	flag.StringVar(&stableZone, "stable-dns-zone-id", "", "Delegated cache.tuist.dev Route53 hosted zone; empty disables stable DNS")
	flag.StringVar(&stableOwner, "stable-dns-owner", "", "Unique cluster identity for shared box health checks")
	flag.DurationVar(&stableDrain, "stable-dns-drain", 3720*time.Second, "Minimum rendering retention after provider-observed DNS withdrawal")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))
	probeInstances := splitNames(connectivityDiagnosticsInstances)
	if len(probeInstances) != 0 && watchNamespace == "" {
		setupLog.Error(errors.New("connectivity diagnostics require watch-namespace"), "invalid probe configuration")
		os.Exit(1)
	}

	if len(probeInstances) != 0 {
		if !controllers.ValidConnectivityProfile(deploymentEnvironment) {
			setupLog.Error(errors.New("unsupported connectivity profile"), "invalid probe environment")
			os.Exit(1)
		}
	}

	managerOptions := ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "kura-controller.kura.tuist.dev",
	}
	if watchNamespace != "" {
		managerOptions.Cache = cache.Options{
			DefaultNamespaces: map[string]cache.Config{watchNamespace: {}},
		}
	}

	restConfig := ctrl.GetConfigOrDie()
	// Concurrent reconciles each make a few uncached apiserver calls (the status
	// write, unstructured DNSEndpoint and Certificate reads), which the
	// controller-runtime default of 20 QPS would throttle into a queue of its own.
	restConfig.QPS = 100
	restConfig.Burst = 200

	mgr, err := ctrl.NewManager(restConfig, managerOptions)
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	metricsClient, err := controllers.NewPodMetricsClient(mgr.GetConfig())
	if err != nil {
		setupLog.Error(err, "build pod metrics client")
		os.Exit(1)
	}

	reconciler := &controllers.KuraInstanceReconciler{
		Client:                           mgr.GetClient(),
		APIReader:                        mgr.GetAPIReader(),
		Scheme:                           mgr.GetScheme(),
		GRPCClusterIssuer:                grpcClusterIssuer,
		PublicTLSSecretName:              publicTLSSecretName,
		OTLPTracesEndpoint:               otlpTracesEndpoint,
		Environment:                      deploymentEnvironment,
		MetricsClient:                    metricsClient,
		ConnectivityDiagnosticsInstances: probeInstances,
	}
	if stableZone != "" {
		if watchNamespace == "" {
			setupLog.Error(errors.New("stable DNS requires watch-namespace"), "invalid configuration")
			os.Exit(1)
		}
		if stableDrain < 120*time.Second {
			setupLog.Error(errors.New("stable DNS drain must cover propagation and record TTL"), "invalid drain")
			os.Exit(1)
		}
		provider, err := controllers.NewRoute53StableDNS(context.Background(), stableZone, stableOwner)
		if err != nil {
			setupLog.Error(err, "create stable DNS provider")
			os.Exit(1)
		}
		reconciler.StableDNS, reconciler.StableDrain = provider, stableDrain
		if err := mgr.Add(&controllers.StableHealthCollector{Reconciler: reconciler, Provider: provider, Namespace: watchNamespace}); err != nil {
			setupLog.Error(err, "add health collector")
			os.Exit(1)
		}
	}
	if err := reconciler.SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup KuraInstanceReconciler")
		os.Exit(1)
	}
	if publicTLSDNSNames != "" {
		names := splitNames(publicTLSDNSNames)
		if err := mgr.Add(&controllers.PublicWildcardCertificate{
			Client:        mgr.GetClient(),
			Namespace:     watchNamespace,
			SecretName:    publicTLSSecretName,
			DNSNames:      names,
			ClusterIssuer: grpcClusterIssuer,
		}); err != nil {
			setupLog.Error(err, "setup PublicWildcardCertificate")
			os.Exit(1)
		}
	}

	if err := (&controllers.PeerDemuxReconciler{
		Client:    mgr.GetClient(),
		APIReader: mgr.GetAPIReader(),
		Scheme:    mgr.GetScheme(),
		Image:     os.Getenv("KURA_PEER_DEMUX_IMAGE"),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup PeerDemuxReconciler")
		os.Exit(1)
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up ready check")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}

func splitNames(value string) []string {
	var names []string
	for _, name := range strings.Split(value, ",") {
		if trimmed := strings.TrimSpace(name); trimmed != "" {
			names = append(names, trimmed)
		}
	}
	return names
}
