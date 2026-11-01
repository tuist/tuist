package main

import (
	"context"
	"log"
	"net"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandbox-image/internal/executiongateway"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	"google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/keepalive"
)

func main() {
	serverURL := os.Getenv("TUIST_URL")
	u, err := url.Parse(serverURL)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		log.Fatal("TUIST_URL must be an HTTP(S) server URL")
	}
	address := os.Getenv("LISTEN_ADDR")
	if address == "" {
		address = ":50051"
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		log.Fatal(err)
	}
	s := grpc.NewServer(grpc.MaxRecvMsgSize(64<<10), grpc.MaxSendMsgSize(256<<10), grpc.MaxConcurrentStreams(128), grpc.ConnectionTimeout(10*time.Second), grpc.KeepaliveParams(keepalive.ServerParameters{MaxConnectionAge: 15 * time.Minute, MaxConnectionAgeGrace: 10 * time.Second}))
	gateway := executiongateway.New(serverURL)
	gateway.Register(s)
	h := health.NewServer()
	grpc_health_v1.RegisterHealthServer(s, h)
	h.SetServingStatus("", grpc_health_v1.HealthCheckResponse_SERVING)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	stopped := make(chan struct{})
	go func() {
		<-ctx.Done()
		h.Shutdown()
		time.AfterFunc(10*time.Second, s.Stop)
		s.GracefulStop()
		close(stopped)
	}()
	if err = s.Serve(listener); err != nil {
		log.Fatal(err)
	}
	// Streams finish first, so their action-cache publications are pending.
	<-stopped
	drain, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	gateway.Wait(drain)
}
