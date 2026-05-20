// Package controllers contains the two reconcile loops this
// operator runs:
//
//   - InventorySyncer (this file). A periodic poller that calls
//     Robot's `/server` endpoint, filters by name prefix, and
//     keeps the set of `HetznerBareMetalHost` CRs in sync with
//     what Robot reports. Creates CRs for newly-ordered servers,
//     deletes CRs for cancelled / renamed servers.
//
//   - WWNFillReconciler (wwnfill.go). Event-driven. Watches
//     `HetznerBareMetalHost` CRs and patches their
//     `rootDeviceHints` once caph populates `hardwareDetails`.
//
// Robot has no webhook surface, so inventory sync is timer-driven.
// The poll interval is generous (60s default) because hardware
// procurement is human-paced — there's no point reacting in
// milliseconds.
package controllers

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/hetzner-robot-controller/internal/robot"
)

// HetznerBareMetalHost GVK. caph defines the type; we operate on
// it via unstructured so we don't need to vendor caph's API
// package (its module graph is heavy and we only touch four
// fields).
var hetznerBareMetalHostGVK = schema.GroupVersionKind{
	Group:   "infrastructure.cluster.x-k8s.io",
	Version: "v1beta1",
	Kind:    "HetznerBareMetalHost",
}

// Labels we stamp on every controller-managed CR. Used by deletion
// to scope the "what's mine" query, and by the operator to grep
// for which hosts were registered by this controller vs added
// manually (so we don't accidentally delete hand-managed CRs).
const (
	// ManagedByLabel mirrors the standard Kubernetes convention
	// (`app.kubernetes.io/managed-by`).
	ManagedByLabel = "app.kubernetes.io/managed-by"
	// ManagedByValue identifies CRs this controller owns. Stable
	// across releases so existing CRs keep matching.
	ManagedByValue = "hetzner-robot-controller"

	// ServerNumberLabel surfaces the Robot server ID as a label so
	// it's queryable with `kubectl get -l` (the field is also on
	// `spec.serverID`, but labels are friendlier for ad-hoc
	// inspection).
	ServerNumberLabel = "robot.hetzner.com/server-number"

	// ServerNameLabel surfaces the Robot panel name. Used by
	// `HetznerBareMetalMachineTemplate.spec.template.spec.hostSelector`
	// in some setups (e.g. selecting all `tuist-bm-staging-*`).
	ServerNameLabel = "robot.hetzner.com/server-name"

	// ClusterLabel records which CAPI cluster the host belongs to,
	// derived from the Robot server name. Each env's HBMM
	// `hostSelector.matchLabels` filters on this so a single shared
	// Robot account stays partitioned across staging / canary /
	// production. The controller stamps it on creation and back-
	// fills it on existing CRs whose label is missing.
	ClusterLabel = "tuist.dev/cluster"
)

// InventorySyncer is a controller-runtime Runnable that
// reconciles Robot's server list into HetznerBareMetalHost CRs.
//
// Single-leader-only: relies on the manager's leader election to
// avoid duplicate Robot API calls when the controller is HA. The
// manager doesn't run this until election succeeds.
type InventorySyncer struct {
	// Client is the mgmt-cluster k8s client.
	Client client.Client

	// Robot lists Robot servers.
	Robot robot.Client

	// Namespace is where HetznerBareMetalHost CRs live (typically
	// `org-tuist`).
	Namespace string

	// NamePrefix selects which Robot servers this controller
	// owns. Default `tuist-bm-`. Servers whose name doesn't start
	// with this are ignored — both for creation (we won't make a
	// CR) and for deletion (we won't touch their CRs).
	NamePrefix string

	// Clusters partitions a shared Robot account across CAPI
	// clusters. A Robot server is included in inventory only if
	// its name matches `tuist-bm-{cluster}-...` (operator-named)
	// or `tuist-{cluster}-...` (caph-renamed during provisioning),
	// where `{cluster}` is one of these values. The matched value
	// is stamped on the HBM as `tuist.dev/cluster=<cluster>` so
	// each env's HBMM `hostSelector` can scope itself.
	//
	// Empty list = legacy single-env mode: no gating, no cluster
	// label stamped. Production should always set this.
	Clusters []string

	// PollInterval between Robot list calls. Default 60s.
	PollInterval time.Duration
}

