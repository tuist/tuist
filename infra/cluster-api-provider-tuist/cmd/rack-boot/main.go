// Command rack-boot is a rack's boot server (internal/rackboot), run by the
// rack-boot DaemonSet on each edge node of a site with host networking.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	toolscache "k8s.io/client-go/tools/cache"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackboot"
)

func main() {
	ctrl.SetLogger(zap.New())
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "rack-boot: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var cfg rackboot.Config
	var apiFile string
	flag.StringVar(&cfg.Address, "address", "", "the site's provisioning address")
	flag.IntVar(&cfg.HTTPPort, "http-port", 8480, "the HTTP port on the provisioning address and the edges' link")
	flag.StringVar(&cfg.ISOURL, "iso-url", "", "the Ubuntu installer ISO")
	flag.StringVar(&cfg.ISOSHA256, "iso-sha256", "", "the ISO's SHA-256")
	flag.StringVar(&cfg.StateDir, "state-dir", "/var/lib/tuist-rack-boot", "a directory kept on the node, which holds the ISO")
	flag.StringVar(&cfg.NetbootDir, "netboot-dir", "/opt/rack-netboot", "the signed iPXE")
	flag.StringVar(&cfg.NodeBinary, "node-binary", "/opt/rack-node/rack-node-linux-amd64", "the rack-node binary an install stick asks for its seed with")
	flag.StringVar(&cfg.Namespace, "namespace", os.Getenv("POD_NAMESPACE"), "the fleet's namespace")
	flag.StringVar(&cfg.SecretName, "secret", "", "the boot Secret the operator publishes installs to")
	flag.StringVar(&cfg.Site, "site", "", "the site this boot server serves")
	flag.StringVar(&cfg.Node, "node", os.Getenv("NODE_NAME"), "the edge node it runs on")
	flag.StringVar(&cfg.PeerInterface, "peer-interface", "vrrp0", "the link between the site's edges")
	flag.DurationVar(&cfg.PeerWait, "peer-wait", 2*time.Minute, "how long a fresh edge waits for the edges' link before downloading the ISO from the internet")
	flag.StringVar(&apiFile, "kubernetes-api-file", "/etc/tuist/kubernetes-api", "a file on the node naming the API server its kubelet uses; a rack node reaches no Service address")
	flag.Parse()
	for name, value := range map[string]string{"address": cfg.Address, "iso-url": cfg.ISOURL, "iso-sha256": cfg.ISOSHA256,
		"namespace": cfg.Namespace, "secret": cfg.SecretName, "site": cfg.Site, "node": cfg.Node} {
		if value == "" {
			return fmt.Errorf("--%s is required", name)
		}
	}

	restConfig, err := rest.InClusterConfig()
	if err != nil {
		return err
	}
	if server, err := os.ReadFile(apiFile); err == nil && strings.TrimSpace(string(server)) != "" {
		restConfig.Host = strings.TrimSpace(string(server))
	}
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		return err
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	informers, err := cache.New(restConfig, cache.Options{
		Scheme:            scheme,
		DefaultNamespaces: map[string]cache.Config{cfg.Namespace: {}},
		ByObject: map[client.Object]cache.ByObject{
			// The boot Secret alone: RBAC grants this one by name.
			&corev1.Secret{}: {Field: fields.OneTermEqualSelector("metadata.name", cfg.SecretName)},
		},
	})
	if err != nil {
		return err
	}
	cached, err := client.New(restConfig, client.Options{Scheme: scheme, Cache: &client.CacheOptions{Reader: informers}})
	if err != nil {
		return err
	}
	direct, err := client.New(restConfig, client.Options{Scheme: scheme})
	if err != nil {
		return err
	}

	log := ctrl.Log.WithName("rack-boot")
	server := rackboot.NewServer(cfg, cached, direct, log)
	secrets, err := informers.GetInformer(ctx, &corev1.Secret{})
	if err != nil {
		return err
	}
	set := func(obj any) {
		if s, ok := obj.(*corev1.Secret); ok && s.Name == cfg.SecretName {
			server.SetInstalls(s.Data)
		}
	}
	if _, err := secrets.AddEventHandler(toolscache.ResourceEventHandlerFuncs{
		AddFunc:    set,
		UpdateFunc: func(_, obj any) { set(obj) },
		DeleteFunc: func(any) { server.SetInstalls(nil) },
	}); err != nil {
		return err
	}
	if _, err := informers.GetInformer(ctx, &infrav1.RackLinuxCandidate{}); err != nil {
		return err
	}
	go func() {
		if err := informers.Start(ctx); err != nil {
			log.Error(err, "watch the boot Secret and the candidates")
			stop()
		}
	}()
	if !informers.WaitForCacheSync(ctx) {
		return fmt.Errorf("the boot Secret and the candidates did not sync")
	}
	return server.Run(ctx)
}
