// Command tart-kubelet runs on a Mac mini, joins it to the cluster as
// a real Node, and translates Pods scheduled to that Node into Tart
// VMs. It is "kubelet, but for Tart" — same shape, none of cAdvisor's
// hard Linux-isms, no CSI.
//
// One process per Mac mini, started by launchd as root. Reads its
// kubeconfig from disk (provisioned by the CAPI provider during host
// bootstrap), watches the API server for Pods scheduled to its
// hostname-derived Node, and drives `tart` locally to execute them.
package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	cache "sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/envresolver"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/nodeagent"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/podagent"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/satoken"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	_ = clientgoscheme.AddToScheme(scheme)
}

func main() {
	var (
		nodeName           string
		nodeIP             string
		nodeIPSource       string
		scrapeAllowedCIDRs cidrList
		nodeLabelsRaw      string
		hostCPU            int
		hostMemoryMB       int
		maxPods            int
		metricsAddr        string
		probeAddr          string
		tartBinary         string
	)
	flag.StringVar(&nodeName, "node-name", envOr("TART_KUBELET_NODE_NAME", ""), "Node name to register as. Defaults to os.Hostname() when empty.")
	flag.StringVar(&nodeIP, "node-ip", envOr("TART_KUBELET_NODE_IP", ""),
		"Routable IP of this Mac mini. Pods that opt into Prometheus scraping advertise it as their PodIP and run a host-side forwarder on the host port. Defaults to the first non-loopback IPv4 address on a UP interface.")
	flag.StringVar(&nodeIPSource, "node-ip-source", envOr("TART_KUBELET_NODE_IP_SOURCE", "auto"),
		"Where to learn this Mac mini's routable IP from. "+
			"`auto` (default) walks UP interfaces. `tailscale` shells out to `tailscale ip -4` "+
			"and is fatal on failure — used when the cluster's scraper path is the tailnet and "+
			"falling back to a public interface would expose the host-side metrics forwarder on "+
			"the open internet. `--node-ip` overrides this in either mode.")
	flag.Var(&scrapeAllowedCIDRs, "scrape-allowed-cidr",
		"CIDR (IPv4 or IPv6) allowed to reach the per-Pod metrics forwarder. May be repeated. Defaults to RFC1918 / IPv6 ULA / loopback / link-local — covers any realistic cluster Pod or Node CIDR while clamping out the public WAN. The Mac mini's bind address can in practice be a public IP, so this allowlist (not the bind interface) is the load-bearing security boundary.")
	flag.StringVar(&nodeLabelsRaw, "node-labels", envOr("TART_KUBELET_NODE_LABELS", ""),
		"Comma-separated key=value pairs the Node carries as labels (e.g. "+
			"`tuist.dev/fleet=runners,tuist.dev/instance-type=large`). Workloads use "+
			"these via nodeSelector to pin to specific Mac minis. Mirrors kubelet's "+
			"--node-labels flag. Empty omits the labels; tart-kubelet prunes any "+
			"`tuist.dev/*` labels it previously set on the Node but no longer carries.")
	flag.IntVar(&hostCPU, "host-cpu", 8, "CPU cores to advertise on the Node.")
	flag.IntVar(&hostMemoryMB, "host-memory-mb", 16384, "Memory MB to advertise on the Node.")
	flag.IntVar(&maxPods, "max-pods", 2,
		"Max concurrent Pods (= concurrent Tart VMs) on this Node. Capped at 2 "+
			"by Apple's macOS SLA (no more than two simultaneous virtualized macOS "+
			"instances per host); Tart refuses to start a third VM.")
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080",
		"Prometheus metrics endpoint. When --node-ip-source=tailscale and "+
			"this is left at the default `:8080`, the bind address is "+
			"rewritten to `<tailnet-ip>:8080` so the controller-runtime "+
			"metrics never listen on a public interface. Any explicit "+
			"override (including an explicit `:8080`) opts out of that "+
			"rewrite — the operator is then responsible for not exposing "+
			"the endpoint on the WAN.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "Liveness/readiness probe endpoint.")
	flag.StringVar(&tartBinary, "tart-binary", "/usr/local/bin/tart", "Path to the local tart CLI.")

	// `--kubeconfig` is registered automatically by controller-runtime's
	// init() (sigs.k8s.io/controller-runtime/pkg/client/config). Defining
	// our own flag of the same name here would panic with `flag
	// redefined`; rely on theirs and let the launchd plist pass the path.
	opts := zap.Options{Development: false}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	if nodeName == "" {
		hostname, err := os.Hostname()
		if err != nil {
			setupLog.Error(err, "resolve hostname for default node name")
			os.Exit(1)
		}
		nodeName = hostname
	}

	if nodeIP == "" {
		switch nodeIPSource {
		case "tailscale":
			// Fatal on failure: the only reason an operator pins
			// source=tailscale is that the tailnet IP is the
			// load-bearing boundary for in-cluster scrapers. Silently
			// falling back to a public interface would expose the
			// metrics forwarder on the WAN and bypass the source-CIDR
			// allowlist (which is RFC1918 + CGNAT — public IPs
			// outside the RFC1918 set would still match a cluster
			// egress NAT if the operator override loosened it).
			ip, err := tailscaleNodeIP()
			if err != nil {
				setupLog.Error(err, "resolve tailnet node-ip via `tailscale ip -4`")
				os.Exit(1)
			}
			nodeIP = ip
		case "auto", "":
			ip, err := defaultNodeIP()
			if err != nil {
				// Non-fatal: scraping is opt-in per Pod, and the
				// reconciler's PodIP rewrite is gated on NodeIP being
				// set. Everything else (Pod ↔ VM management) keeps
				// working without a known host IP.
				setupLog.Info("no --node-ip and auto-detect failed; metrics scraping for VM Pods will be disabled", "err", err.Error())
			} else {
				nodeIP = ip
			}
		default:
			setupLog.Error(fmt.Errorf("unknown --node-ip-source %q (want one of: auto, tailscale)", nodeIPSource), "parse flag")
			os.Exit(1)
		}
	}

	// Bind the controller-runtime metrics endpoint (PromEx-shaped
	// /metrics on :8080 by default) to the same tailnet interface
	// when source=tailscale and the operator left --metrics-bind-
	// address at its default :8080. Without this, the endpoint
	// listens on 0.0.0.0:8080 and on a Scaleway Mac mini that's a
	// public address — the kubelet's reconcile-counters, error
	// rates, and the new `tart_kubelet_vm_boot_duration_seconds`
	// histogram would be exposed on the WAN. The tailnet bind
	// inverts that: only `tag:tuist-k8s-operator` can dial 8080,
	// gated by the Tailscale ACL.
	if nodeIPSource == "tailscale" && nodeIP != "" && metricsAddr == ":8080" {
		metricsAddr = fmt.Sprintf("%s:8080", nodeIP)
		setupLog.Info("binding metrics endpoint to tailnet IP", "addr", metricsAddr)
	}

	// controller-runtime's GetConfigOrDie resolves config via (in order):
	//   1. `--kubeconfig` flag value (set by launchd plist)
	//   2. KUBECONFIG env
	//   3. in-cluster service-account mount (won't apply on Mac mini)
	//   4. ~/.kube/config
	cfg := ctrl.GetConfigOrDie()

	// Narrow the cache: we only ever care about Pods scheduled to this
	// Node and the Node object itself. Cluster-wide watches on a node-
	// embedded agent are wasteful; this keeps memory + apiserver load
	// small per Mac mini.
	mgr, err := ctrl.NewManager(cfg, manager.Options{
		Scheme:                 scheme,
		Metrics:                metricsserver.Options{BindAddress: metricsAddr},
		HealthProbeBindAddress: probeAddr,
		Cache: cache.Options{
			ByObject: map[client.Object]cache.ByObject{
				&corev1.Pod{}: {
					Field: pickPodsForNode(nodeName),
				},
				&corev1.Node{}: {
					Field: pickThisNode(nodeName),
				},
			},
		},
	})
	if err != nil {
		setupLog.Error(err, "create manager")
		os.Exit(1)
	}

	tartClient := tart.New()
	tartClient.Binary = tartBinary

	resolver := &envresolver.Resolver{K8s: mgr.GetAPIReader()}

	store := podagent.NewStore()

	gcCollector := &podagent.Collector{
		K8s:      mgr.GetAPIReader(),
		Tart:     tartClient,
		NodeName: nodeName,
		Interval: 5 * time.Minute,
		Store:    store,
	}
	if err := mgr.Add(gcCollector); err != nil {
		setupLog.Error(err, "add gc collector")
		os.Exit(1)
	}

	// Hydrate the Pod ↔ VM map from on-host state before reconciles
	// fire. After a kubelet restart the in-memory store is empty but
	// any Tart VMs from before the restart are still running
	// (`nohup`-detached). Without this pass the next Reconcile would
	// see "no entry for this Pod", check `tart get`, find the existing
	// VM, and stop+delete it as stale — killing a healthy workload on
	// every kubelet update. We do this synchronously, before
	// mgr.Start, using a fresh non-cached client.
	if err := recoverState(cfg, scheme, tartClient, store, nodeName); err != nil {
		setupLog.Error(err, "state recovery failed; reconciles may treat existing VMs as stale")
	}

	// Typed kubernetes.Interface for TokenRequest — the
	// controller-runtime client doesn't expose CreateToken on
	// ServiceAccounts because TokenRequest is a subresource that
	// doesn't fit the generic resource shape.
	typedClient, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		setupLog.Error(err, "create typed kubernetes client")
		os.Exit(1)
	}

	if err := (&podagent.Reconciler{
		CachedClient:       mgr.GetClient(),
		NodeName:           nodeName,
		NodeIP:             nodeIP,
		ScrapeAllowedCIDRs: scrapeAllowedCIDRs.Value(),
		Tart:               tartClient,
		Resolver:           resolver,
		Store:              store,
		TokenMinter:        &satoken.ClientMinter{Client: typedClient, ExpirationSeconds: 3600},
		GC:                 gcCollector,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "setup pod reconciler")
		os.Exit(1)
	}

	nodeLabels, err := parseNodeLabels(nodeLabelsRaw)
	if err != nil {
		setupLog.Error(err, "parse --node-labels")
		os.Exit(1)
	}

	if err := mgr.Add(&nodeagent.Maintainer{
		Client:     mgr.GetClient(),
		NodeName:   nodeName,
		NodeIP:     nodeIP,
		NodeLabels: nodeLabels,
		CPU:        hostCPU,
		MemoryMB:   hostMemoryMB,
		MaxPods:    maxPods,
		Heartbeat:  30 * time.Second,
		DiskPressure: func(ctx context.Context) (bool, string, error) {
			return diskPressureFromGuests(ctx, tartClient, diskPressureThresholdPercent)
		},
	}); err != nil {
		setupLog.Error(err, "add node maintainer")
		os.Exit(1)
	}

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up healthz")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "set up readyz")
		os.Exit(1)
	}

	setupLog.Info("starting tart-kubelet", "node", nodeName)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "manager exited")
		os.Exit(1)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// parseNodeLabels parses kubelet's --node-labels=k=v,k=v form. Empty
