package main

import (
	"context"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/kura-controller/internal/activation"
)

func main() {
	httpAddr := flag.String("http-address", ":8080", "HTTP listener")
	grpcAddr := flag.String("grpc-address", ":8081", "h2c gRPC listener")
	prod := flag.String("production-server", "https://tuist.dev", "Production control plane")
	canary := flag.String("canary-server", "https://canary.tuist.dev", "Canary control plane")
	staging := flag.String("staging-server", "https://staging.tuist.dev", "Staging control plane")
	flag.Parse()
	gateway := activation.New(activation.Servers{"production": *prod, "canary": *canary, "staging": *staging}, 128)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	servers := []*http.Server{activation.Server(*httpAddr, gateway), activation.Server(*grpcAddr, gateway)}
	for _, server := range servers {
		go func() {
			if err := activation.Listen(server); err != nil {
				slog.Error("activation listener failed", "error", err)
				os.Exit(1)
			}
		}()
	}
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var waiting sync.WaitGroup
	for _, server := range servers {
		waiting.Go(func() { _ = server.Shutdown(shutdown) })
	}
	waiting.Wait()
}
