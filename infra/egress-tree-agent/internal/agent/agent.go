package agent

import (
	"context"
	"fmt"
	"log/slog"
	"net"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Agent reconciles the shared per-node egress HTB tree: the trampoline
// devices, the tree itself, and one tcx program per shaped kura pod. Each
// cycle is idempotent and ordered fail-safe: the return program is confirmed
// before any pod program exists, so a shaped packet always has a way back
// into Cilium.
type Agent struct {
	NodeName string
	// DefaultNodeMbps is the observe-mode fallback root ceiling for nodes
	// that do not advertise tuist.dev/egress-mbps capacity. Zero means: no
	// budget, no tree, pods stay unshaped.
	DefaultNodeMbps int64

	Client    kubernetes.Interface
	Endpoints *EndpointResolver
	Tree      Tree
	Attacher  Attacher
	Metrics   *Metrics
	Log       *slog.Logger
}

// Reconcile runs one convergence cycle.
func (a *Agent) Reconcile(ctx context.Context) error {
	a.Metrics.ReconcileTotal.Inc()
	if err := a.reconcile(ctx); err != nil {
		a.Metrics.ReconcileErrors.Inc()
		return err
	}
	return nil
}

func (a *Agent) reconcile(ctx context.Context) error {
	nodeMbps, err := a.nodeBudget(ctx)
	if err != nil {
		return err
	}
	pods, skipped, err := a.shapedPods(ctx)
	if err != nil {
		return err
	}

	if nodeMbps <= 0 {
		// No advertised budget and no fallback: never build a tree with a
		// made-up cap. Everything stays on the unshaped Cilium-only path
		// (the NIC annotation still paces the wire leg) and the
		// skipped-pod gauge carries the signal.
		a.Metrics.NodeBudgetMbps.Set(0)
		a.Metrics.AttachedPods.Set(0)
		a.Metrics.SkippedPods.Set(float64(len(pods) + skipped))
		if len(pods) > 0 {
			a.Log.Warn("node advertises no egress budget; pods stay unshaped",
				"pods", len(pods))
		}
		return a.Attacher.CleanupStale(map[string]bool{})
	}
	a.Metrics.NodeBudgetMbps.Set(float64(nodeMbps))

	classes, attachments := Desired(pods)

	if err := a.Tree.EnsureDevices(ctx); err != nil {
		return err
	}
	if err := a.Tree.EnsureTree(ctx, nodeMbps, classes); err != nil {
		return err
	}
	// Hard ordering: no pod program without a confirmed return path.
	if err := a.Attacher.EnsureReturn(a.Tree.ReturnDev); err != nil {
		a.Metrics.AttachedPods.Set(0)
		return fmt.Errorf("return program not attachable, leaving pods unshaped: %w", err)
	}

	interfaces, err := a.Endpoints.Interfaces(ctx)
	if err != nil {
		return err
	}
	trampoline, err := net.InterfaceByName(a.Tree.TrampolineDev)
	if err != nil {
		return err
	}

	attached := 0
	active := map[string]bool{}
	deviceOf := map[string]string{}
	for _, attachment := range attachments {
		device, ok := interfaces[attachment.Namespace+"/"+attachment.Name]
		if !ok {
			skipped++
			a.Log.Warn("no cilium endpoint for pod; leaving it unshaped",
				"pod", attachment.Namespace+"/"+attachment.Name)
			continue
		}
		reattached, err := a.Attacher.EnsurePod(device, trampoline.Index, attachment)
		if err != nil {
			skipped++
			a.Log.Error("attaching pod device failed",
				"pod", attachment.Namespace+"/"+attachment.Name, "device", device, "error", err)
			continue
		}
		if reattached {
			a.Metrics.LinkReattaches.Inc()
		}
		active[device] = true
		deviceOf[attachment.Namespace+"/"+attachment.Name] = device
		attached++
	}
	a.Metrics.AttachedPods.Set(float64(attached))
	a.Metrics.SkippedPods.Set(float64(skipped))

	if err := a.Attacher.CleanupStale(active); err != nil {
		a.Log.Error("cleaning stale pins failed", "error", err)
	}

	a.exportStats(ctx, attachments, deviceOf)
	return nil
}

func (a *Agent) exportStats(ctx context.Context, attachments []PodAttachment, deviceOf map[string]string) {
	stats, direct, err := a.Tree.Stats(ctx)
	if err != nil {
		a.Log.Error("reading tree stats failed", "error", err)
	} else {
		a.Metrics.ClassSentBytes.Reset()
		a.Metrics.ClassDrops.Reset()
		a.Metrics.ClassBacklogBytes.Reset()
		for _, class := range stats {
			id := ClassIDString(class.Minor)
			a.Metrics.ClassSentBytes.WithLabelValues(id).Set(float64(class.SentBytes))
			a.Metrics.ClassDrops.WithLabelValues(id).Set(float64(class.Drops))
			a.Metrics.ClassBacklogBytes.WithLabelValues(id).Set(float64(class.BacklogBytes))
		}
		a.Metrics.DirectPackets.Set(float64(direct))
	}

	a.Metrics.PodRedirected.Reset()
	a.Metrics.PodGuardPass.Reset()
	a.Metrics.PodSiblingBypass.Reset()
	for _, attachment := range attachments {
		device, ok := deviceOf[attachment.Namespace+"/"+attachment.Name]
		if !ok {
			continue
		}
		counters, err := a.Attacher.PodCounters(device)
		if err != nil {
			continue
		}
		a.Metrics.PodRedirected.WithLabelValues(attachment.Namespace, attachment.Name).Set(float64(counters[counterRedirected]))
		a.Metrics.PodGuardPass.WithLabelValues(attachment.Namespace, attachment.Name).Set(float64(counters[counterGuardPass]))
		a.Metrics.PodSiblingBypass.WithLabelValues(attachment.Namespace, attachment.Name).Set(float64(counters[counterSiblingBypass]))
	}
	if counters, err := a.Attacher.ReturnCounters(); err == nil {
		a.Metrics.Returned.Set(float64(counters[counterReturned]))
		a.Metrics.ReturnDropped.Set(float64(counters[counterReturnDropped]))
	}
}

func (a *Agent) nodeBudget(ctx context.Context) (int64, error) {
	node, err := a.Client.CoreV1().Nodes().Get(ctx, a.NodeName, metav1.GetOptions{})
	if err != nil {
		return 0, fmt.Errorf("getting node %s: %w", a.NodeName, err)
	}
	if quantity, ok := node.Status.Capacity[corev1.ResourceName(NodeEgressResource)]; ok && !quantity.IsZero() {
		return quantity.Value(), nil
	}
	return a.DefaultNodeMbps, nil
}

// shapedPods lists this node's pods carrying the egress-class annotation,
// with the annotation parsed. Pods whose annotation does not parse are
// counted, not attached.
func (a *Agent) shapedPods(ctx context.Context) ([]PodShape, int, error) {
	list, err := a.Client.CoreV1().Pods(metav1.NamespaceAll).List(ctx, metav1.ListOptions{
		FieldSelector: "spec.nodeName=" + a.NodeName,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("listing pods on %s: %w", a.NodeName, err)
	}
	var pods []PodShape
	skipped := 0
	for _, pod := range list.Items {
		value, ok := pod.Annotations[EgressClassAnnotation]
		if !ok {
			continue
		}
		if pod.Spec.HostNetwork || pod.Status.PodIP == "" || pod.Status.Phase != corev1.PodRunning {
			continue
		}
		minor, floor, burst, err := ParseEgressClass(value)
		if err != nil {
			skipped++
			a.Log.Error("malformed egress-class annotation; pod stays unshaped",
				"pod", pod.Namespace+"/"+pod.Name, "error", err)
			continue
		}
		pods = append(pods, PodShape{
			Namespace: pod.Namespace,
			Name:      pod.Name,
			IP:        pod.Status.PodIP,
			Minor:     minor,
			FloorMbps: floor,
			BurstMbps: burst,
		})
	}
	return pods, skipped, nil
}