// input yields a nil map (no labels stamped, prune-only mode). Used
// by the Maintainer to populate the Node's labels at registration.
func parseNodeLabels(raw string) (map[string]string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}
	out := map[string]string{}
	for _, pair := range strings.Split(raw, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		k, v, ok := strings.Cut(pair, "=")
		if !ok {
			return nil, fmt.Errorf("invalid label pair %q (expected key=value)", pair)
		}
		k = strings.TrimSpace(k)
		v = strings.TrimSpace(v)
		if k == "" {
			return nil, fmt.Errorf("invalid label pair %q (empty key)", pair)
		}
		out[k] = v
	}
	return out, nil
}

// defaultNodeIP picks the first non-loopback IPv4 address bound to a
// UP, non-loopback, non-VM-bridge interface. Mirrors what real
// kubelet does when --node-ip isn't set, with one extra exclusion:
// Tart spins up `bridge*` interfaces for the VM NAT network
// (192.168.64.0/24 by default) on first `tart run`, and after a
// kubelet restart with a running VM those would be the first
// candidate the naive walker picked — handing back the host-side
// gateway of the VM network instead of the routable host IP.
// Returns an error if no candidate is found — the caller treats
// that as "scraping disabled" rather than fatal.
func defaultNodeIP() (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if isVMBridge(iface.Name) {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ip, _, err := net.ParseCIDR(a.String())
			if err != nil {
				continue
			}
			if ip.IsLoopback() || ip.IsLinkLocalUnicast() {
				continue
			}
			ip4 := ip.To4()
			if ip4 == nil {
				continue
			}
			return ip4.String(), nil
		}
	}
	return "", &noNodeIPError{}
}