// NeedLeaderElection makes the manager only run this on the
// elected leader. Without it, every replica would poll Robot in
// parallel and race on CR creation.
func (s *InventorySyncer) NeedLeaderElection() bool { return true }

// Start blocks until ctx is cancelled, syncing on each tick.
// Errors during a single tick are logged and the next tick still
// fires — Robot API hiccups shouldn't permanently break the
// controller.
func (s *InventorySyncer) Start(ctx context.Context) error {
	if s.PollInterval <= 0 {
		s.PollInterval = 60 * time.Second
	}
	if s.NamePrefix == "" {
		s.NamePrefix = "tuist-bm-"
	}
	logger := log.FromContext(ctx).WithName("inventory-syncer")
	logger.Info("starting", "namespace", s.Namespace, "prefix", s.NamePrefix, "interval", s.PollInterval)

	// First tick immediately so a freshly-deployed controller
	// doesn't wait a full interval before populating CRs.
	if err := s.sync(ctx); err != nil {
		logger.Error(err, "initial sync failed; will retry on next tick")
	}

	t := time.NewTicker(s.PollInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			if err := s.sync(ctx); err != nil {
				logger.Error(err, "sync failed; will retry on next tick")
			}
		}
	}
}

// sync does one full pass: list Robot servers, compare against
// existing CRs, create/delete as needed. Idempotent — running it
// twice in a row is a no-op when the state matches.
//
// Asymmetric selection (intentional):
//
//   - **Creation** filters by name prefix. Only servers freshly
//     named `tuist-bm-*` in the Robot panel get an initial CR.
//     This keeps the controller from claiming random servers in
//     the account.
//
//   - **Deletion** filters by serverID present in Robot at all
//     (regardless of name). caph rewrites `server_name` to the
//     `HetznerBareMetalMachine` name as part of its provisioning
//     flow, which would otherwise drop our prefix-match and cause
//     the controller to reap a perfectly healthy CR every time a
//     host gets provisioned. Once we've created a CR, we keep it
//     as long as the underlying physical server still exists in
//     the account.
func (s *InventorySyncer) sync(ctx context.Context) error {
	logger := log.FromContext(ctx)

	servers, err := s.Robot.ListServers(ctx)
	if err != nil {
		return fmt.Errorf("list robot servers: %w", err)
	}

	// `eligibleForCreation` — name prefix matches AND not cancelled.
	// `liveServerNumbers` — every non-cancelled server in the account,
	// regardless of name. Used for the deletion gate so caph's rename
	// doesn't cause us to reap a live host.
	// `clusterByName` — the cluster derived from the server name (if
	// any). Cached here so we can stamp it on creation AND back-fill
	// it on existing CRs without re-parsing inside two separate loops.
	eligibleForCreation := map[string]robot.Server{} // CR name → server
	clusterByName := map[string]string{}             // CR name → cluster (may be "")
	liveServerNumbers := map[int]struct{}{}
	for _, srv := range servers {
		if srv.Cancelled {
			continue
		}
		liveServerNumbers[srv.Number] = struct{}{}
		if !strings.HasPrefix(srv.Name, s.NamePrefix) {
			continue
		}
		cluster := clusterFromServerName(srv.Name, s.Clusters)
		// Cluster gating: when `--clusters` is configured, only
		// servers whose name parses to one of them get a CR. This
		// is what keeps a shared Robot account from cross-claiming
		// across envs after `NamePrefix` got widened past
		// `tuist-bm-` to accommodate caph's mid-provisioning name
		// rewrite (e.g. `tuist-staging-runners-linux-…`).
		if len(s.Clusters) > 0 && cluster == "" {
			continue
		}
		name := crNameForServer(srv.Number)
		eligibleForCreation[name] = srv
		clusterByName[name] = cluster
	}

	// Current state from the cluster: every HBMH we own (matched
	// by ManagedByLabel). We deliberately don't look at CRs we
	// don't own, so a human-added HBMH won't be reaped.
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(hetznerBareMetalHostGVK)
	if err := s.Client.List(ctx, list,
		client.InNamespace(s.Namespace),
		client.MatchingLabels{ManagedByLabel: ManagedByValue},
	); err != nil {
		return fmt.Errorf("list HetznerBareMetalHosts: %w", err)
	}

	owned := map[string]*unstructured.Unstructured{}
	for i := range list.Items {
		owned[list.Items[i].GetName()] = &list.Items[i]
	}

	createdCount := 0
	for name, srv := range eligibleForCreation {
		if _, exists := owned[name]; exists {
			continue
		}
		if err := s.createHost(ctx, name, srv, clusterByName[name]); err != nil {
			// Don't bail the whole pass on one create failure;
			// log and continue so other servers still progress.
			logger.Error(err, "create HetznerBareMetalHost", "name", name, "server", srv.Number)
			continue
		}
		logger.Info("created HetznerBareMetalHost", "name", name, "server", srv.Number,
			"robotName", srv.Name, "cluster", clusterByName[name])
		createdCount++
	}

	// Back-fill `tuist.dev/cluster` on CRs that pre-date this
	// label (the controller used to stamp only managed-by +
	// server-number + server-name). Without this, existing HBMs
	// would never gain the label and caph hostSelector wouldn't
	// claim them after an env adopts the per-cluster gate.
	backfilledCount := 0
	if len(s.Clusters) > 0 {
		for name, obj := range owned {
			if obj.GetLabels()[ClusterLabel] != "" {
				continue
			}
			robotName := obj.GetLabels()[ServerNameLabel]
			cluster := clusterFromServerName(robotName, s.Clusters)
			if cluster == "" {
				continue
			}
			labels := obj.GetLabels()
			if labels == nil {
				labels = map[string]string{}
			}
			labels[ClusterLabel] = cluster
			obj.SetLabels(labels)
			if err := s.Client.Update(ctx, obj); err != nil {
				logger.Error(err, "back-fill cluster label", "name", name, "cluster", cluster)
				continue
			}
			logger.Info("back-filled cluster label", "name", name, "cluster", cluster)
			backfilledCount++
		}
	}

	deletedCount := 0
	for name, obj := range owned {
		// A CR is stale only if its underlying Robot server has
		// vanished from the inventory (cancelled / removed). caph
		// rewriting `server_name` doesn't count — the physical
		// box is still there.
		serverNumber, ok := serverNumberFromCR(obj)
		if !ok {
			logger.Info("skipping delete; CR has no robot server-number label", "name", name)
			continue
		}
		if _, stillInRobot := liveServerNumbers[serverNumber]; stillInRobot {
			continue
		}
		// Cascade safety: refuse to delete a CR that caph has
		// already bound to a HetznerBareMetalMachine. If we drop
		// the CR while it's claimed, caph's reconcile loops error
		// out on a now-missing object reference. The operator's
		// path is: drain the MD (replicas → 0), wait for the
		// HetznerBareMetalMachine to release, then we can
		// reap the orphan CR.
		consumer, hasConsumer, _ := unstructured.NestedString(obj.Object, "spec", "consumerRef", "name")
		if hasConsumer && consumer != "" {
			logger.Info("skipping delete; HetznerBareMetalHost is still claimed",
				"name", name, "consumer", consumer)
			continue
		}
		if err := s.Client.Delete(ctx, obj); err != nil && !apierrors.IsNotFound(err) {
			logger.Error(err, "delete HetznerBareMetalHost", "name", name)
			continue
		}
		logger.Info("deleted HetznerBareMetalHost (server no longer in Robot inventory)",
			"name", name, "server", serverNumber)
		deletedCount++
	}

	logger.V(1).Info("sync complete",
		"robotServers", len(servers), "eligibleForCreation", len(eligibleForCreation),
		"created", createdCount, "deleted", deletedCount,
		"backfilledClusterLabel", backfilledCount, "owned", len(owned))
	return nil
}

