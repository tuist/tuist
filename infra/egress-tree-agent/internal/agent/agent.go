package agent

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"maps"
	"net"
	"slices"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/labels"
	listersv1 "k8s.io/client-go/listers/core/v1"
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
	// BetaPodPrefix, when non-empty, restricts attachment to pods whose
	// name starts with the prefix (a beta-rollout gate: shape one account's
	// pods before the fleet). Excluded pods stay on the unshaped
	// Cilium-only path and are counted separately from skipped pods so the
	// exclusion never alerts. The desired tree and the sibling allowlists
	// are still computed over every annotated pod, so a matched pod keeps
	// its co-located sibling in the bypass even when that sibling is not
	// itself attached. Clearing or changing the prefix converges through
	// the normal reconcile: newly matched pods attach, no-longer-matched
	// pods detach via stale-pin cleanup within one cycle.
	BetaPodPrefix string
	// ReturnDetachAfter is the number of consecutive return-program attach
	// failures after which every pod program is detached. Attached pod
	// programs redirect into the trampoline, and without a return program
	// those packets drop at the peer — past this threshold, unshaped beats
	// blackholed.
	ReturnDetachAfter int

	// Pods and Nodes are informer-backed listers, field-selected to this
	// node by main. Reconcile reads only the local cache; the watch events
	// behind it are what kick a cycle.
	Pods      listersv1.PodLister
	Nodes     listersv1.NodeLister
	Endpoints *EndpointResolver
	Tree      Tree
	Attacher  Attacher
	Metrics   *Metrics
	Log       *slog.Logger

	// Converged desired state from previous cycles, kept only to log
	// added/updated/removed transitions at info level without logging the
	// idempotent replays. Empty after a restart, so the first cycle logs
	// the full converged state once.
	appliedBudget  int64
	appliedClasses map[uint16]TenantClass
	appliedPods    map[string]appliedPod

	// Consecutive EnsureReturn failures; reset on success.
	returnFailures int
}

// appliedPod is the logged-state fingerprint of one attached pod.
type appliedPod struct {
	Device   string
	Minor    uint16
	Siblings []string // sorted, as produced by Desired
}

// Reconcile runs one convergence cycle. requeue asks the caller for a quick
// retry, for the two conditions no watch event reports: a Running pod whose
// Cilium endpoint (the lxc* device) does not exist yet, and a return program
// that failed to attach.
func (a *Agent) Reconcile(ctx context.Context) (requeue bool, err error) {
	a.Metrics.ReconcileTotal.Inc()
	requeue, err = a.reconcile(ctx)
	if err != nil {
		a.Metrics.ReconcileErrors.Inc()
	}
	return requeue, err
}