// isVMBridge matches the interface-name patterns macOS uses for
// virtualization NAT bridges — Tart's `bridge100+` and the more
// generic `vmnet*` (Hypervisor.framework's reserved prefix).
func isVMBridge(name string) bool {
	if len(name) >= 6 && name[:6] == "bridge" {
		return true
	}
	if len(name) >= 5 && name[:5] == "vmnet" {
		return true
	}
	return false
}

type noNodeIPError struct{}

func (*noNodeIPError) Error() string {
	return "no non-loopback IPv4 address found on any UP interface"
}

// tailscaleNodeIP shells out to `tailscale ip -4` and returns the
// first IPv4 address the daemon advertises. macOS's CLI lives at
// /usr/local/bin/tailscale after macos-host-bootstrap.installTailscale
// extracts the operator-baked binaries there and `tailscaled
// install-system-daemon` registers the launchd job.
// /usr/bin/env-style PATH lookup would work too (the launchd job
// already exports /usr/local/bin first), but pinning the absolute
// path keeps the failure mode explicit when the binary is missing.
//
// Why not parse the utun interface address ourselves: macOS picks an
// arbitrary utunN index for Tailscale (varies by boot order with
// other VPN clients), and the daemon's CGNAT address can be IPv4-
// only, IPv6-only, or both depending on tailnet config. Asking the
// daemon is the only stable source of truth.
func tailscaleNodeIP() (string, error) {
	const tailscaleCLI = "/usr/local/bin/tailscale"
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, tailscaleCLI, "ip", "-4").Output()
	if err != nil {
		return "", fmt.Errorf("exec %s ip -4: %w", tailscaleCLI, err)
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if ip := net.ParseIP(line); ip != nil && ip.To4() != nil {
			return ip.String(), nil
		}
	}
	return "", fmt.Errorf("tailscale ip -4 returned no IPv4 address")
}

