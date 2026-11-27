package podagent

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"path/filepath"
	"sync"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus"
	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

// ActionsCacheGuestURL is where a guest reaches this host's GitHub Actions
// cache: the vmnet gateway, which is the host's own bridge address. The
// runner image's node shim reads it from TUIST_ACTIONS_CACHE_URL.
const ActionsCacheGuestURL = "http://192.168.64.1:8090"

// actionsCacheReserve keeps staged uploads from taking the cache volume's last
// gigabytes from the custom volumes, whose reservations availableBytes does
// not subtract.
const actionsCacheReserve = 20 << 30

var vmSubnet = netip.MustParsePrefix("192.168.64.0/22")

var (
	actionsCacheOperations = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "tuist_runner_actions_cache_operations_total", Help: "GitHub Actions cache operations by result: a lookup is a hit or miss, lookup_github is GitHub's answer to a lookup the mirror missed, enabled is whether a job's account uses the mirror, a store is a finished upload copied to the store."}, []string{"operation", "result"})
	actionsCacheBytes      = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "tuist_runner_actions_cache_bytes_total", Help: "GitHub Actions cache bytes received from jobs (upload), copied to the store (store) or relayed from it (download)."}, []string{"operation", "result"})
	actionsCacheDuration   = prometheus.NewHistogramVec(prometheus.HistogramOpts{Name: "tuist_runner_actions_cache_operation_duration_seconds", Help: "GitHub Actions cache operation duration, including unsuccessful attempts.", Buckets: []float64{0.005, 0.025, 0.1, 0.5, 2, 10, 60, 300}}, []string{"operation"})
)

func init() {
	metrics.Registry.MustRegister(actionsCacheOperations, actionsCacheBytes, actionsCacheDuration)
}

// ActionsCache serves GitHub's Actions cache to this host's runner VMs, the
// way the Linux cache agent serves its node's runner Pods: uploads are staged
// on the runner cache volume and copied to the store StoreURL names, restores
// are relayed from it, and the server keeps the index. The guests reach it on
// the vmnet gateway; only the host talks to the store.
type ActionsCache struct {
	// Addr is where the cache listens, such as ":8090". The VM egress guard
	// passes guests to the host on its port.
	Addr string
	// StoreURL is the store's endpoint for this host's site, probed for health.
	StoreURL string
	Custom   *CustomVolumes
	Pods     client.Reader
}

// NeedLeaderElection is false: every host serves its own guests.
func (a *ActionsCache) NeedLeaderElection() bool { return false }

func (a *ActionsCache) Start(ctx context.Context) error {
	logger := slog.New(logr.ToSlogHandler(log.Log.WithName("actions-cache")))
	store := &cachevolumes.ActionsStore{Root: filepath.Join(a.Custom.Space.Root, "actions-cache"), Reserve: actionsCacheReserve, Log: logger,
		FreeBytes: func(string) (uint64, error) { return a.Custom.Space.availableBytes() }}
	index := &cachevolumes.ActionsServer{URL: a.Custom.URL + "/actions-cache", Node: a.Custom.Node, Token: a.Custom.token, Client: cachevolumes.NewServerClient(time.Minute), Log: logger}
	pods := &vmPods{reader: a.Pods, node: a.Custom.Node}
	cache := &cachevolumes.ActionsCache{Index: index, Store: store, StoreURL: a.StoreURL, Caller: pods.caller, Client: &http.Client{}, Record: recordActionsCache, Log: logger}
	go cache.Run(ctx)
	go func() {
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		for {
			if err := store.Maintain(); err != nil {
				logger.Warn("actions cache maintenance failed", "error", err.Error())
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	// The Linux agent's timeouts; uploads and downloads extend their own.
	server := &http.Server{Addr: a.Addr, Handler: guestsOnly(cache), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 20 * time.Second, WriteTimeout: 7 * time.Minute, MaxHeaderBytes: 32768}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// guestsOnly answers only this host's guests. The listener binds every
// address, because vmnet creates the bridge only once a VM runs, so the
// rack's segment could otherwise use the cache's pass-through to GitHub.
func guestsOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		addr, err := netip.ParseAddr(host)
		if err != nil || !vmSubnet.Contains(addr.Unmap()) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func recordActionsCache(operation, result string, bytes int64, start time.Time) {
	actionsCacheOperations.WithLabelValues(operation, result).Inc()
	actionsCacheDuration.WithLabelValues(operation).Observe(time.Since(start).Seconds())
	if bytes > 0 {
		actionsCacheBytes.WithLabelValues(operation, result).Add(float64(bytes))
	}
}

var errUnknownGuest = errors.New("not a runner VM on this host")

// vmPods resolves a request's source address to the running runner Pod whose
// VM has it. tart-kubelet reports a runner VM's address as its PodIP.
type vmPods struct {
	reader client.Reader
	node   string
	mu     sync.Mutex
	byIP   map[string]cachevolumes.ActionsCaller
	listed time.Time
}

func (p *vmPods) caller(ctx context.Context, ip string) (cachevolumes.ActionsCaller, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	caller, ok := p.byIP[ip]
	// vmnet hands a released address out again only after its lease, far
	// longer than a listing lives.
	if ok && time.Since(p.listed) < 5*time.Second {
		return caller, nil
	}
	if time.Since(p.listed) < time.Second {
		if ok {
			return caller, nil
		}
		return cachevolumes.ActionsCaller{}, errUnknownGuest
	}
	pods := &corev1.PodList{}
	if err := p.reader.List(ctx, pods, client.MatchingLabels{runnerPodLabel: "true"}); err != nil {
		return cachevolumes.ActionsCaller{}, err
	}
	p.byIP = map[string]cachevolumes.ActionsCaller{}
	for _, pod := range pods.Items {
		if pod.Status.PodIP != "" && pod.Status.Phase == corev1.PodRunning && pod.DeletionTimestamp == nil && pod.Spec.NodeName == p.node {
			p.byIP[pod.Status.PodIP] = cachevolumes.ActionsCaller{PodName: pod.Name, PodUID: string(pod.UID)}
		}
	}
	p.listed = time.Now()
	if caller, ok = p.byIP[ip]; ok {
		return caller, nil
	}
	return cachevolumes.ActionsCaller{}, errUnknownGuest
}
