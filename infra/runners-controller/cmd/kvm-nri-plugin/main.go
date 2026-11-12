// kvm-nri-plugin runs as a DaemonSet on Kata runner hosts labelled
// tuist.dev/kata-kvm=true and gives /dev/kvm to the runner containers of
// exclusive-CPU pools, whose Pod-level budget rules out the
// devices.tuist.dev/kvm device plugin. See internal/kvmnri.
package main

import (
	"context"
	"flag"
	"log"
	"os/signal"
	"syscall"

	"github.com/containerd/nri/pkg/api"
	"github.com/containerd/nri/pkg/stub"

	"github.com/tuist/tuist/infra/runners-controller/internal/kvmnri"
)

type plugin struct {
	namespace string
}

func (p *plugin) CreateContainer(_ context.Context, pod *api.PodSandbox, ctr *api.Container) (*api.ContainerAdjustment, []*api.ContainerUpdate, error) {
	adjustment := kvmnri.Adjust(p.namespace, pod, ctr)
	if adjustment != nil {
		log.Printf("injecting %s into %s/%s container %s", kvmnri.DevicePath, pod.GetNamespace(), pod.GetName(), ctr.GetName())
	}
	return adjustment, nil, nil
}

func main() {
	socket := flag.String("socket", "/var/run/nri/nri.sock", "containerd NRI socket")
	namespace := flag.String("namespace", "tuist-runners", "namespace of the runner Pods that get /dev/kvm")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	s, err := stub.New(&plugin{namespace: *namespace},
		stub.WithPluginName("tuist-kvm"),
		stub.WithPluginIdx("50"),
		stub.WithSocketPath(*socket),
	)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("registering with %s for namespace %s", *socket, *namespace)
	// Run returns the context's error on SIGTERM; only other errors fail.
	if err := s.Run(ctx); err != nil && ctx.Err() == nil {
		log.Fatal(err)
	}
}