// cidrList implements flag.Value for repeated --scrape-allowed-cidr.
// Each invocation appends one CIDR; no value at all means "fall
// back to DefaultScrapeAllowedCIDRs in the reconciler" rather than
// "deny everything", because an empty allowlist would silently lock
// out every scraper.
type cidrList []*net.IPNet

func (c *cidrList) String() string {
	if c == nil || len(*c) == 0 {
		return ""
	}
	parts := make([]string, 0, len(*c))
	for _, n := range *c {
		parts = append(parts, n.String())
	}
	return joinComma(parts)
}

func (c *cidrList) Set(value string) error {
	_, n, err := net.ParseCIDR(value)
	if err != nil {
		return fmt.Errorf("parse cidr %q: %w", value, err)
	}
	*c = append(*c, n)
	return nil
}

// Value returns the parsed CIDRs, or nil when none were passed.
func (c cidrList) Value() []*net.IPNet { return []*net.IPNet(c) }

func joinComma(s []string) string {
	out := ""
	for i, v := range s {
		if i > 0 {
			out += ","
		}
		out += v
	}
	return out
}

// pickPodsForNode narrows the Pod informer with a server-side field
// selector — the API server filters by spec.nodeName before sending us
// anything. Same trick the upstream kubelet uses.
func pickPodsForNode(nodeName string) fields.Selector {
	return fields.SelectorFromSet(fields.Set{"spec.nodeName": nodeName})
}

// pickThisNode narrows the Node informer to just our Node.
func pickThisNode(nodeName string) fields.Selector {
	return fields.SelectorFromSet(fields.Set{"metadata.name": nodeName})
}

// diskPressureThresholdPercent is the guest root-volume capacity at or
// above which the host Node reports DiskPressure. Below 100% so the
// condition fires (stopping new scheduling and triggering alerts) before
// the guest actually starts failing writes with ENOSPC.
const diskPressureThresholdPercent = 90

