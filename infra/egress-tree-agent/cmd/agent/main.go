// egress-tree-agent keeps a per-node shared HTB tree that enforces the kura
// per-tenant egress floors (egress_guaranteed_mbps), ceilings
// (egress_burst_mbps), and the node's box cap (tuist.dev/egress-mbps).
// See infra/egress-tree-agent/AGENTS.md for the architecture and the lab
// evidence behind it.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/tuist/tuist/infra/egress-tree-agent/internal/agent"
)

const (
	// debounceWindow batches the event burst behind a trigger before
	// reconciling, so one converge covers a whole pod churn (and a pod's
	// Running event has a moment for its Cilium endpoint to appear).
	debounceWindow = time.Second
	// endpointRetryDelay is the requeue delay for the one gap events cannot
	// see: a Running pod whose Cilium endpoint (lxc* device) does not exist
	// yet. Endpoint creation emits no pod event.
	endpointRetryDelay = 2 * time.Second
	// cycleTimeout bounds one reconcile (API cache reads, tc/ip shell-outs,
	// BPF attach) independently of the backstop interval.
	cycleTimeout = time.Minute
)

func main() {
	level, levelErr := levelEnv("LOG_LEVEL", slog.LevelInfo)
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
	if levelErr != nil {
		logger.Error("invalid log level", "env", "LOG_LEVEL", "value", os.Getenv("LOG_LEVEL"), "error", levelErr)
		os.Exit(1)
	}

	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		logger.Error("NODE_NAME is required (downward API)")
		os.Exit(1)
	}
	interval := durationEnv(logger, "RECONCILE_INTERVAL", 2*time.Minute)
	metricsAddr := envOr("METRICS_ADDR", ":9469")
	trampolineDev := envOr("TRAMPOLINE_DEV", "kura-egress0")
	returnDev := envOr("RETURN_DEV", "kura-egress1")
	ciliumSock := envOr("CILIUM_SOCK", "/var/run/cilium/cilium.sock")
	pinRoot := envOr("BPF_PIN_ROOT", "/sys/fs/bpf/kura-egress-tree")
	defaultNodeMbps := int64Env(logger, "DEFAULT_NODE_EGRESS_MBPS", 0)

	client, err := kubernetesClient()
	if err != nil {
		logger.Error("building kubernetes client", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// trigger is the edge-triggered reconcile signal: informer events and
	// requeues coalesce into at most one pending cycle.
	trigger := make(chan struct{}, 1)
	kick := func() {
		select {
		case trigger <- struct{}{}:
		default:
		}
	}

	// Both informers are field-selected server-side, so this node's agent
	// watches only its own pods and its own Node object. The informers
	// carry no resync period: the backstop ticker below owns periodic
	// repair, and a watch failure relists automatically.
	podFactory := informers.NewSharedInformerFactoryWithOptions(client, 0,
		informers.WithTweakListOptions(func(options *metav1.ListOptions) {
			options.FieldSelector = "spec.nodeName=" + nodeName
		}))
	nodeFactory := informers.NewSharedInformerFactoryWithOptions(client, 0,
		informers.WithTweakListOptions(func(options *metav1.ListOptions) {
			options.FieldSelector = "metadata.name=" + nodeName
		}))
	podInformer := podFactory.Core().V1().Pods()
	nodeInformer := nodeFactory.Core().V1().Nodes()

	if _, err := podInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj any) {
			if isShapedPod(obj) {
				kick()
			}
		},
		UpdateFunc: func(oldObj, newObj any) {
			// Either side annotated matters: annotation added, removed, or
			// a phase/IP change on a shaped pod.
			if isShapedPod(oldObj) || isShapedPod(newObj) {
				kick()
			}
		},
		DeleteFunc: func(obj any) {
			if isShapedPod(obj) {
				kick()
			}
		},
	}); err != nil {
		logger.Error("registering pod event handler", "error", err)
		os.Exit(1)
	}
	if _, err := nodeInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(any) { kick() },
		UpdateFunc: func(oldObj, newObj any) {
			// Node status updates are frequent (heartbeats, conditions);
			// only the advertised egress budget matters here.
			if nodeEgressCapacity(oldObj) != nodeEgressCapacity(newObj) {
				kick()
			}
		},
	}); err != nil {
		logger.Error("registering node event handler", "error", err)
		os.Exit(1)
	}

	podFactory.Start(ctx.Done())
	nodeFactory.Start(ctx.Done())
	if !cache.WaitForCacheSync(ctx.Done(), podInformer.Informer().HasSynced, nodeInformer.Informer().HasSynced) {
		logger.Error("informer caches never synced (shutdown during startup)")
		return
	}

	registry := prometheus.NewRegistry()
	registry.MustRegister(collectors.NewGoCollector())

	a := &agent.Agent{
		NodeName:        nodeName,
		DefaultNodeMbps: defaultNodeMbps,
		BetaPodPrefix:   os.Getenv("BETA_POD_PREFIX"),
		Pods:            podInformer.Lister(),
		Nodes:           nodeInformer.Lister(),
		Endpoints:       agent.NewEndpointResolver(ciliumSock),
		Tree:            agent.Tree{TrampolineDev: trampolineDev, ReturnDev: returnDev},
		Attacher:        agent.Attacher{PinRoot: pinRoot},
		Metrics:         agent.NewMetrics(registry),
		Log:             logger,
	}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	server := &http.Server{Addr: metricsAddr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("metrics server", "error", err)
			os.Exit(1)
		}
	}()

	// Events drive convergence; the ticker is the backstop that repairs
	// what no event reports (a stripped tcx link, a deleted trampoline
	// device, a stale pin).
	backstop := time.NewTicker(interval)
	defer backstop.Stop()
	kick() // initial convergence from the freshly synced caches
	for {
		select {
		case <-ctx.Done():
			// Deliberately no teardown: the pinned links keep enforcing
			// across agent restarts and upgrades. Removing shaping is an
			// explicit operator action (see AGENTS.md).
			_ = server.Close()
			return
		case <-trigger:
			if !settle(ctx, trigger) {
				_ = server.Close()
				return
			}
		case <-backstop.C:
		}
		cycle, cancel := context.WithTimeout(ctx, cycleTimeout)
		requeue, err := a.Reconcile(cycle)
		cancel()
		if err != nil {
			logger.Error("reconcile", "error", err)
		}
		if requeue {
			time.AfterFunc(endpointRetryDelay, kick)
		}
	}
}