// clusterFromServerName returns which of the configured clusters
// a Robot server name belongs to, or "" if none match. Accepts
// both shapes the controller sees in practice:
//
//   - `tuist-bm-<cluster>-<n>` — the operator's name in the
//     Robot panel.
//   - `tuist-<cluster>-...` — caph rewrites the server name to
//     the HetznerBareMetalMachine name during provisioning, which
//     CAPI templates as `<clusterName>-<deploymentName>-…`. The
//     cluster name is the first segment after `tuist-`.
//
// Cluster names are matched as literal prefixes (with a trailing
// `-` to avoid `production` accidentally matching `prod`).
// Longest match wins so `production-us-east` takes precedence
// over `production`.
func clusterFromServerName(name string, clusters []string) string {
	// Try `tuist-bm-<cluster>-` first (operator-named original).
	// Then `tuist-<cluster>-` (caph-renamed). Take the longest
	// matching cluster so multi-segment names like
	// `production-us-east` aren't shadowed by `production`.
	best := ""
	for _, c := range clusters {
		if c == "" {
			continue
		}
		for _, prefix := range []string{"tuist-bm-" + c + "-", "tuist-" + c + "-"} {
			if strings.HasPrefix(name, prefix) && len(c) > len(best) {
				best = c
			}
		}
	}
	return best
}

