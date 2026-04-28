// Command vk-orchard is the Virtual Kubelet provider that exposes a Tuist
// Orchard fleet (Scaleway Mac minis hosting Tart VMs) as a virtual k8s
// Node. Pods scheduled onto the node get translated to Orchard VM
// lifecycle calls.
//
// Configuration is via environment variables. All k8s API access uses
// the in-cluster service account.
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/virtual-kubelet/virtual-kubelet/log"
	logruslogger "github.com/virtual-kubelet/virtual-kubelet/log/logrus"
	"github.com/virtual-kubelet/virtual-kubelet/node"
	"github.com/virtual-kubelet/virtual-kubelet/node/api"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"
	typedcorev1 "k8s.io/client-go/kubernetes/typed/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/record"

	"github.com/tuist/tuist/infra/vk-orchard/internal/orchard"
	"github.com/tuist/tuist/infra/vk-orchard/internal/provider"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "vk-orchard: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		nodeName   = envDefault("VK_NODE_NAME", "tuist-orchard")
		orchardURL = os.Getenv("ORCHARD_URL")
		orchardSAN = os.Getenv("ORCHARD_SERVICE_ACCOUNT_NAME")
		orchardSAT = os.Getenv("ORCHARD_SERVICE_ACCOUNT_TOKEN")
		listenAddr = envDefault("VK_LISTEN_ADDR", ":10250")
		kubeconfig = os.Getenv("KUBECONFIG")
	)

	if orchardURL == "" {
		return fmt.Errorf("ORCHARD_URL is required")
	}

	logger := logrus.New()
	logger.SetFormatter(&logrus.TextFormatter{FullTimestamp: true})
	log.L = logruslogger.FromLogrus(logrus.NewEntry(logger))

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	clientset, err := kubeClient(kubeconfig)
	if err != nil {
		return fmt.Errorf("k8s client: %w", err)
	}

	orchardClient := orchard.NewClient(orchardURL, orchardSAN, orchardSAT)
	prov := provider.New(nodeName, orchardClient)

	if err := prov.Resync(ctx); err != nil {
		// Non-fatal — first run won't have any VMs and this also helps
		// surface a misconfigured Orchard URL early. Log loud and
		// continue; the node won't go Ready until Orchard is reachable
		// (Ping in NodeProvider gates that), so a hard exit here would
		// just hide the cause behind a CrashLoopBackOff.
		log.G(ctx).Warnf("initial resync failed (continuing): %v", err)
	}

	nodeProv := provider.NewNodeProvider(prov)

	nodeTemplate := buildNodeTemplate(nodeName)

	// PodController: routes API-server Pod events to our Provider.
	informerFactory := informers.NewSharedInformerFactoryWithOptions(
		clientset, 10*time.Minute,
		informers.WithTweakListOptions(func(opts *metav1.ListOptions) {
			opts.FieldSelector = "spec.nodeName=" + nodeName
		}),
	)

	eventBroadcaster := record.NewBroadcaster()
	eventBroadcaster.StartLogging(logger.Infof)
	eventBroadcaster.StartRecordingToSink(&typedcorev1.EventSinkImpl{
		Interface: clientset.CoreV1().Events(""),
	})
	eventRecorder := eventBroadcaster.NewRecorder(scheme.Scheme, corev1.EventSource{Component: "vk-orchard"})

	podController, err := node.NewPodController(node.PodControllerConfig{
		PodClient:         clientset.CoreV1(),
		PodInformer:       informerFactory.Core().V1().Pods(),
		EventRecorder:     eventRecorder,
		Provider:          prov,
		ConfigMapInformer: informerFactory.Core().V1().ConfigMaps(),
		SecretInformer:    informerFactory.Core().V1().Secrets(),
		ServiceInformer:   informerFactory.Core().V1().Services(),
	})
	if err != nil {
		return fmt.Errorf("new pod controller: %w", err)
	}

	// NodeController: keeps the virtual Node resource in the API server.
	nodeController, err := node.NewNodeController(
		nodeProv,
		nodeTemplate,
		clientset.CoreV1().Nodes(),
		node.WithNodeEnableLeaseV1(clientset.CoordinationV1().Leases(corev1.NamespaceNodeLease), 40),
	)
	if err != nil {
		return fmt.Errorf("new node controller: %w", err)
	}

	informerFactory.Start(ctx.Done())
	informerFactory.WaitForCacheSync(ctx.Done())

	// HTTP server hosting kubelet's pod-runtime endpoints. The VK runtime
	// requires this even though we proxy logs through Orchard;
	// `kubectl logs` and friends still hit the kubelet API on this address.
	mux := http.NewServeMux()
	api.AttachPodRoutes(api.PodHandlerConfig{
		GetContainerLogs:  prov.GetContainerLogs,
		RunInContainer:    prov.RunInContainer,
		AttachToContainer: prov.AttachToContainer,
		PortForward:       prov.PortForward,
		GetPods:           prov.GetPods,
	}, mux, true)

	server := &http.Server{Addr: listenAddr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.G(ctx).Errorf("http server: %v", err)
			cancel()
		}
	}()

	go func() {
		if err := podController.Run(ctx, 1); err != nil {
			log.G(ctx).Errorf("pod controller: %v", err)
			cancel()
		}
	}()

	log.G(ctx).Infof("vk-orchard up: node=%s orchard=%s addr=%s", nodeName, orchardURL, listenAddr)
	if err := nodeController.Run(ctx); err != nil && err != context.Canceled {
		return fmt.Errorf("node controller: %w", err)
	}

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()
	_ = server.Shutdown(shutdownCtx)

	log.G(ctx).Infof("vk-orchard shut down")
	return nil
}

func buildNodeTemplate(nodeName string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: nodeName,
			Labels: map[string]string{
				"kubernetes.io/role":      "agent",
				"kubernetes.io/os":        "darwin",
				"kubernetes.io/arch":      "arm64",
				"type":                    "virtual-kubelet",
				"tuist.dev/orchard-fleet": "true",
			},
		},
		Spec: corev1.NodeSpec{
			Taints: []corev1.Taint{
				{Key: "tuist.dev/macos", Value: "true", Effect: corev1.TaintEffectNoSchedule},
				{Key: "virtual-kubelet.io/provider", Value: "vk-orchard", Effect: corev1.TaintEffectNoSchedule},
			},
		},
	}
}

func kubeClient(kubeconfig string) (*kubernetes.Clientset, error) {
	var cfg *rest.Config
	var err error
	if kubeconfig != "" {
		cfg, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
	} else {
		cfg, err = rest.InClusterConfig()
	}
	if err != nil {
		return nil, err
	}
	return kubernetes.NewForConfig(cfg)
}

func envDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