// diskPressureFromGuests reports DiskPressure=True when any running VM's
// guest root volume is at or above the threshold. Each probe is bounded
// so an unresponsive guest agent can't stall the node heartbeat, and a
// per-VM error is logged and skipped rather than failing the whole check
// — one bad guest shouldn't blind the others. A List error propagates so
// the maintainer keeps the previous condition instead of flapping.
func diskPressureFromGuests(ctx context.Context, tartClient *tart.Client, threshold int) (bool, string, error) {
	vms, err := tartClient.List(ctx)
	if err != nil {
		return false, "", err
	}

	var pressured []string
	for _, vm := range vms {
		if vm.Source != "local" {
			continue
		}
		running, err := tartClient.IsRunning(ctx, vm.Name)
		if err != nil || !running {
			continue
		}

		probeCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		pct, err := tartClient.GuestDiskUsagePercent(probeCtx, vm.Name)
		cancel()
		if err != nil {
			log.FromContext(ctx).Error(err, "guest disk usage probe", "vm", vm.Name)
			continue
		}
		if pct >= threshold {
			pressured = append(pressured, fmt.Sprintf("%s at %d%%", vm.Name, pct))
		}
	}

	if len(pressured) > 0 {
		return true, "guest root volume(s) near capacity: " + strings.Join(pressured, ", "), nil
	}
	return false, "", nil
}

// recoverState rebuilds the Pod ↔ VM map by intersecting the host's
// current Tart VMs with the Pods scheduled to this Node. Any Pod whose
// VM name is present in `tart list` is recorded in the Store so the
// reconciler treats the VM as live instead of attempting to
// re-provision it.
//
// Best-effort. A miss (no Tart VM matching a scheduled Pod) is left
// alone — the reconciler will recreate it. A spurious extra Tart VM
// (no matching Pod) is also left; the reconciler garbage-collects on
// Pod deletion in steady state, and an explicit `tart-kubelet gc`
// pass can be added later if drift becomes a real problem.
func recoverState(
	cfg *clientcmdConfig,
	scheme *runtime.Scheme,
	tartClient *tart.Client,
	store *podagent.Store,
	nodeName string,
) error {
	c, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	vms, err := tartClient.List(ctx)
	if err != nil {
		return err
	}
	// Probe each local VM with `tart ip` — that's the only reliable
	// liveness signal under Tart 2.32 (the on-disk State field stays
	// "stopped" for backgrounded VMs even when they're running).
	// Stopped clones (left over from a previous kubelet kill) get
	// skipped here; createPod will pick them up and start them.
	live := make(map[string]bool, len(vms))
	for _, vm := range vms {
		if vm.Source != "local" {
			continue
		}
		if ip, ipErr := tartClient.IP(ctx, vm.Name); ipErr == nil && ip != "" {
			live[vm.Name] = true
		}
	}

	pods := &corev1.PodList{}
	if err := c.List(ctx, pods, client.MatchingFields{"spec.nodeName": nodeName}); err != nil {
		return err
	}

	matched := 0
	for i := range pods.Items {
		pod := &pods.Items[i]
		vmName := podagent.VMNameForPod(pod)
		if !live[vmName] {
			continue
		}
		startTS := pod.Status.StartTime
		if startTS == nil {
			now := metav1.Now()
			startTS = &now
		}
		store.Put(pod.Namespace, pod.Name, &podagent.Entry{
			VMName: vmName,
			// Pod.Status.StartTime is when the API server first saw the
			// Pod, not when we started the clone — observing
			// `tart_kubelet_vm_boot_duration_seconds` against it would
			// fold kubelet downtime into the histogram and read as a
			// boot-time spike across every recovered VM. Suppress the
			// observation for recovered entries.
			StartTS:      *startTS,
			BootObserved: true,
		})
		matched++
	}
	setupLog.Info("recovered VM state", "node", nodeName, "tart_vms", len(vms), "matched_pods", matched)
	return nil
}

// clientcmdConfig is an alias so the signature of recoverState reads
// without dragging the rest-config dep into the main signature line.
type clientcmdConfig = rest.Config
