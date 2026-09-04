// Command manager is the controller-manager binary for
// cloudflare-operator. It runs in the management cluster and reconciles
// CRDs under cloudflare.tuist.dev against the Cloudflare API so that
// git is the source of truth for zone configuration (rate limiting
// rules today; cache rules, WAF custom rules, AI Crawl Control, and
// zone settings as follow-on CRDs).
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

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/controllers"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(cfv1alpha1.AddToScheme(scheme))
}

func main() {
	var (
		metricsAddr          string
		probeAddr            string
		enableLeaderElection bool

		tokenPath      string
		apiBaseURL     string
		resyncInterval time.Duration
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election; required when running >1 replica")
	flag.StringVar(&tokenPath, "cloudflare-token-path", "/etc/cloudflare/token",
		"Path to the file holding the Cloudflare API token")
	flag.StringVar(&apiBaseURL, "cloudflare-api-base-url", "",
		"Override the Cloudflare API base URL. Empty means production (https://api.cloudflare.com/client/v4)")
	flag.DurationVar(&resyncInterval, "resync-interval", 5*time.Minute,
		"Periodic reconcile interval; also how quickly dashboard drift is corrected")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	if resyncInterval <= 0 {
		setupLog.Error(nil, "--resync-interval must be positive")
		os.Exit(1)
	}

	tokenBytes, err := os.ReadFile(tokenPath)
	if err != nil {
		setupLog.Error(err, "read cloudflare token", "path", tokenPath)
		os.Exit(1)
	}
	token := strings.TrimSpace(string(tokenBytes))
	if token == "" {
		setupLog.Error(nil, "cloudflare token file is empty", "path", tokenPath)
		os.Exit(1)
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "cloudflare-operator.tuist.dev",
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	cf := cloudflare.New(token, apiBaseURL)

	if err := (&controllers.CloudflareRateLimitReconciler{
		Client:         mgr.GetClient(),
		Scheme:         mgr.GetScheme(),
		CF:             cf,
		ResyncInterval: resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup CloudflareRateLimitReconciler")
		os.Exit(1)
	}
	if err := (&controllers.CloudflareCacheRuleReconciler{
		Client:         mgr.GetClient(),
		Scheme:         mgr.GetScheme(),
		CF:             cf,
		ResyncInterval: resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup CloudflareCacheRuleReconciler")
		os.Exit(1)
	}
	if err := (&controllers.CloudflareWAFCustomRuleReconciler{
		Client:         mgr.GetClient(),
		Scheme:         mgr.GetScheme(),
		CF:             cf,
		ResyncInterval: resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup CloudflareWAFCustomRuleReconciler")
		os.Exit(1)
	}
	if err := (&controllers.CloudflareZoneSettingReconciler{
		Client:         mgr.GetClient(),
		Scheme:         mgr.GetScheme(),
		CF:             cf,
		ResyncInterval: resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup CloudflareZoneSettingReconciler")
		os.Exit(1)
	}
	if err := (&controllers.CloudflareAICrawlControlReconciler{
		Client:         mgr.GetClient(),
		Scheme:         mgr.GetScheme(),
		CF:             cf,
		ResyncInterval: resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup CloudflareAICrawlControlReconciler")
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

	setupLog.Info("starting manager", "resyncInterval", resyncInterval)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}
