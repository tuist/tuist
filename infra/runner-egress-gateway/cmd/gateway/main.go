// runner-egress-gateway terminates WireGuard tunnels from Mac runner hosts
// and forwards their traffic to the internet. See
// infra/runner-egress-gateway/AGENTS.md.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"golang.zx2c4.com/wireguard/wgctrl"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	corev1listers "k8s.io/client-go/listers/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/gateway"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/netdev"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/nftables"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/peers"
)

const (
	passTimeout     = time.Minute
	shutdownTimeout = 5 * time.Second
)

func main() {
	os.Exit(run())
}

func run() int {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	cfg, err := config.Parse(os.Args[1:], os.Stderr)
	if errors.Is(err, flag.ErrHelp) {
		return 0
	}
	if err != nil {
		logger.Error("invalid configuration", "error", err)
		return 2
	}
	logger = logger.With("gateway", cfg.GatewayName)

	restConfig, err := kubernetesConfig()
	if err != nil {
		logger.Error("load kubernetes config", "error", err)
		return 1
	}
	client, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		logger.Error("create kubernetes client", "error", err)
		return 1
	}

	wireGuard, err := wgctrl.New()
	if err != nil {
		logger.Error("open wireguard control", "error", err)
		return 1
	}
	defer wireGuard.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	factory := informers.NewSharedInformerFactory(client, 0)
	nodeInformer := factory.Core().V1().Nodes()
	informer := nodeInformer.Informer()
	if err := informer.SetTransform(stripNode); err != nil {
		logger.Error("set node transform", "error", err)
		return 1
	}
	trigger := make(chan struct{}, 1)
	notify := func() {
		select {
		case trigger <- struct{}{}:
		default:
		}
	}
	if _, err := informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(any) { notify() },
		UpdateFunc: func(oldObj, newObj any) {
			oldNode, okOld := oldObj.(*corev1.Node)
			newNode, okNew := newObj.(*corev1.Node)
			if !okOld || !okNew || peers.CandidateFor(oldNode) != peers.CandidateFor(newNode) {
				notify()
			}
		},
		DeleteFunc: func(any) { notify() },
	}); err != nil {
		logger.Error("add node event handler", "error", err)
		return 1
	}

	registry := prometheus.NewRegistry()
	registry.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)
	labeled := prometheus.WrapRegistererWith(prometheus.Labels{"gateway": cfg.GatewayName}, registry)

	reconciler := gateway.New(cfg, gateway.Deps{
		Link:       netdev.NewLink(),
		WireGuard:  wireGuard,
		NFT:        nftables.Exec{},
		Forwarding: netdev.Forwarding{},
		Nodes:      nodeLister{nodeInformer.Lister()},
		ReadKey:    gateway.KeyFileReader(cfg.PrivateKeyFile),
		Logger:     logger,
		Metrics:    gateway.NewMetrics(labeled),
	})
	labeled.MustRegister(gateway.NewPeerCollector(wireGuard, reconciler.NodeFor))

	tunnelListener, err := netdev.ListenFreebind(ctx, gateway.TunnelHealthAddress(cfg))
	if err != nil {
		logger.Error("listen for tunnel health checks", "address", gateway.TunnelHealthAddress(cfg), "error", err)
		return 1
	}

	started := time.Now()
	staleAfter := 3*cfg.ResyncInterval + passTimeout
	metricsMux := http.NewServeMux()
	metricsMux.Handle("GET /metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	servers := []*http.Server{
		{Addr: cfg.ProbeAddr, Handler: gateway.ProbeHandler(reconciler, started, staleAfter, time.Now), ReadHeaderTimeout: 5 * time.Second},
		{Addr: cfg.MetricsAddr, Handler: metricsMux, ReadHeaderTimeout: 5 * time.Second},
	}
	tunnelServer := &http.Server{Handler: gateway.TunnelHealthHandler(reconciler), ReadHeaderTimeout: 5 * time.Second}

	serverErrors := make(chan error, len(servers)+1)
	for _, server := range servers {
		go func() {
			if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
				serverErrors <- err
			}
		}()
	}
	go func() {
		if err := tunnelServer.Serve(tunnelListener); !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
		}
	}()
	defer shutdown(logger, append(servers, tunnelServer))

	logger.Info("starting",
		"listen_port", cfg.ListenPort,
		"tunnel_address", cfg.TunnelAddress.String(),
		"peer_cidr", cfg.PeerCIDR.String(),
		"out_interface", cfg.OutInterface,
		"snat", cfg.SNAT.String(),
	)

	factory.Start(ctx.Done())
	if !cache.WaitForCacheSync(ctx.Done(), informer.HasSynced) {
		if ctx.Err() != nil {
			return 0
		}
		logger.Error("node cache did not sync")
		return 1
	}

	ticker := time.NewTicker(cfg.ResyncInterval)
	defer ticker.Stop()
	wasReady := false
	for {
		passCtx, cancel := context.WithTimeout(ctx, passTimeout)
		err := reconciler.Reconcile(passCtx)
		cancel()
		status := reconciler.Status()
		if err != nil {
			logger.Error("reconcile failed", "error", err, "ready", status.Ready())
		}
		if status.Ready() != wasReady {
			logger.Info("readiness changed", "ready", status.Ready(), "forwarding", status.Forwarding, "link", status.Link, "rules", status.Rules, "peers_synced", status.PeersSynced)
			wasReady = status.Ready()
		}

		select {
		case <-ctx.Done():
			logger.Info("shutting down")
			return 0
		case err := <-serverErrors:
			logger.Error("http server failed", "error", err)
			return 1
		case <-ticker.C:
		case <-trigger:
		}
	}
}

func shutdown(logger *slog.Logger, servers []*http.Server) {
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	for _, server := range servers {
		if err := server.Shutdown(ctx); err != nil {
			logger.Warn("http server shutdown", "error", err)
		}
	}
}

func kubernetesConfig() (*rest.Config, error) {
	if cfg, err := rest.InClusterConfig(); err == nil {
		return cfg, nil
	}
	rules := clientcmd.NewDefaultClientConfigLoadingRules()
	return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, &clientcmd.ConfigOverrides{}).ClientConfig()
}

func stripNode(obj any) (any, error) {
	if node, ok := obj.(*corev1.Node); ok {
		node.ManagedFields = nil
		node.Status.Images = nil
	}
	return obj, nil
}

type nodeLister struct {
	lister corev1listers.NodeLister
}

func (l nodeLister) List() ([]*corev1.Node, error) {
	return l.lister.List(labels.Everything())
}
