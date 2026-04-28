// Command tart-cri is the Container Runtime Interface (CRI) runtime
// that drives Tart on macOS. Kubelet on a Mac mini connects to it via
// the Unix socket configured in /etc/kubernetes/kubelet-config.yaml.
//
//   kubelet  ─CRI gRPC─►  tart-cri  ─tart CLI─►  Tart VMs
//
// One Pod ↔ one Tart VM. The first container in a Pod becomes the VM
// image; additional containers in the same Pod are not supported (CRI
// allows reporting that limitation via the runtime status conditions
// — kubelet refuses to schedule unsupported pod shapes onto the node).
package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"

	"github.com/tuist/tuist/infra/tart-cri/internal/imageservice"
	"github.com/tuist/tuist/infra/tart-cri/internal/runtimeservice"
	"github.com/tuist/tuist/infra/tart-cri/internal/state"
	"github.com/tuist/tuist/infra/tart-cri/internal/tart"
)

func main() {
	var (
		socket    = flag.String("socket", "/var/run/tart-cri/tart-cri.sock", "Unix socket kubelet connects to")
		statePath = flag.String("state", "/var/lib/tart-cri/state.json", "Persistent state file")
		logDir    = flag.String("log-dir", "/var/log/tart-cri", "Per-container log root")
	)
	flag.Parse()

	if err := run(*socket, *statePath, *logDir); err != nil {
		fmt.Fprintf(os.Stderr, "tart-cri: %v\n", err)
		os.Exit(1)
	}
}

func run(socket, statePath, logDir string) error {
	t, err := tart.NewRuntime()
	if err != nil {
		return err
	}

	store, err := state.New(statePath)
	if err != nil {
		return fmt.Errorf("open state: %w", err)
	}

	rs := runtimeservice.New(t, store, logDir)
	is := imageservice.New(t)

	// Remove a stale socket from a prior crash.
	_ = os.Remove(socket)
	if err := os.MkdirAll(socketDir(socket), 0o755); err != nil {
		return fmt.Errorf("mkdir socket dir: %w", err)
	}
	lis, err := net.Listen("unix", socket)
	if err != nil {
		return fmt.Errorf("listen %s: %w", socket, err)
	}
	if err := os.Chmod(socket, 0o660); err != nil {
		return fmt.Errorf("chmod socket: %w", err)
	}

	srv := grpc.NewServer()
	runtimeapi.RegisterRuntimeServiceServer(srv, rs)
	runtimeapi.RegisterImageServiceServer(srv, is)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	go func() {
		<-ctx.Done()
		srv.GracefulStop()
	}()

	fmt.Fprintf(os.Stderr, "tart-cri serving on %s\n", socket)
	if err := srv.Serve(lis); err != nil {
		return err
	}
	return nil
}

func socketDir(path string) string {
	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == '/' {
			return path[:i]
		}
	}
	return "."
}
