// Command manager is the controller-manager binary for the Scaleway
// Apple Silicon CAPI infrastructure provider. Watches
// ScalewayAppleSiliconMachine + ScalewayAppleSiliconCluster CRs and
// reconciles them against Scaleway's Apple Silicon API: order/release
// Mac minis, then SSH-bootstrap each into a real cluster Node.
//
// Bootstrap installs `tart-kubelet` on the Mac mini — a small
// kubelet-shaped agent that registers a Node with the cluster API and
// runs Pods scheduled to it as Tart VMs. The operator owns lifecycle
// (provision, bootstrap, release) and produces the kubeconfig the
// agent uses to authenticate.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"os"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/controllers"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/kubeconfig"
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
		secretsNamespace     string

		apiServerURL                 string
		nodeIdentityClusterRole      string
		tartKubeletBinaryPath        string
		tartTarballPath              string
		tartKubeletHostCPU           int
		tartKubeletHostMemory        int
		tartKubeletMaxPods           int
		tartKubeletMaxUpdateAttempts int
	)
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "Prometheus metrics endpoint")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint")
	flag.BoolVar(&enableLeaderElection, "leader-elect", true,
		"Single-leader election; required when running >1 replica")
	flag.StringVar(&secretsNamespace, "secrets-namespace", "default",
		"Namespace where the operator stores per-fleet SSH key Secrets")

	flag.StringVar(&apiServerURL, "api-server-url", os.Getenv("CAPI_TARTKUBELET_API_SERVER_URL"),
		"External API server URL Mac minis dial when joining (https://...). "+
			"When unset, auto-discovered from the kube-public/cluster-info ConfigMap that "+
			"kubeadm/CAPI populate during cluster bootstrap. Override only if the ConfigMap "+
			"isn't usable (non-kubeadm cluster, split-horizon DNS, etc.).")
	flag.StringVar(&nodeIdentityClusterRole, "node-identity-cluster-role",
		envOrDefault("CAPI_NODE_IDENTITY_CLUSTER_ROLE", "tart-kubelet"),
		"Name of the chart-managed ClusterRole each per-machine ServiceAccount binds to. "+
			"Chart's deployment template injects the rendered name.")
	flag.StringVar(&tartKubeletBinaryPath, "tartkubelet-binary-path",
		envOrDefault("CAPI_TARTKUBELET_BINARY_PATH", "/opt/tart-kubelet/tart-kubelet-darwin-arm64"),
		"Local path of the darwin/arm64 tart-kubelet binary baked into this image.")
	flag.StringVar(&tartTarballPath, "tart-tarball-path",
		envOrDefault("CAPI_TART_TARBALL_PATH", "/opt/tart/tart.tar.gz"),
		"Local path of the upstream tart.app tarball baked into this image. "+
			"Pinned by Dockerfile ARG; bumping it is a deliberate operator-image change.")
	flag.IntVar(&tartKubeletHostCPU, "tartkubelet-host-cpu", 8, "CPU cores tart-kubelet advertises on its Node")
	flag.IntVar(&tartKubeletHostMemory, "tartkubelet-host-memory-mb", 16384, "Memory MB tart-kubelet advertises on its Node")
	flag.IntVar(&tartKubeletMaxPods, "tartkubelet-max-pods", 2,
		"Max concurrent Pods on each Mac mini. Capped at 2 by Apple's macOS SLA "+
			"(no more than two simultaneous virtualized macOS instances per host); "+
			"Tart refuses to start a third VM.")
	flag.IntVar(&tartKubeletMaxUpdateAttempts, "tartkubelet-max-update-attempts", 5,
		"Drift-loop retries before transitioning the CR to a terminal Failed state. "+
			"Set to 0 to disable the cap (not recommended for production).")

	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	scwClient, err := scaleway.NewClient()
	if err != nil {
		setupLog.Error(err, "scaleway client init")
		os.Exit(1)
	}

	tartKubeletBinary, err := os.ReadFile(tartKubeletBinaryPath)
	if err != nil {
		setupLog.Error(err, "read tart-kubelet binary", "path", tartKubeletBinaryPath)
		os.Exit(1)
	}
	binarySHA := sha256Hex(tartKubeletBinary)
	setupLog.Info("loaded tart-kubelet binary", "path", tartKubeletBinaryPath, "bytes", len(tartKubeletBinary), "sha", binarySHA)

	tartTarball, err := os.ReadFile(tartTarballPath)
	if err != nil {
		setupLog.Error(err, "read tart tarball", "path", tartTarballPath)
		os.Exit(1)
	}
	tartTarballSHA := sha256Hex(tartTarball)
	setupLog.Info("loaded tart tarball", "path", tartTarballPath, "bytes", len(tartTarball), "sha", tartTarballSHA)

	restConfig := ctrl.GetConfigOrDie()

	if apiServerURL == "" {
		discovered, err := discoverAPIServerURL(restConfig)
		if err != nil {
			setupLog.Error(err, "discover api server url from kube-public/cluster-info; "+
				"set --api-server-url (or CAPI_TARTKUBELET_API_SERVER_URL) to skip discovery")
			os.Exit(1)
		}
		apiServerURL = discovered
		setupLog.Info("auto-discovered api server url", "source", "kube-public/cluster-info", "url", apiServerURL)
	}

	mgr, err := ctrl.NewManager(restConfig, ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "scaleway-applesilicon.infrastructure.cluster.x-k8s.io",
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
		Client:                  mgr.GetClient(),
		Scaleway:                scwClient,
		Namespace:               secretsNamespace,
		NodeIdentityClusterRole: nodeIdentityClusterRole,
	}

	kubeconfigBuilder := &kubeconfig.Builder{
		APIServerURL: apiServerURL,
	}

	if err := (&controllers.ScalewayAppleSiliconMachineReconciler{
		Client:                       mgr.GetClient(),
		Scheme:                       mgr.GetScheme(),
		ScalewayClient:               scwClient,
		CredentialsManager:           credsManager,
		Recorder:                     mgr.GetEventRecorderFor("scalewayapplesiliconmachine-controller"),
		Kubeconfig:                   kubeconfigBuilder,
		TartKubeletBinary:            tartKubeletBinary,
		TartKubeletBinarySHA:         binarySHA,
		TartTarball:                  tartTarball,
		TartKubeletHostCPU:           tartKubeletHostCPU,
		TartKubeletHostMemoryMB:      tartKubeletHostMemory,
		TartKubeletMaxPods:           tartKubeletMaxPods,
		TartKubeletMaxUpdateAttempts: int32(tartKubeletMaxUpdateAttempts),
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

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func sha256Hex(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// discoverAPIServerURL reads the cluster's externally-reachable
// kube-apiserver URL from the kube-public/cluster-info ConfigMap.
//
// kubeadm (and CAPI's KubeadmControlPlane on top of it) write that
// ConfigMap during cluster bootstrap with whatever
// `controlPlaneEndpoint` was configured (IP or DNS) plus the cluster
// CA. It's intentionally world-readable so `kubeadm join` can fetch
// it before establishing TLS — the operator's ServiceAccount can read
// it without extra RBAC.
//
// Reading from cluster-info instead of taking a chart-injected URL
// removes a hardcoded value from the chart values: the chart no
// longer needs to know the cluster's LB IP, and the value tracks
// whatever caph reconciles the LB to in the future.
func discoverAPIServerURL(restConfig *rest.Config) (string, error) {
	clientset, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return "", fmt.Errorf("clientset for cluster-info read: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cm, err := clientset.CoreV1().ConfigMaps(metav1.NamespacePublic).
		Get(ctx, "cluster-info", metav1.GetOptions{})
	if err != nil {
		if apierrors.IsNotFound(err) {
			return "", fmt.Errorf("kube-public/cluster-info ConfigMap not found (cluster not bootstrapped via kubeadm/CAPI?)")
		}
		return "", fmt.Errorf("get kube-public/cluster-info: %w", err)
	}
	raw, ok := cm.Data["kubeconfig"]
	if !ok {
		return "", fmt.Errorf("kube-public/cluster-info has no `kubeconfig` key")
	}
	cfg, err := clientcmd.Load([]byte(raw))
	if err != nil {
		return "", fmt.Errorf("parse cluster-info kubeconfig: %w", err)
	}
	for _, cluster := range cfg.Clusters {
		if cluster != nil && cluster.Server != "" {
			return cluster.Server, nil
		}
	}
	return "", fmt.Errorf("cluster-info kubeconfig has no cluster.server entry")
}