func (a *Agent) reconcile(ctx context.Context) (bool, error) {
	if a.appliedPods == nil {
		a.appliedPods = map[string]appliedPod{}
	}
	nodeMbps, err := a.nodeBudget()
	if err != nil {
		return false, err
	}
	if nodeMbps != a.appliedBudget {
		a.Log.Info("node egress budget changed",
			"old_mbps", a.appliedBudget, "mbps", nodeMbps)
		a.appliedBudget = nodeMbps
	}
	pods, skipped := a.shapedPods()

	if nodeMbps <= 0 {
		// No advertised budget and no fallback: never build a tree with a
		// made-up cap. Everything stays on the unshaped Cilium-only path
		// (the NIC annotation still paces the wire leg) and the
		// skipped-pod gauge carries the signal.
		a.Metrics.NodeBudgetMbps.Set(0)
		a.Metrics.AttachedPods.Set(0)
		a.Metrics.BetaExcludedPods.Set(0)
		a.Metrics.SkippedPods.Set(float64(len(pods) + skipped))
		if len(pods) > 0 {
			a.Log.Warn("node advertises no egress budget; pods stay unshaped",
				"pods", len(pods))
		}
		for key, old := range a.appliedPods {
			a.Log.Info("removed pod shaping", "pod", key, "device", old.Device)
			delete(a.appliedPods, key)
		}
		return false, a.Attacher.CleanupStale(map[string]bool{})
	}
	a.Metrics.NodeBudgetMbps.Set(float64(nodeMbps))

	classes, attachments := Desired(pods)

	if err := a.Tree.EnsureDevices(ctx); err != nil {
		return false, err
	}
	if err := a.Tree.EnsureTree(ctx, nodeMbps, classes); err != nil {
		return false, err
	}
	a.logClassChanges(classes)
	// Hard ordering: no pod program without a confirmed return path.
	if err := a.Attacher.EnsureReturn(a.Tree.ReturnDev); err != nil {
		return a.handleReturnFailure(err)
	}
	a.returnFailures = 0

	interfaces, err := a.Endpoints.Interfaces(ctx)
	if err != nil {
		return false, err
	}
	trampoline, err := net.InterfaceByName(a.Tree.TrampolineDev)
	if err != nil {
		return false, err
	}

	requeue := false
	attached := 0
	betaExcluded := 0
	active := map[string]bool{}
	deviceOf := map[string]string{}
	for _, attachment := range attachments {
		if a.BetaPodPrefix != "" && !strings.HasPrefix(attachment.Name, a.BetaPodPrefix) {
			betaExcluded++
			continue
		}
		device, ok := interfaces[attachment.Namespace+"/"+attachment.Name]
		if !ok {
			skipped++
			requeue = true
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
		key := attachment.Namespace + "/" + attachment.Name
		a.logPodChange(key, device, attachment, reattached)
		active[device] = true
		deviceOf[key] = device
		attached++
	}
	a.Metrics.AttachedPods.Set(float64(attached))
	a.Metrics.SkippedPods.Set(float64(skipped))
	a.Metrics.BetaExcludedPods.Set(float64(betaExcluded))

	if err := a.Attacher.CleanupStale(active); err != nil {
		a.Log.Error("cleaning stale pins failed", "error", err)
	}
	for key, old := range a.appliedPods {
		if _, ok := deviceOf[key]; !ok {
			a.Log.Info("removed pod shaping", "pod", key, "device", old.Device)
			delete(a.appliedPods, key)
		}
	}

	a.exportStats(ctx, attachments, deviceOf)
	return requeue, nil
}

// handleReturnFailure escalates a failed return-program attach. While pod
// programs stay attached, their shaped packets drop at the trampoline peer
// (fail-close); after ReturnDetachAfter consecutive failures the pod
// programs are detached so pods run unshaped instead. Always requeues a fast
// retry.
func (a *Agent) handleReturnFailure(cause error) (bool, error) {
	a.returnFailures++
	a.Metrics.ReturnAttachFailures.Inc()
	a.Log.Error("return program attach failed; shaped pods drop at the trampoline peer until it attaches",
		"attempt", a.returnFailures, "detach_after", a.ReturnDetachAfter, "error", cause)
	if a.returnFailures < a.ReturnDetachAfter {
		return true, fmt.Errorf("return program not attachable: %w", cause)
	}
	a.Log.Warn("detaching all pod programs: the return program stayed unattachable; pods run unshaped",
		"failures", a.returnFailures)
	for key, old := range a.appliedPods {
		a.Log.Info("removed pod shaping", "pod", key, "device", old.Device)
		delete(a.appliedPods, key)
	}
	a.Metrics.AttachedPods.Set(0)
	if err := a.Attacher.CleanupStale(map[string]bool{}); err != nil {
		return true, fmt.Errorf("return program not attachable and pod detach failed: %w", errors.Join(cause, err))
	}
	return true, fmt.Errorf("return program not attachable, pod programs detached: %w", cause)
}

// logClassChanges logs tenant-class additions and parameter updates against
// the previously converged set. Removals are logged by EnsureTree at the
// point of the kernel deletion, which also covers foreign stale classes.
func (a *Agent) logClassChanges(classes map[uint16]TenantClass) {
	for minor, class := range classes {
		old, ok := a.appliedClasses[minor]
		switch {
		case !ok:
			a.Log.Info("added tenant class", "classid", ClassIDString(minor),
				"floor_mbps", class.FloorMbps, "burst_mbps", class.BurstMbps)
		case old != class:
			a.Log.Info("updated tenant class", "classid", ClassIDString(minor),
				"old_floor_mbps", old.FloorMbps, "old_burst_mbps", old.BurstMbps,
				"floor_mbps", class.FloorMbps, "burst_mbps", class.BurstMbps)
		}
	}
	a.appliedClasses = maps.Clone(classes)
}

// logPodChange logs one pod's attach or config transition and records the
// new fingerprint. A quiet cycle (attached, first, same config) logs nothing.
func (a *Agent) logPodChange(key, device string, attachment PodAttachment, reattached bool) {
	old, existed := a.appliedPods[key]
	current := appliedPod{Device: device, Minor: attachment.Minor, Siblings: attachment.SiblingIPs}
	switch {
	case reattached:
		a.Log.Info("attached pod program", "pod", key, "device", device,
			"classid", ClassIDString(attachment.Minor), "siblings", attachment.SiblingIPs)
	case !existed:
		// Restart with the pinned link intact: report the standing state
		// once rather than a fake update against an empty fingerprint.
		a.Log.Info("pod shaping in effect", "pod", key, "device", device,
			"classid", ClassIDString(attachment.Minor), "siblings", attachment.SiblingIPs)
	case old.Minor != current.Minor || !slices.Equal(old.Siblings, current.Siblings):
		added, removed := diffStrings(old.Siblings, current.Siblings)
		a.Log.Info("updated pod shaping", "pod", key, "device", device,
			"old_classid", ClassIDString(old.Minor), "classid", ClassIDString(attachment.Minor),
			"siblings_added", added, "siblings_removed", removed)
	default:
		return
	}
	a.appliedPods[key] = current
}

// diffStrings compares two sorted slices and returns the elements only in
// current and only in old.
func diffStrings(old, current []string) (added, removed []string) {
	for _, s := range current {
		if !slices.Contains(old, s) {
			added = append(added, s)
		}
	}
	for _, s := range old {
		if !slices.Contains(current, s) {
			removed = append(removed, s)
		}
	}
	return added, removed
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

func (a *Agent) nodeBudget() (int64, error) {
	node, err := a.Nodes.Get(a.NodeName)
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
// counted, not attached. The lister cache holds only this node's pods (the
// informer watch is field-selected), so no further node filtering happens
// here.
func (a *Agent) shapedPods() ([]PodShape, int) {
	list, err := a.Pods.List(labels.Everything())
	if err != nil {
		// The in-memory lister cannot fail on labels.Everything; keep the
		// branch honest anyway.
		a.Log.Error("listing pods from cache", "error", err)
		return nil, 0
	}
	var pods []PodShape
	skipped := 0
	for _, pod := range list {
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
	return pods, skipped
}
