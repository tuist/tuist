// kvm-device-plugin runs as a DaemonSet on Kata runner hosts labelled
// tuist.dev/kata-kvm=true and advertises devices.tuist.dev/kvm, which
// nested-virtualization runner Pods request to get /dev/kvm. See
// internal/kvmdeviceplugin.
package main

import (
	"context"
	"flag"
	"log"
	"os/signal"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/runners-controller/internal/kvmdeviceplugin"
)

func main() {
	socketDir := flag.String("socket-dir", "/var/lib/kubelet/device-plugins", "kubelet device-plugin directory")
	cdiDir := flag.String("cdi-dir", "/var/run/cdi", "containerd CDI spec directory the plugin publishes /dev/kvm in")
	devicePath := flag.String("device-path", kvmdeviceplugin.DevicePath, "host /dev/kvm as mounted into this container")
	devices := flag.Int("devices", 64, "allocatable units per node; KVM is shared, so this only bounds concurrent Pods")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	plugin := &kvmdeviceplugin.Plugin{
		SocketDir:    *socketDir,
		SocketName:   "tuist-kvm.sock",
		CDIDir:       *cdiDir,
		DevicePath:   *devicePath,
		Devices:      *devices,
		PollInterval: 5 * time.Second,
		Logf:         log.Printf,
	}
	if err := plugin.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
