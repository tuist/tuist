// Command manager is the controller-manager binary for
// stable-egress-controller. It runs in a workload cluster and keeps the
// hosted server's stable-egress gateway highly available: exactly one
// host-prepared node from the egress candidate pool holds the Hetzner Floating
// IP and the active gateway label (which the CiliumEgressGatewayPolicy
// selects on). On loss of that node it elects another prepared, directly
// reachable candidate and moves the Floating IP + label together, replacing the manual
// `hcloud floating-ip assign` failover runbook.
package main

import (
	"flag"
	"net/netip"
	"os"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
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

		candidateLabel    string
		activeLabel       string
		preparedPodLabel  string
		preparedPodNS     string
		floatingIPName    string
		tokenPath         string
		egressIPAllowlist string
		resyncInterval    time.Duration
		nodeHealthPort    int
		nodeHealthTimeout time.Duration
		unhealthyGrace    time.Duration
		unpreparedGrace   time.Duration
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election; required when running >1 replica")
	flag.StringVar(&candidateLabel, "candidate-label", "tuist.dev/stable-egress-candidate=server",
		"key=value label identifying the egress candidate node pool (set by kubelet node-labels)")
	flag.StringVar(&activeLabel, "active-label", "tuist.dev/stable-egress-gateway=server",
		"key=value label this controller places on the single active gateway node; "+
			"the CiliumEgressGatewayPolicy selects on it")
	flag.StringVar(&preparedPodLabel, "prepared-pod-label",
		"tuist.dev/stable-egress-host-configurer=true",
		"key=value label identifying host-configurer Pods whose readiness proves a gateway is prepared")
	flag.StringVar(&preparedPodNS, "prepared-pod-namespace", "kube-system",
		"Namespace containing the host-configurer Pods")
	flag.StringVar(&floatingIPName, "floating-ip-name", "",
		"Name of the Hetzner Cloud Floating IP to keep on the active node (required)")
	flag.StringVar(&tokenPath, "hcloud-token-path", "/etc/hcloud/token",
		"Path to the file holding the Hetzner Cloud API token (mounted from kube-system/hcloud)")
	flag.StringVar(&egressIPAllowlist, "egress-ip-allowlist", "",
		"Comma-separated CIDRs of the documented egress set customers allowlist. When set, the "+
			"controller refuses (fails closed) to operate a Floating IP whose address is outside it")
	flag.DurationVar(&resyncInterval, "resync-interval", 30*time.Second,
		"Periodic reconcile interval; node events trigger reconciles in between")
	flag.IntVar(&nodeHealthPort, "node-health-port", 9962,
		"Host-network Cilium listener port used for direct gateway health checks")
	flag.DurationVar(&nodeHealthTimeout, "node-health-timeout", 2*time.Second,
		"Timeout for each direct gateway node health check")
	flag.DurationVar(&unhealthyGrace, "node-unhealthy-grace-period", 90*time.Second,
		"Continuous direct health check failure duration required before failover")
	flag.DurationVar(&unpreparedGrace, "node-unprepared-grace-period", 5*time.Minute,
		"Continuous host preparation failure duration required before failover")

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
	preparedKey, preparedVal, ok := splitLabel(preparedPodLabel)
	if !ok {
		setupLog.Error(nil, "invalid --prepared-pod-label, want key=value", "value", preparedPodLabel)
		os.Exit(1)
	}
	if strings.TrimSpace(preparedPodNS) == "" {
		setupLog.Error(nil, "--prepared-pod-namespace must not be empty")
		os.Exit(1)
	}
	if nodeHealthPort < 1 || nodeHealthPort > 65535 {
		setupLog.Error(nil, "--node-health-port must be between 1 and 65535")
		os.Exit(1)
	}
	if nodeHealthTimeout <= 0 {
		setupLog.Error(nil, "--node-health-timeout must be positive")
		os.Exit(1)
	}
	if unhealthyGrace <= 0 {
		setupLog.Error(nil, "--node-unhealthy-grace-period must be positive")
		os.Exit(1)
	}
	if unpreparedGrace <= 0 {
		setupLog.Error(nil, "--node-unprepared-grace-period must be positive")
		os.Exit(1)
	}
	if resyncInterval <= 0 {
		setupLog.Error(nil, "--resync-interval must be positive")
		os.Exit(1)
	}

	allowlist, err := parsePrefixes(egressIPAllowlist)
	if err != nil {
		setupLog.Error(err, "invalid --egress-ip-allowlist", "value", egressIPAllowlist)
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
		Cache: cache.Options{
			ByObject: map[client.Object]cache.ByObject{
				&corev1.Pod{}: {
					Namespaces: map[string]cache.Config{preparedPodNS: {}},
					Label:      labels.SelectorFromSet(labels.Set{preparedKey: preparedVal}),
				},
			},
		},
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	if err := (&controllers.FailoverReconciler{
		Client:                mgr.GetClient(),
		FIP:                   hcloud.New(strings.TrimSpace(string(token))),
		FloatingIPName:        floatingIPName,
		CandidateLabelKey:     candKey,
		CandidateLabelValue:   candVal,
		ActiveLabelKey:        actKey,
		ActiveLabelValue:      actVal,
		PreparedPodNamespace:  preparedPodNS,
		PreparedPodLabelKey:   preparedKey,
		PreparedPodLabelValue: preparedVal,
		EgressIPAllowlist:     allowlist,
		NodeHealthChecker: controllers.DirectNodeHealthChecker{
			Port:    nodeHealthPort,
			Timeout: nodeHealthTimeout,
		},
		UnhealthyGracePeriod:  unhealthyGrace,
		UnpreparedGracePeriod: unpreparedGrace,
		ResyncInterval:        resyncInterval,
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
		"candidateLabel", candidateLabel, "activeLabel", activeLabel,
		"preparedPodLabel", preparedPodLabel, "preparedPodNamespace", preparedPodNS)
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

func parsePrefixes(csv string) ([]netip.Prefix, error) {
	csv = strings.TrimSpace(csv)
	if csv == "" {
		return nil, nil
	}
	var out []netip.Prefix
	for _, part := range strings.Split(csv, ",") {
		p, err := netip.ParsePrefix(strings.TrimSpace(part))
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, nil
}