// serverNumberFromCR reads the Robot server number from the
// label the controller stamps on creation. Returns ok=false if
// the label is missing or unparseable — the caller treats that
// as "leave the CR alone" since we can't safely diff it against
// Robot inventory.
func serverNumberFromCR(obj *unstructured.Unstructured) (int, bool) {
	raw := obj.GetLabels()[ServerNumberLabel]
	if raw == "" {
		return 0, false
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return 0, false
	}
	return n, true
}

// createHost emits a minimal HetznerBareMetalHost CR. WWNs stay
// empty — caph fills `status.hardwareDetails` on first rescue
// boot, then WWNFillReconciler patches them into
// `spec.rootDeviceHints`. We can't pre-populate WWNs here without
// SSHing into rescue ourselves, which doubles the surface area
// for no real win.
func (s *InventorySyncer) createHost(ctx context.Context, name string, srv robot.Server, cluster string) error {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)
	obj.SetName(name)
	obj.SetNamespace(s.Namespace)
	labels := map[string]string{
		ManagedByLabel:    ManagedByValue,
		ServerNumberLabel: fmt.Sprintf("%d", srv.Number),
		ServerNameLabel:   srv.Name,
	}
	if cluster != "" {
		labels[ClusterLabel] = cluster
	}
	obj.SetLabels(labels)
	obj.SetAnnotations(map[string]string{
		// Surface the Robot product / DC for ad-hoc inspection.
		// caph itself also populates `hardwareDetails`, but this
		// is what Robot reports vs what the box actually self-
		// describes after rescue boot. Useful when the two
		// diverge (e.g. RAM upgrade Hetzner billed but didn't
		// install).
		"robot.hetzner.com/product": srv.Product,
		"robot.hetzner.com/dc":      srv.Dc,
	})
	if err := unstructured.SetNestedField(obj.Object, int64(srv.Number), "spec", "serverID"); err != nil {
		return fmt.Errorf("set spec.serverID: %w", err)
	}
	// Maintenance mode false — caph is allowed to drive this box.
	if err := unstructured.SetNestedField(obj.Object, false, "spec", "maintenanceMode"); err != nil {
		return fmt.Errorf("set spec.maintenanceMode: %w", err)
	}
	if err := s.Client.Create(ctx, obj); err != nil {
		if apierrors.IsAlreadyExists(err) {
			// Race with another reconciler / human: treat as
			// success. Next sync will reconcile any field drift.
			return nil
		}
		return err
	}
	return nil
}

// crNameForServer is the deterministic naming function. Pulled
// out so tests can call it without re-deriving the formula.
// Convention `bm-<server-id>` — short, unambiguous, matches
// what an operator would write by hand.
func crNameForServer(serverID int) string {
	return fmt.Sprintf("bm-%d", serverID)
}

// We never block the wait condition; metav1 import is only here
// because UnstructuredList embeds an ObjectMeta reference. Keep
// the import explicit so removing the field elsewhere doesn't
// silently drop transitive coverage.
var _ = metav1.ObjectMeta{}
