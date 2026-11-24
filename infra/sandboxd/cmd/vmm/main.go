// Command vmm runs in the sandboxd Pod's vmm container and spawns the
// Firecracker VMs for the daemon, so they sit in this container's cgroup
// rather than the daemon's (internal/vm.VMMServer). It keeps no state: a VM
// lives as long as the daemon's connection for it.
package main

import (
	"log/slog"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/envfile"
	"github.com/tuist/tuist/infra/sandboxd/internal/hostinfo"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

var version = "dev"

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if err := envfile.Load(os.Getenv("SANDBOXD_CONFIG")); err != nil {
		logger.Error("loading the config file", "error", err)
		os.Exit(1)
	}
	socket := os.Getenv("VMM_SOCKET")
	if socket == "" {
		socket = "/run/vmm/vmm.sock"
	}
	if err := vm.SetChildSubreaper(); err != nil {
		logger.Error("setting child subreaper", "error", err)
		os.Exit(1)
	}

	// The daemon creates each VM's cgroup under this container's and the
	// server resizes this container, so the VMs' memory counts here.
	floor := uint64(protocol.DefaultCPUGuaranteeMilli)
	if milli, err := strconv.ParseUint(os.Getenv("CPU_FLOOR_MILLI"), 10, 64); err == nil && milli > 0 {
		floor = milli
	}
	cgroup, err := hostinfo.SetupVMMCgroups(floor)
	if err != nil {
		logger.Warn("per-VM cgroups are off; every VM shares the vmm container's", "error", err)
		data, readErr := os.ReadFile("/proc/self/cgroup")
		if readErr != nil {
			logger.Error("reading the container's cgroup", "error", readErr)
			os.Exit(1)
		}
		cgroup = hostinfo.ParseCgroupPath(string(data))
	}

	if err := os.MkdirAll(filepath.Dir(socket), 0o700); err != nil {
		logger.Error("creating the socket directory", "error", err)
		os.Exit(1)
	}
	_ = os.Remove(socket)
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: socket, Net: "unix"})
	if err != nil {
		logger.Error("listening", "socket", socket, "error", err)
		os.Exit(1)
	}
	if err := os.Chmod(socket, 0o600); err != nil {
		logger.Error("restricting the socket", "error", err)
		os.Exit(1)
	}
	server := &vm.VMMServer{Launcher: &vm.FirecrackerLauncher{Log: logger}, Cgroup: cgroup, Log: logger}
	logger.Info("vmm started", "version", version, "socket", socket, "cgroup", cgroup)

	go func() {
		if err := server.Serve(ln); err != nil {
			logger.Error("serving", "error", err)
			os.Exit(1)
		}
	}()
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	<-signals
	// Keep serving: the daemon is pausing its VMs now and may still spawn
	// one for a resume in flight. The kubelet's grace period bounds this.
	logger.Info("vmm stopping once the daemon released its VMs", "active", server.Active())
	for server.Active() > 0 {
		time.Sleep(200 * time.Millisecond)
	}
	logger.Info("vmm stopped")
}
