// Command manager is the controller-manager binary for
// hetzner-robot-controller. Runs on the mgmt cluster, polls
// Hetzner Robot's webservice for servers matching a name prefix,
// and keeps `HetznerBareMetalHost` CRs in sync — so the operator
// doesn't hand-author one per box. Also auto-fills disk WWNs
// into `rootDeviceHints` once caph populates `hardwareDetails`,
// closing the chicken-and-egg that otherwise leaves caph stuck
// at registering.
//
// caph itself remains the CAPI infrastructure provider for
// Hetzner — claims hosts, runs rescue/installimage, drives
// kubeadm-join. This controller is the Tuist-side glue around
// caph, not a from-scratch provider.
package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/tuist/tuist/infra/hetzner-robot-controller/controllers"
	"github.com/tuist/tuist/infra/hetzner-robot-controller/internal/robot"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	// HetznerBareMetalHost is operated on via unstructured.* —
	// no caph API package import needed.
}

func main() {
	var (
		metricsAddr          string
		probeAddr            string
		enableLeaderElection bool

		hostNamespace string
		namePrefix    string
		pollInterval  time.Duration

		robotUserPath string
		robotPassPath string
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080",
		"Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081",
		"Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election; required when running >1 replica")
	flag.StringVar(&hostNamespace, "host-namespace",
		envOrDefault("HRC_HOST_NAMESPACE", "org-tuist"),
		"Namespace where HetznerBareMetalHost CRs live")
	flag.StringVar(&namePrefix, "name-prefix",
		envOrDefault("HRC_NAME_PREFIX", "tuist-bm-"),
		"Robot servers whose name starts with this are managed by this controller. "+
			"Servers outside the prefix are ignored on both creation and deletion.")
	flag.DurationVar(&pollInterval, "poll-interval", 60*time.Second,
		"How often to poll Robot for inventory changes. Hardware procurement is "+
			"human-paced — short intervals just add load without speeding anything up.")
	flag.StringVar(&robotUserPath, "robot-user-path",
		envOrDefault("HRC_ROBOT_USER_PATH", "/etc/hetzner-robot-controller/robot-user"),
		"Path to the file containing the Robot webservice username. "+
			"The chart mounts this from the `hetzner-robot-credentials` Secret.")
	flag.StringVar(&robotPassPath, "robot-pass-path",
		envOrDefault("HRC_ROBOT_PASS_PATH", "/etc/hetzner-robot-controller/robot-pass"),
		"Path to the file containing the Robot webservice password.")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	user, err := os.ReadFile(robotUserPath)
	if err != nil {
		setupLog.Error(err, "read robot user", "path", robotUserPath)
		os.Exit(1)
	}
	pass, err := os.ReadFile(robotPassPath)
	if err != nil {
		setupLog.Error(err, "read robot pass", "path", robotPassPath)
		os.Exit(1)
	}
	robotClient := robot.New(trimNewline(string(user)), trimNewline(string(pass)))

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "hetzner-robot-controller.tuist.dev",
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	syncer := &controllers.InventorySyncer{
		Client:       mgr.GetClient(),
		Robot:        robotClient,
		Namespace:    hostNamespace,
		NamePrefix:   namePrefix,
		PollInterval: pollInterval,
	}
	if err := mgr.Add(syncer); err != nil {
		setupLog.Error(err, "add InventorySyncer")
		os.Exit(1)
	}

	if err := (&controllers.WWNFillReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup WWNFillReconciler")
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

	setupLog.Info("starting manager",
		"namespace", hostNamespace, "prefix", namePrefix, "interval", pollInterval)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// trimNewline strips a single trailing newline if present.
// `kubectl create secret --from-file` doesn't add one, but `op
// read` does — operators occasionally bootstrap the Secret by
// hand and that one byte mismatches Robot's basic-auth.
func trimNewline(s string) string {
	if n := len(s); n > 0 && s[n-1] == '\n' {
		return s[:n-1]
	}
	return s
}

// Sanity: ensure the fmt import is used (placeholder for future
// formatted error wrapping in main; currently main only uses
// setupLog.Error).
var _ = fmt.Sprintf
