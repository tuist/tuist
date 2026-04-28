// Command manager is the controller-manager binary for the Scaleway
// Apple Silicon CAPI infrastructure provider. Watches
// ScalewayAppleSiliconMachine + ScalewayAppleSiliconCluster CRs and
// reconciles them against Scaleway's Apple Silicon API + the host's
// kubelet/tart-cri runtime.
//
// Configured entirely via env / flags: the operator pod's Deployment
// spec mounts a Secret with Scaleway credentials and an embedded
// tart-cri / tart-cni binary set the bootstrap step ships to each
// fresh Mac mini.
package main

import (
	"flag"
	"os"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/controllers"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/bootstrap"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(clusterv1.AddToScheme(scheme))
	utilruntime.Must(infrav1.AddToScheme(scheme))
}

func main() {
	var (
		metricsAddr          string
		probeAddr            string
		enableLeaderElection bool
	)
	var (
		secretsNamespace      string
		defaultKubeletVersion string
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election; required when running >1 replica")
	flag.StringVar(&secretsNamespace, "secrets-namespace", "default",
		"Namespace where the operator stores per-fleet SSH key Secrets")
	flag.StringVar(&defaultKubeletVersion, "default-kubelet-version", "1.32.1",
		"Kubelet version to install when a Machine doesn't specify one")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	// Wire the bootstrap package's binary reader to read the embedded
	// tart-cri/tart-cni binaries the operator image carries.
	bootstrap.SetBinaryReader(func(path string) string {
		data, err := os.ReadFile(path)
		if err != nil {
			setupLog.Error(err, "read embedded binary", "path", path)
			return ""
		}
		return string(data)
	})

	scwClient, err := scaleway.NewClient()
	if err != nil {
		setupLog.Error(err, "scaleway client init")
		os.Exit(1)
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                  scheme,
		Metrics:                 metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress:  probeAddr,
		LeaderElection:          enableLeaderElection,
		LeaderElectionID:        "scaleway-applesilicon.infrastructure.cluster.x-k8s.io",
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	if err := (&controllers.ScalewayAppleSiliconClusterReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup ClusterReconciler")
		os.Exit(1)
	}

	credsManager := &credentials.Manager{
		Client:    mgr.GetClient(),
		Scaleway:  scwClient,
		Namespace: secretsNamespace,
	}

	if err := (&controllers.ScalewayAppleSiliconMachineReconciler{
		Client:                mgr.GetClient(),
		Scheme:                mgr.GetScheme(),
		ScalewayClient:        scwClient,
		CredentialsManager:    credsManager,
		DefaultKubeletVersion: defaultKubeletVersion,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup MachineReconciler")
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