// settle absorbs further triggers for debounceWindow after the first one, so
// a burst of pod events becomes one reconcile. Returns false on shutdown.
func settle(ctx context.Context, trigger <-chan struct{}) bool {
	timer := time.NewTimer(debounceWindow)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return false
		case <-trigger:
		case <-timer.C:
			return true
		}
	}
}

// isShapedPod reports whether an informer event object is a pod carrying the
// egress-class annotation, unwrapping delete tombstones.
func isShapedPod(obj any) bool {
	if tombstone, ok := obj.(cache.DeletedFinalStateUnknown); ok {
		obj = tombstone.Obj
	}
	pod, ok := obj.(*corev1.Pod)
	if !ok {
		return false
	}
	_, ok = pod.Annotations[agent.EgressClassAnnotation]
	return ok
}

func nodeEgressCapacity(obj any) string {
	node, ok := obj.(*corev1.Node)
	if !ok {
		return ""
	}
	quantity := node.Status.Capacity[corev1.ResourceName(agent.NodeEgressResource)]
	return quantity.String()
}

func kubernetesClient() (kubernetes.Interface, error) {
	config, err := rest.InClusterConfig()
	if err != nil {
		kubeconfig := os.Getenv("KUBECONFIG")
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			return nil, err
		}
	}
	return kubernetes.NewForConfig(config)
}

// levelEnv parses a slog level name ("debug", "info", "warn", "error",
// case-insensitive, offsets like "info+2" included) from the environment.
func levelEnv(key string, fallback slog.Level) (slog.Level, error) {
	value := os.Getenv(key)
	if value == "" {
		return fallback, nil
	}
	var level slog.Level
	if err := level.UnmarshalText([]byte(value)); err != nil {
		return fallback, err
	}
	return level, nil
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func durationEnv(logger *slog.Logger, key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		logger.Error("invalid duration", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}

func int64Env(logger *slog.Logger, key string, fallback int64) int64 {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		logger.Error("invalid integer", "env", key, "value", value)
		os.Exit(1)
	}
	return parsed
}
