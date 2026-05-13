package main

import (
	"flag"
	"os"

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
	var cloudflareAccountID string
	var cloudflareZoneID string
	var cloudflareAPIToken string

	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true, "Single-leader election")
	flag.StringVar(&watchNamespace, "watch-namespace", "", "Namespace to watch for KuraInstance resources")
	flag.StringVar(&grpcClusterIssuer, "grpc-cluster-issuer", "", "cert-manager ClusterIssuer to use for gRPC TLS certificates (leaves gRPC plaintext when empty)")
	flag.StringVar(&cloudflareAccountID, "cloudflare-account-id", "", "Cloudflare account ID for Kura global DNS steering")
	flag.StringVar(&cloudflareZoneID, "cloudflare-zone-id", "", "Cloudflare zone ID for Kura global DNS steering")
	flag.StringVar(&cloudflareAPIToken, "cloudflare-api-token", "", "Cloudflare API token for Kura global DNS steering")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

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

	if err := (&controllers.KuraInstanceReconciler{
		Client:            mgr.GetClient(),
		Scheme:            mgr.GetScheme(),
		GRPCClusterIssuer: grpcClusterIssuer,
		CloudflareLoadBalancing: controllers.CloudflareLoadBalancingConfig{
			AccountID: cloudflareAccountID,
			ZoneID:    cloudflareZoneID,
			APIToken:  cloudflareAPIToken,
		},
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup KuraInstanceReconciler")
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
