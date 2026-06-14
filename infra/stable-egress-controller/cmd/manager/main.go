// Command manager is the controller-manager binary for
// stable-egress-controller. It runs in a workload cluster and keeps the
// hosted server's stable-egress gateway highly available: exactly one Ready
// node from the egress candidate pool holds the Hetzner Floating IP and the
// active gateway label (which the CiliumEgressGatewayPolicy + host-configurer
// select on). On loss of that node it re-elects another Ready candidate and
// moves the Floating IP + label together — replacing the manual
// `hcloud floating-ip assign` failover runbook.
package main

import (
	"flag"
	"os"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/tuist/tuist/infra/stable-egress-controller/controllers"
	"github.com/tuist/tuist/infra/stable-egress-controller/internal/hcloud"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
}

func main() {
	var (
		metricsAddr          string
		probeAddr            string
		enableLeaderElection bool

		candidateLabel string
		activeLabel    string
		floatingIPName string
		tokenPath      string
		resyncInterval time.Duration
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election; required when running >1 replica")
	flag.StringVar(&candidateLabel, "candidate-label", "tuist.dev/stable-egress-candidate=server",
		"key=value label identifying the egress candidate node pool (set by kubelet node-labels)")
	flag.StringVar(&activeLabel, "active-label", "tuist.dev/stable-egress-gateway=server",
		"key=value label this controller places on the single active gateway node; "+
			"the CiliumEgressGatewayPolicy and host-configurer select on it")
	flag.StringVar(&floatingIPName, "floating-ip-name", "",
		"Name of the Hetzner Cloud Floating IP to keep on the active node (required)")
	flag.StringVar(&tokenPath, "hcloud-token-path", "/etc/hcloud/token",
		"Path to the file holding the Hetzner Cloud API token (mounted from kube-system/hcloud)")
	flag.DurationVar(&resyncInterval, "resync-interval", 30*time.Second,
		"Periodic reconcile interval; node events trigger reconciles in between")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	if floatingIPName == "" {
		setupLog.Error(nil, "--floating-ip-name is required")
		os.Exit(1)
	}
	candKey, candVal, ok := splitLabel(candidateLabel)
	if !ok {
		setupLog.Error(nil, "invalid --candidate-label, want key=value", "value", candidateLabel)
		os.Exit(1)
	}
	actKey, actVal, ok := splitLabel(activeLabel)
	if !ok {
		setupLog.Error(nil, "invalid --active-label, want key=value", "value", activeLabel)
		os.Exit(1)
	}

	token, err := os.ReadFile(tokenPath)
	if err != nil {
		setupLog.Error(err, "read hcloud token", "path", tokenPath)
		os.Exit(1)
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "stable-egress-controller.tuist.dev",
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	if err := (&controllers.FailoverReconciler{
		Client:              mgr.GetClient(),
		FIP:                 hcloud.New(strings.TrimSpace(string(token))),
		FloatingIPName:      floatingIPName,
		CandidateLabelKey:   candKey,
		CandidateLabelValue: candVal,
		ActiveLabelKey:      actKey,
		ActiveLabelValue:    actVal,
		ResyncInterval:      resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup FailoverReconciler")
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

	setupLog.Info("starting manager", "floatingIP", floatingIPName,
		"candidateLabel", candidateLabel, "activeLabel", activeLabel)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}

func splitLabel(s string) (key, value string, ok bool) {
	k, v, found := strings.Cut(s, "=")
	if !found || k == "" || v == "" {
		return "", "", false
	}
	return k, v, true
}
