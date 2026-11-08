// kvm-device-plugin runs as a DaemonSet on Kata runner hosts labelled
// tuist.dev/kata-kvm=true and advertises devices.tuist.dev/kvm, which
// nested-virtualization runner Pods request to get /dev/kvm. See
// internal/kvmdeviceplugin.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"github.com/tuist/tuist/infra/runners-controller/internal/kvmdeviceplugin"
)

func main() {
	socketDir := flag.String("socket-dir", "/var/lib/kubelet/device-plugins", "kubelet device-plugin directory")
	cdiDir := flag.String("cdi-dir", "/var/run/cdi", "containerd CDI spec directory the plugin publishes /dev/kvm in")
	devicePath := flag.String("device-path", kvmdeviceplugin.DevicePath, "host /dev/kvm as mounted into this container")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatal(err)
	}
	config.Timeout = 10 * time.Second
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal(err)
	}
	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		log.Fatal("NODE_NAME is required")
	}
	deviceCount := func(ctx context.Context) (int, error) {
		node, err := client.CoreV1().Nodes().Get(ctx, nodeName, metav1.GetOptions{})
		if err != nil {
			return 0, err
		}
		count := node.Status.Allocatable[corev1.ResourcePods]
		if count.Value() <= 0 {
			return 0, fmt.Errorf("node %s has no allocatable Pod capacity", nodeName)
		}
		return int(count.Value()), nil
	}
	devices, err := deviceCount(ctx)
	if err != nil {
		log.Fatal(err)
	}

	plugin := &kvmdeviceplugin.Plugin{
		SocketDir:    *socketDir,
		SocketName:   "tuist-kvm.sock",
		CDIDir:       *cdiDir,
		DevicePath:   *devicePath,
		Devices:      devices,
		DeviceCount:  deviceCount,
		PollInterval: 30 * time.Second,
		Logf:         log.Printf,
	}
	if err := plugin.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
