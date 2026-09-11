package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

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
	var regionalRoutingConfig string
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

	flag.StringVar(&regionalRoutingConfig, "regional-routing-config", "", "JSON array of regional wildcard domains and existing host-network ingress DaemonSets")

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

	regions, err := controllers.ParseRegionalRouting(regionalRoutingConfig)
	if err != nil {
		setupLog.Error(err, "parse --regional-routing-config")
		os.Exit(1)
	}
	if len(regions) > 0 {
		for _, required := range []struct{ name, value string }{
			{"watch-namespace", watchNamespace}, {"public-tls-secret-name", publicTLSSecretName},
			{"public-tls-dns-names", publicTLSDNSNames}, {"grpc-cluster-issuer", grpcClusterIssuer},
		} {
			if strings.TrimSpace(required.value) == "" {
				setupLog.Error(fmt.Errorf("--%s is required", required.name), "invalid regional routing configuration")
				os.Exit(1)
			}
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

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), managerOptions)
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	metricsClient, err := controllers.NewPodMetricsClient(mgr.GetConfig())
	if err != nil {
		setupLog.Error(err, "build pod metrics client")
		os.Exit(1)
	}

	if err := (&controllers.KuraInstanceReconciler{
		Client:                           mgr.GetClient(),
		APIReader:                        mgr.GetAPIReader(),
		Scheme:                           mgr.GetScheme(),
		GRPCClusterIssuer:                grpcClusterIssuer,
		PublicTLSSecretName:              publicTLSSecretName,
		OTLPTracesEndpoint:               otlpTracesEndpoint,
		Environment:                      deploymentEnvironment,
		MetricsClient:                    metricsClient,
		ConnectivityDiagnosticsInstances: probeInstances,
		RegionalRouting:                  regions,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup KuraInstanceReconciler")
		os.Exit(1)
	}
	if publicTLSDNSNames != "" {
		names := splitNames(publicTLSDNSNames)
		for _, region := range regions {
			names = append(names, "*."+region.Domain)
		}
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

	if len(regions) > 0 {
		if err := mgr.Add(&controllers.RegionalDNS{Client: mgr.GetClient(), APIReader: mgr.GetAPIReader(), Namespace: watchNamespace, Regions: regions}); err != nil {
			setupLog.Error(err, "setup regional DNS")
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
