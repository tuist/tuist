// Command rack-switch-controller reconciles RackSwitch objects against the
// Omada SDN controller's Open API: it adopts each switch whose managedBy is
// controller into the site and writes its configuration, one switch at a time
// in the site's apply order.
//
// `rack-switch-controller apply` runs the same steps once for one object
// from a file, without a cluster. See apply.go.
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
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/controllers"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/telemetry"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(v1alpha1.AddToScheme(scheme))
}

// engineFlags are the flags the manager and apply share.
type engineFlags struct {
	omadaURL          string
	omadaCAFile       string
	site              string
	controllerAddress string
	credentialsDir    string
	gates             converge.Gates
}

func (f *engineFlags) register(fs *flag.FlagSet, siteFlag string) {
	fs.StringVar(&f.omadaURL, "omada-url", "https://omada-omada-controller.omada.svc:8043",
		"Base URL of the Omada controller")
	fs.StringVar(&f.omadaCAFile, "omada-ca-file", "",
		"PEM file with the CA the Omada controller's certificate is issued from; empty trusts the system's roots")
	fs.StringVar(&f.site, siteFlag, "", "Omada site the switches are adopted into")
	fs.StringVar(&f.controllerAddress, "controller-address", "",
		"Address the controller tells adopted switches to connect back to: its tailnet IP")
	fs.StringVar(&f.credentialsDir, "credentials-dir", "/etc/rack-switch-controller",
		"Directory holding client-id, client-secret, device-username, device-password, and optionally factory-username and factory-password")
	fs.BoolVar(&f.gates.VLANs, "enable-vlans", true, "Create site networks and write port VLAN membership")
	fs.BoolVar(&f.gates.LAGs, "enable-lags", true, "Create link aggregation groups")
	fs.BoolVar(&f.gates.PortSpanningTree, "enable-port-spanning-tree", true, "Write per-port spanning tree")
	fs.BoolVar(&f.gates.ManagementAddressing, "enable-management-addressing", true,
		"Write the management interface's static address, mask and gateway")
	fs.BoolVar(&f.gates.SiteServices, "enable-site-services", true,
		"Write the site's LLDP and SNMP settings")
}

func (f *engineFlags) engine(siteFlag string) (*converge.Engine, func() (converge.Credentials, error), error) {
	switch {
	case f.site == "":
		return nil, nil, fmt.Errorf("--%s is required", siteFlag)
	case f.controllerAddress == "":
		return nil, nil, fmt.Errorf("--controller-address is required")
	}
	dir := f.credentialsDir
	credentials := func() (converge.Credentials, error) { return converge.LoadCredentials(dir) }
	if _, err := credentials(); err != nil {
		return nil, nil, err
	}
	rootCAs, err := omada.LoadRootCAs(f.omadaCAFile)
	if err != nil {
		return nil, nil, err
	}
	client := omada.New(f.omadaURL, func() (string, string, error) {
		creds, err := credentials()
		return creds.ClientID, creds.ClientSecret, err
	}, rootCAs)
	return &converge.Engine{
		Omada:             client,
		Site:              f.site,
		ControllerAddress: f.controllerAddress,
		Gates:             f.gates,
	}, credentials, nil
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "apply" {
		os.Exit(runApply(os.Args[2:], os.Stdout, os.Stderr))
	}

	var (
		metricsAddr          string
		probeAddr            string
		enableLeaderElection bool
		namespace            string
		resyncInterval       time.Duration
		ef                   engineFlags
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election, so exactly one replica writes to the switches")
	flag.StringVar(&namespace, "namespace", "", "Namespace whose RackSwitches the controller reconciles")
	flag.DurationVar(&resyncInterval, "resync-interval", 10*time.Minute,
		"How often each switch is read again, which is how drift is noticed")
	ef.register(flag.CommandLine, "omada-site")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	if namespace == "" {
		setupLog.Error(nil, "--namespace is required")
		os.Exit(1)
	}
	if resyncInterval <= 0 {
		setupLog.Error(nil, "--resync-interval must be positive")
		os.Exit(1)
	}
	engine, credentials, err := ef.engine("omada-site")
	if err != nil {
		setupLog.Error(err, "configure")
		os.Exit(1)
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "rack-switch-controller.tuist.dev",
		Cache: cache.Options{
			DefaultNamespaces: map[string]cache.Config{namespace: {}},
		},
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	if err := (&controllers.RackSwitchReconciler{
		Client:         mgr.GetClient(),
		Recorder:       mgr.GetEventRecorderFor("rack-switch-controller"),
		Engine:         engine,
		Credentials:    credentials,
		ResyncInterval: resyncInterval,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup RackSwitch reconciler")
		os.Exit(1)
	}

	poller := telemetry.New(engine.Omada, ef.site, mgr.GetClient(), namespace, ctrl.Log.WithName("telemetry"))
	metrics.Registry.MustRegister(poller)
	if err := mgr.Add(poller); err != nil {
		setupLog.Error(err, "setup switch telemetry")
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

	setupLog.Info("starting manager", "namespace", namespace, "site", ef.site, "gates", ef.gates)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}
