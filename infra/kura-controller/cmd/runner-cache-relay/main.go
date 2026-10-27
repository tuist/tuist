package main

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/kura-controller/internal/runnerrelay"
	"golang.org/x/net/http2"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
)

type transports struct {
	http1 *http.Transport
	http2 *http2.Transport
}

func (t transports) RoundTrip(r *http.Request) (*http.Response, error) {
	if strings.HasPrefix(r.Header.Get("Content-Type"), "application/grpc") {
		return t.http2.RoundTrip(r)
	}
	return t.http1.RoundTrip(r)
}

func relayServer(handler http.Handler) *http.Server {
	protocols := new(http.Protocols)
	protocols.SetHTTP1(true)
	protocols.SetUnencryptedHTTP2(true)
	// Use the native HTTP/2 server so Shutdown tracks active gRPC streams too.
	return &http.Server{Addr: ":8080", Handler: handler, Protocols: protocols,
		ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second}
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatal("in-cluster configuration unavailable")
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal("Kubernetes client unavailable")
	}
	// Pool labels alone are mutable. Refuse to serve on an OVH/cache/runner
	// host even if it were accidentally labeled as general-purpose capacity.
	node, err := client.CoreV1().Nodes().Get(ctx, os.Getenv("NODE_NAME"), metav1.GetOptions{})
	if err != nil || !strings.HasPrefix(node.Spec.ProviderID, "hcloud://") || node.Labels["tuist.dev/private-network"] != "" {
		log.Fatal("WAN relay requires an unenrolled Hetzner Cloud node")
	}
	namespace := os.Getenv("POD_NAMESPACE")
	factory := informers.NewSharedInformerFactoryWithOptions(client, 0,
		informers.WithNamespace(namespace), informers.WithTweakListOptions(func(options *metav1.ListOptions) {
			options.LabelSelector = runnerrelay.Label + "=true"
		}))
	services := factory.Core().V1().Services()
	services.Informer()
	factory.Start(ctx.Done())
	if !cache.WaitForCacheSync(ctx.Done(), services.Informer().HasSynced) {
		log.Fatal("cache routes unavailable")
	}
	dialer := &net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}
	transport := transports{
		http1: &http.Transport{DialContext: dialer.DialContext, MaxIdleConns: 1024, MaxIdleConnsPerHost: 32,
			IdleConnTimeout: 10 * time.Second, ResponseHeaderTimeout: 60 * time.Second},
		http2: &http2.Transport{AllowHTTP: true, DialTLSContext: func(ctx context.Context, network, addr string, _ *tls.Config) (net.Conn, error) {
			return dialer.DialContext(ctx, network, addr)
		}},
	}
	handler := runnerrelay.NewHandler(namespace, services.Lister().Services(namespace).Get, transport)
	server := relayServer(handler)
	health := &http.Server{Addr: ":8081", ReadHeaderTimeout: 5 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })}
	go func() {
		if err := health.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("health listener failed")
		}
	}()
	shutdownDone := make(chan struct{})
	go func() {
		<-ctx.Done()
		defer close(shutdownDone)
		shutdown, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = health.Shutdown(shutdown)
		_ = server.Shutdown(shutdown)
	}()
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal("cache relay listener failed")
	}
	<-shutdownDone
}
