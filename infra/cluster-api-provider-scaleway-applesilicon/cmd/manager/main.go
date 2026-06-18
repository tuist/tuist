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
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
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
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/controllers"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/githubapp"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/runner"
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
		tailscaleBinariesPath        string
		nodeExporterBinaryPath       string
		tailscaleAuthKeySecretName   string
		tailscaleTagsRaw             string
		tailscaleAcceptRoutes        bool
		vmKuraEgressCIDR             string
		vmClusterDNSIP               string
		vmCachePNID                  string
		vmCachePNCIDR                string
		tartKubeletHostCPU           int
		tartKubeletHostMemory        int
		tartKubeletMaxPods           int
		tartKubeletMaxUpdateAttempts int
		bootstrapRebootAfter         int
		bootstrapMaxAttempts         int

		machineMaxConcurrentReconciles int

		fleetSpreadDeployment string
		fleetSpreadNamespace  string

		egressNamespace      string
		egressProxyGroup     string
		egressMagicDNSSuffix string

		defaultAdoptPoolPrefix       string
		orphanReclaimClaimNamePrefix string
		orphanReclaimZonesRaw        string
		orphanReclaimInterval        time.Duration
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
	flag.StringVar(&tailscaleBinariesPath, "tailscale-binaries-path",
		envOrDefault("CAPI_TAILSCALE_BINARIES_PATH", ""),
		"Local path of the gzipped tarball containing the darwin/arm64 "+
			"tailscale + tailscaled binaries baked into this image "+
			"(/opt/tailscale/tailscale-darwin-arm64.tar.gz by default). The "+
			"bootstrap extracts to /usr/local/bin and calls `tailscaled "+
			"install-system-daemon` — the open-source variant per Tailscale's "+
			"own headless-server docs. Empty disables the Tailscale bootstrap "+
			"step; kubelet then falls back to the public interface as NodeIP.")
	flag.StringVar(&nodeExporterBinaryPath, "node-exporter-binary-path",
		envOrDefault("CAPI_NODE_EXPORTER_BINARY_PATH", ""),
		"Local path of the darwin/arm64 node_exporter binary baked into this "+
			"image (/opt/node-exporter/node_exporter-darwin-arm64 by default). "+
			"Empty disables the host-metrics step. Paired with "+
			"--tailscale-binaries-path: node_exporter without Tailscale would bind "+
			"to a public interface, which the bootstrap step actively refuses.")
	flag.StringVar(&tailscaleAuthKeySecretName, "tailscale-auth-key-secret-name",
		envOrDefault("CAPI_TAILSCALE_AUTH_KEY_SECRET_NAME", ""),
		"Name of the operator-namespace Secret (key `auth-key`) holding the "+
			"Tailscale pre-auth key the bootstrap uses for `tailscale up`. "+
			"Synced from 1Password via ESO — see the chart's "+
			"macos-fleet-tailscale-external-secrets.yaml. Empty disables the "+
			"Tailscale step even when --tailscale-binaries-path is set, so a chart "+
			"bring-up where ESO hasn't synced yet falls back cleanly.")
	flag.StringVar(&tailscaleTagsRaw, "tailscale-tags",
		envOrDefault("CAPI_TAILSCALE_TAGS", ""),
		"Comma-separated Tailscale ACL tags every Mac mini in this env's "+
			"fleet advertises at `tailscale up` time (e.g. "+
			"`tag:tuist-macmini-staging`). Must be allowed by the auth key's "+
			"tag binding and declared in the tailnet's tagOwners ACL block "+
			"(see infra/tailscale/acls.json). Per-env values flow through "+
			"macosFleet.tailscale.tags in the Helm values. Empty falls back "+
			"to whatever default tag the auth key carries.")
	flag.BoolVar(&tailscaleAcceptRoutes, "tailscale-accept-routes",
		envOrDefault("CAPI_TAILSCALE_ACCEPT_ROUTES", "") == "true",
		"Run `tailscale up --accept-routes` on every Mac mini, installing the "+
			"subnet routes the cluster-side Connector advertises (the cluster's "+
			"Service CIDR) so Tart runner VMs can reach the in-cluster Kura "+
			"runner-cache Service through the host's tailnet route. Enable only "+
			"in an env whose Connector is the single advertiser of that CIDR — "+
			"see infra/helm/tailscale-operator/values.yaml.")
	flag.StringVar(&vmKuraEgressCIDR, "vm-kura-egress-cidr",
		envOrDefault("CAPI_VM_KURA_EGRESS_CIDR", ""),
		"IPv4 CIDR (the cluster's Service CIDR, e.g. 10.128.0.0/12) the VM "+
			"egress firewall lets Tart VMs reach on the Kura cache ports "+
			"4000/50051. Empty keeps the firewall a pure RFC1918 blocklist. "+
			"Pairs with --tailscale-accept-routes; flows from the chart's "+
			"macosFleet.vmClusterEgress.kuraServiceCIDR.")
	flag.StringVar(&vmClusterDNSIP, "vm-cluster-dns-ip",
		envOrDefault("CAPI_VM_CLUSTER_DNS_IP", ""),
		"IPv4 ClusterIP of kube-dns (e.g. 10.128.0.10) the VM egress firewall "+
			"lets Tart VMs reach on port 53, so the runner VM's /etc/resolver "+
			"entry can resolve *.svc.cluster.local. Requires --vm-kura-egress-cidr; "+
			"flows from the chart's macosFleet.vmClusterEgress.clusterDNSIP.")
	flag.StringVar(&vmCachePNID, "vm-cache-pn-id",
		envOrDefault("CAPI_VM_CACHE_PN_ID", ""),
		"Scaleway Private Network ID carrying the kura runner-cache NodePort "+
			"endpoints. When set with --vm-cache-pn-cidr, the operator attaches "+
			"every Mac mini to this PN, resolves the per-host VLAN, and bootstrap "+
			"materializes the VLAN interface + VM egress pass + NAT. Flows from "+
			"the chart's macosFleet.vmCachePrivateNetwork.id.")
	flag.StringVar(&vmCachePNCIDR, "vm-cache-pn-cidr",
		envOrDefault("CAPI_VM_CACHE_PN_CIDR", ""),
		"IPv4 subnet of the runner-cache Private Network (e.g. 172.16.0.0/22). "+
			"The VM egress firewall lets Tart VMs reach it on the Kubernetes "+
			"NodePort range only. Flows from the chart's "+
			"macosFleet.vmCachePrivateNetwork.cidr.")
	flag.IntVar(&tartKubeletHostCPU, "tartkubelet-host-cpu", 8, "CPU cores tart-kubelet advertises on its Node")
	flag.IntVar(&tartKubeletHostMemory, "tartkubelet-host-memory-mb", 16384, "Memory MB tart-kubelet advertises on its Node")
	flag.IntVar(&tartKubeletMaxPods, "tartkubelet-max-pods", 2,
		"Max concurrent Pods on each Mac mini. Capped at 2 by Apple's macOS SLA "+
			"(no more than two simultaneous virtualized macOS instances per host); "+
			"Tart refuses to start a third VM.")
	flag.IntVar(&tartKubeletMaxUpdateAttempts, "tartkubelet-max-update-attempts", 5,
		"Drift-loop retries before transitioning the CR to a terminal Failed state. "+
			"Set to 0 to disable the cap (not recommended for production).")
	flag.IntVar(&bootstrapRebootAfter, "bootstrap-reboot-after", 3,
		"Consecutive BootstrapFailed count at which the controller asks Scaleway to "+
			"reboot the host once to clear volatile state (PAM lockouts, sshd throttling). "+
			"Fires once per host. Set to 0 to disable the reboot step.")
	flag.IntVar(&bootstrapMaxAttempts, "bootstrap-max-attempts", 8,
		"Consecutive BootstrapFailed count at which the controller returns the host to "+
			"the adopt pool (triggering ReinstallServer) and claims a different mini on the "+
			"next reconcile. Set to 0 to disable pool release (host is retried forever).")
	flag.IntVar(&machineMaxConcurrentReconciles, "machine-max-concurrent-reconciles", 4,
		"How many ScalewayAppleSiliconMachine reconciles run in parallel. The "+
			"default of 1 (controller-runtime's default) serializes the whole "+
			"fleet behind one worker — first-time bring-up of N Mac minis takes "+
			"N × bootstrap time because each AdoptFromPool + SSH bootstrap "+
			"blocks the worker for ~50 min. Bumping this lets distinct machines "+
			"provision in parallel; reconciles for the same machine remain "+
			"serialized by controller-runtime's per-key locking. 4 covers the "+
			"production fleet size with headroom; raise if fleets grow.")
	flag.StringVar(&fleetSpreadDeployment, "fleet-spread-deployment",
		envOrDefault("CAPI_FLEET_SPREAD_DEPLOYMENT", ""),
		"Deployment name to roll on fleet-shape change (typically "+
			"the xcresult-processor). When set, the operator stamps a hash of "+
			"the Ready Mac mini set onto the Deployment's pod template "+
			"annotation, forcing a new ReplicaSet whenever the fleet grows or "+
			"shrinks — the rolling update then redistributes Pods across hosts "+
			"via the Deployment's existing topologySpreadConstraints. The "+
			"scheduler doesn't rebalance running Pods on its own, so without "+
			"this we'd need a manual `kubectl rollout restart` every time a "+
			"Mac mini joins or leaves. Empty disables the controller (OSS "+
			"deployments without a workload to spread).")
	flag.StringVar(&fleetSpreadNamespace, "fleet-spread-namespace",
		envOrDefault("CAPI_FLEET_SPREAD_NAMESPACE", ""),
		"Namespace of the Deployment named by --fleet-spread-deployment. "+
			"Defaults to --secrets-namespace, which matches the chart's "+
			"single-namespace install layout.")

	flag.StringVar(&egressProxyGroup, "tailscale-egress-proxy-group",
		envOrDefault("CAPI_TAILSCALE_EGRESS_PROXY_GROUP", ""),
		"Name of the Tailscale ProxyGroup (type: egress) that fronts "+
			"per-machine ExternalName Services. When set, the reconciler "+
			"materialises one Service per Mac mini in --tailscale-egress-namespace, "+
			"annotated with tailscale.com/tailnet-fqdn + tailscale.com/proxy-group, "+
			"so cluster Pods (alloy-metrics) can dial the mini at its MagicDNS "+
			"FQDN. Empty disables the behavior — the OSS shape (no tailnet) is "+
			"untouched.")
	flag.StringVar(&egressNamespace, "tailscale-egress-namespace",
		envOrDefault("CAPI_TAILSCALE_EGRESS_NAMESPACE", "tailscale-operator"),
		"Namespace where per-machine egress Services live. Must match the "+
			"namespace the tailscale-operator wrapper chart installs the "+
			"ProxyGroup into. The operator needs `services` get/list/watch/"+
			"create/update/patch/delete here — granted via a namespaced Role "+
			"+ RoleBinding rendered by the main tuist chart.")
	flag.StringVar(&egressMagicDNSSuffix, "tailscale-egress-magicdns-suffix",
		envOrDefault("CAPI_TAILSCALE_EGRESS_MAGICDNS_SUFFIX", ""),
		"MagicDNS suffix of the tailnet the Mac minis register under "+
			"(e.g. `taild6d7bb.ts.net`). Per-machine egress Service's "+
			"tailnet-fqdn annotation is `<machine.Name>.<suffix>`. Read from "+
			"`tailscale status --json | .MagicDNSSuffix` on any tailnet "+
			"device. Required when --tailscale-egress-proxy-group is set.")

	flag.StringVar(&defaultAdoptPoolPrefix, "default-adopt-pool-prefix",
		envOrDefault("CAPI_DEFAULT_ADOPT_POOL_PREFIX", ""),
		"Pool prefix the controller falls back to when a CR's adoptPoolPrefix is "+
			"empty (legacy CRs), used both to release such CRs on delete and as the "+
			"orphan-reclaim sweep's pool prefix. Setting it enables the orphan-reclaim "+
			"sweep (report-only until --orphan-reclaim-claim-name-prefix is also set). "+
			"Empty disables both — bare legacy CRs skip release and no sweep runs.")
	flag.StringVar(&orphanReclaimClaimNamePrefix, "orphan-reclaim-claim-name-prefix",
		envOrDefault("CAPI_ORPHAN_RECLAIM_CLAIM_NAME_PREFIX", ""),
		"Claimed-name namespace this cluster owns within the Scaleway project (e.g. "+
			"`tuist-tuist-`). The orphan-reclaim sweep only returns a stranded host to "+
			"the pool when its Scaleway name carries this prefix, so a host an operator "+
			"is mid-provisioning under a Scaleway-default name, or a host owned by "+
			"another cluster sharing the project, is reported via the "+
			"scaleway_orphan_servers gauge but never mutated. Empty keeps the sweep "+
			"report-only. Must be unique to this cluster when the Scaleway project is "+
			"shared across environments.")
	flag.StringVar(&orphanReclaimZonesRaw, "orphan-reclaim-zones",
		envOrDefault("CAPI_ORPHAN_RECLAIM_ZONES", "fr-par-1"),
		"Comma-separated Scaleway zones the orphan-reclaim sweep scans every cycle, "+
			"unioned with the distinct zones of all live CRs. The static list keeps a "+
			"zone covered after its last CR is deleted — the case where a strand is "+
			"most likely and least visible.")
	flag.DurationVar(&orphanReclaimInterval, "orphan-reclaim-interval", 15*time.Minute,
		"How often the orphan-reclaim sweep runs. The sweep is a full Scaleway "+
			"ListServers per zone plus a CR list, so keep it coarse.")

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

	// Tailscale binaries tarball and node_exporter binary are both
	// optional: an empty path means the chart didn't wire the tailnet
	// into this release. We read on startup (not per reconcile)
	// because the operator image pins both versions; a bump goes
	// through an operator-image roll, not a hot reload.
	var tailscaleBinaries []byte
	if tailscaleBinariesPath != "" {
		tailscaleBinaries, err = os.ReadFile(tailscaleBinariesPath)
		if err != nil {
			setupLog.Error(err, "read tailscale binaries", "path", tailscaleBinariesPath)
			os.Exit(1)
		}
		setupLog.Info("loaded tailscale binaries", "path", tailscaleBinariesPath, "bytes", len(tailscaleBinaries), "sha", sha256Hex(tailscaleBinaries))
	}
	var nodeExporterBinary []byte
	if nodeExporterBinaryPath != "" {
		nodeExporterBinary, err = os.ReadFile(nodeExporterBinaryPath)
		if err != nil {
			setupLog.Error(err, "read node_exporter binary", "path", nodeExporterBinaryPath)
			os.Exit(1)
		}
		setupLog.Info("loaded node_exporter binary", "path", nodeExporterBinaryPath, "bytes", len(nodeExporterBinary), "sha", sha256Hex(nodeExporterBinary))
	}

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

	mgrOptions := ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "scaleway-applesilicon.infrastructure.cluster.x-k8s.io",
	}
	// When the egress reconciler is wired, scope the Services
	// informer to the egress namespace. The cache's default is a
	// cluster-wide LIST/WATCH on every Get'd GVK; without this
	// scoping the controller demands cluster-scoped `services` read
	// (and the namespaced Role + RoleBinding in the egress
	// namespace can't satisfy that). The reconciler only ever
	// touches Services there, so narrowing the cache matches both
	// the RBAC shape and the actual access pattern.
	if egressProxyGroup != "" && egressNamespace != "" {
		mgrOptions.Cache = cache.Options{
			ByObject: map[client.Object]cache.ByObject{
				&corev1.Service{}: {
					Namespaces: map[string]cache.Config{
						egressNamespace: {},
					},
				},
			},
		}
	}
	mgr, err := ctrl.NewManager(restConfig, mgrOptions)
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
		Client:                     mgr.GetClient(),
		Scaleway:                   scwClient,
		Namespace:                  secretsNamespace,
		NodeIdentityClusterRole:    nodeIdentityClusterRole,
		TailscaleAuthKeySecretName: tailscaleAuthKeySecretName,
	}

	kubeconfigBuilder := &kubeconfig.Builder{
		APIServerURL: apiServerURL,
	}

	// One Client per manager process, not per-Machine: the underlying
	// http.Client keeps its TLS session pool warm across reconciles
	// so a fleet bring-up doesn't re-handshake api.github.com on
	// every host.
	ghAppClient := &githubapp.Client{}
	runnerResolver := &runner.GitHubAppResolver{
		Client: mgr.GetClient(),
		Minter: ghAppClient,
	}

	if err := (&controllers.ScalewayAppleSiliconMachineReconciler{
		Client:               mgr.GetClient(),
		Scheme:               mgr.GetScheme(),
		ScalewayClient:       scwClient,
		CredentialsManager:   credsManager,
		Recorder:             mgr.GetEventRecorderFor("scalewayapplesiliconmachine-controller"),
		Kubeconfig:           kubeconfigBuilder,
		TartKubeletBinary:    tartKubeletBinary,
		TartKubeletBinarySHA: binarySHA,
		TartTarball:          tartTarball,
		TailscaleBinaries:    tailscaleBinaries,
		NodeExporterBinary:   nodeExporterBinary,
		// Per-env Tailscale tag, e.g. `tag:tuist-macmini-staging`.
		// Flows in from the Helm chart's macosFleet.tailscale.tags
		// via --tailscale-tags. ACL grants the matching env's
		// `tag:tuist-k8s-<env>` dial access to this tag on the
		// scrape ports; cross-env scraping is blocked once the
		// wide-open catch-all is removed.
		TailscaleTags:                parseCommaList(tailscaleTagsRaw),
		TailscaleAcceptRoutes:        tailscaleAcceptRoutes,
		VMKuraEgressCIDR:             vmKuraEgressCIDR,
		VMClusterDNSIP:               vmClusterDNSIP,
		VMCachePNID:                  vmCachePNID,
		VMCachePNCIDR:                vmCachePNCIDR,
		TartKubeletHostCPU:           tartKubeletHostCPU,
		TartKubeletHostMemoryMB:      tartKubeletHostMemory,
		TartKubeletMaxPods:           tartKubeletMaxPods,
		TartKubeletMaxUpdateAttempts: int32(tartKubeletMaxUpdateAttempts),
		BootstrapRebootAfter:         int32(bootstrapRebootAfter),
		BootstrapMaxAttempts:         int32(bootstrapMaxAttempts),
		MaxConcurrentReconciles:      machineMaxConcurrentReconciles,
		DefaultAdoptPoolPrefix:       defaultAdoptPoolPrefix,
		EgressNamespace:              egressNamespace,
		EgressProxyGroup:             egressProxyGroup,
		EgressMagicDNSSuffix:         egressMagicDNSSuffix,
		RunnerResolver:               runnerResolver,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup MachineReconciler")
		os.Exit(1)
	}

	// Elastic Metal (bare-metal) machines: the kura runner-cache pool. Same
	// provider, separate reconciler from Apple Silicon: bare-metal servers
	// ordered through the Baremetal API that pass through an OS-install wait,
	// attach the PN as a tagged VLAN, then SSH-bootstrap a rendered self-join.
	baremetalClient, err := scaleway.NewBaremetalClientFromEnv()
	if err != nil {
		setupLog.Error(err, "scaleway baremetal client")
		os.Exit(1)
	}
	if err := (&controllers.ScalewayElasticMetalMachineReconciler{
		Client:             mgr.GetClient(),
		APIReader:          mgr.GetAPIReader(),
		Scheme:             mgr.GetScheme(),
		ScalewayClient:     baremetalClient,
		Recorder:           mgr.GetEventRecorderFor("scalewayelasticmetalmachine-controller"),
		CredentialsManager: credsManager,
		Kubeconfig:         kubeconfigBuilder,
		KubernetesMinor:    "v1.34",
		DefaultOfferType:   "EM-B220E-NVME",
		DefaultOS:          "ubuntu_noble",
		DefaultZone:        "fr-par-1",
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup ScalewayElasticMetalMachineReconciler")
		os.Exit(1)
	}

	if fleetSpreadDeployment != "" {
		ns := fleetSpreadNamespace
		if ns == "" {
			ns = secretsNamespace
		}
		if err := (&controllers.FleetSpreadReconciler{
			Client:         mgr.GetClient(),
			APIReader:      mgr.GetAPIReader(),
			DeploymentName: fleetSpreadDeployment,
			Namespace:      ns,
		}).SetupWithManager(mgr); err != nil {
			setupLog.Error(err, "setup FleetSpreadReconciler")
			os.Exit(1)
		}
		setupLog.Info("fleet-spread controller enabled",
			"deployment", fleetSpreadDeployment, "namespace", ns)
	}

	// Orphan-reclaim sweep: enabled once a pool prefix is configured
	// (the same prefix the delete path falls back to). Report-only
	// until a claim-name prefix is also set; see the flag help.
	if defaultAdoptPoolPrefix != "" {
		reclaimZones := parseCommaList(orphanReclaimZonesRaw)
		if err := mgr.Add(&controllers.OrphanReclaimer{
			Client:          mgr.GetClient(),
			APIReader:       mgr.GetAPIReader(),
			Scaleway:        scwClient,
			Interval:        orphanReclaimInterval,
			Zones:           reclaimZones,
			PoolPrefix:      defaultAdoptPoolPrefix,
			ClaimNamePrefix: orphanReclaimClaimNamePrefix,
			Log:             ctrl.Log.WithName("orphan-reclaim"),
		}); err != nil {
			setupLog.Error(err, "setup OrphanReclaimer")
			os.Exit(1)
		}
		setupLog.Info("orphan-reclaim sweep enabled",
			"poolPrefix", defaultAdoptPoolPrefix,
			"claimNamePrefix", orphanReclaimClaimNamePrefix,
			"zones", reclaimZones, "interval", orphanReclaimInterval)
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

// parseCommaList splits a comma-separated flag value into a slice.
// Empty input returns nil. Whitespace around each entry is trimmed;
// blank entries (e.g. a trailing comma) are dropped.
func parseCommaList(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		out = append(out, p)
	}
	return out
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
