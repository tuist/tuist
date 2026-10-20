package controllers

import (
	"context"
	"fmt"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

// WWNFillReconciler watches HetznerBareMetalHost CRs and, when
// caph populates `spec.status.hardwareDetails.storage[].wwn` for
// at least two disks, patches `spec.rootDeviceHints.raid.wwn`
// with both WWNs so caph's subsequent `installimage` step can
// proceed.
//
// The unusual `spec.status` path is caph's API shape, not a typo
// here: `HetznerBareMetalHostSpec` embeds
// `Status ControllerGeneratedStatus json:"status"` with the
// comment "status is in the specs of the object, DO NOT EDIT" —
// so the discovered hardware details live under spec, even
// though they're controller-written.
//
// Why this is necessary: caph rejects empty `rootDeviceHints`
// with `Please specify one or the other` — so an
// operator/controller has to fill them. caph itself discovers
// WWNs in rescue mode and writes them to
// `spec.status.hardwareDetails`, but doesn't promote them back
// into the operator-facing `spec.rootDeviceHints` (intentionally
// — that field is operator intent). This reconciler does the
// promotion for CRs we own
// (`app.kubernetes.io/managed-by=hetzner-robot-controller`).
//
// Selection of disks: the same-size group in
// `spec.status.hardwareDetails.storage` holding the most capacity,
// so the array matches the machine rather than an assumption about
// it.
//
// It used to take the first two, which was right for as long as
// every box we ordered was an AX-class pair, and then every disk,
// which is right only when they match. installimage hands the set
// to mdadm, which sizes every member to the smallest, so a box
// with two 1.92 TB disks beside two 7.68 TB ones installs as if
// all four were 1.92: 3.84 TB usable out of 19.2 TB of flash. The
// partition layout is fixed at install, so the only way back is a
// reinstall.
//
// Capacity, not disk count, picks the group: four small disks can
// outnumber the pair the machine was bought for while holding
// less. A group too small to mirror is skipped, so a lone large
// disk loses to a smaller pair. The RAID level is chosen
// separately, per cluster, by `statefulRaidLevel`, and has to
// agree: a two-disk selection cannot install at level 10.
//
// This changes nothing for a host whose disks are all one size,
// which is every Hetzner bare-metal host we ran before the
// AX102-4. If the operator wants a topology that is not "the
// biggest matching set", set `rootDeviceHints` manually before the
// first rescue boot. Once the field is non-empty this reconciler
// stops touching it (Patch is no-op).
type WWNFillReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

func (r *WWNFillReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("host", req.NamespacedName)

	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)
	if err := r.Get(ctx, req.NamespacedName, obj); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, fmt.Errorf("get host: %w", err)
	}

	// Only act on CRs we own. The discovery syncer stamps the
	// managed-by label on its creates; manually-managed CRs are
	// off-limits because the operator might have specific
	// rootDeviceHints in mind.
	if obj.GetLabels()[ManagedByLabel] != ManagedByValue {
		return ctrl.Result{}, nil
	}

	// Skip if `rootDeviceHints` is already populated — either we
	// did it on a previous reconcile, or the operator set it by
	// hand. Either way we're done.
	if hintsPopulated(obj) {
		return ctrl.Result{}, nil
	}

	storage, found, err := unstructured.NestedSlice(obj.Object, "spec", "status", "hardwareDetails", "storage")
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("read hardwareDetails.storage: %w", err)
	}
	if !found || len(storage) == 0 {
		// caph hasn't registered yet. Requeue is unnecessary —
		// caph will update the CR which triggers another
		// reconcile via the watch.
		return ctrl.Result{}, nil
	}

	wwns := selectArrayWWNs(storage)
	if len(wwns) < 2 {
		// Need at least two disks for RAID 1. Single-disk hosts
		// would need a different reconcile path (set
		// `rootDeviceHints.wwn` directly). Out of scope for now
		// — every Hetzner AX-class box we order has paired
		// NVMes by SKU.
		logger.V(1).Info("waiting for at least 2 WWNs in hardwareDetails", "have", len(wwns))
		return ctrl.Result{}, nil
	}

	patch := client.MergeFrom(obj.DeepCopy())
	if err := unstructured.SetNestedStringSlice(obj.Object, wwns, "spec", "rootDeviceHints", "raid", "wwn"); err != nil {
		return ctrl.Result{}, fmt.Errorf("set rootDeviceHints.raid.wwn: %w", err)
	}
	if err := r.Patch(ctx, obj, patch); err != nil {
		if apierrors.IsConflict(err) {
			// Caph or another patcher mutated the object since
			// we read it. Retry on next reconcile.
			return ctrl.Result{Requeue: true}, nil
		}
		return ctrl.Result{}, fmt.Errorf("patch rootDeviceHints: %w", err)
	}
	logger.Info("filled rootDeviceHints.raid.wwn from hardwareDetails",
		"server", obj.GetLabels()[ServerNumberLabel], "wwns", wwns)
	return ctrl.Result{}, nil
}

// hintsPopulated returns true if the host's spec already has
// usable rootDeviceHints. Either `wwn` (single-disk) or
// `raid.wwn` (RAID) counts. Anything non-empty.
func hintsPopulated(obj *unstructured.Unstructured) bool {
	if v, ok, _ := unstructured.NestedString(obj.Object, "spec", "rootDeviceHints", "wwn"); ok && v != "" {
		return true
	}
	if v, ok, _ := unstructured.NestedStringSlice(obj.Object, "spec", "rootDeviceHints", "raid", "wwn"); ok && len(v) > 0 {
		return true
	}
	return false
}

// arrayDisk is one storage row reduced to what the array cares
// about: which disk it is, and how much it would contribute.
type arrayDisk struct {
	wwn  string
	size int64
}

// disksFromStorage parses caph's `hardwareDetails.storage` rows.
// Skips entries without a WWN (rare — caph only populates entries
// it could read), and de-duplicates while preserving scan order in
// case caph ever lists the same disk twice (which would be a caph
// bug, but cheap to defend against).
func disksFromStorage(storage []interface{}) []arrayDisk {
	seen := map[string]struct{}{}
	out := []arrayDisk{}
	for _, raw := range storage {
		m, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		wwn, ok := m["wwn"].(string)
		if !ok || wwn == "" {
			continue
		}
		if _, dup := seen[wwn]; dup {
			continue
		}
		seen[wwn] = struct{}{}
		out = append(out, arrayDisk{wwn: wwn, size: sizeBytes(m)})
	}
	return out
}

// sizeBytes reads a storage row's size. Unstructured decoding
// gives int64 from the API server and may give float64 from JSON,
// so both are accepted. A row without one reports 0, which groups
// every such row together and reproduces the old "span everything"
// behaviour for a host that reports no sizes at all.
func sizeBytes(entry map[string]interface{}) int64 {
	switch v := entry["sizeBytes"].(type) {
	case int64:
		return v
	case float64:
		return int64(v)
	}
	return 0
}

// extractWWNs is disksFromStorage reduced to the WWNs, in scan
// order.
func extractWWNs(storage []interface{}) []string {
	disks := disksFromStorage(storage)
	out := make([]string, 0, len(disks))
	for _, d := range disks {
		out = append(out, d.wwn)
	}
	return out
}

// selectArrayWWNs chooses which disks the root array should span:
// the same-size group that holds the most capacity.
//
// Spanning every disk is right only when they match. installimage
// hands the whole set to mdadm, which sizes every member to the
// smallest, so a box with two 1.92 TB disks beside two 7.68 TB
// ones installs as if all four were 1.92: 3.84 TB usable out of
// 19.2 TB of flash, and the layout is fixed at install.
//
// Capacity rather than disk count decides, because four small
// disks can outnumber the pair the machine was bought for while
// holding less. Groups too small to mirror are skipped, so a lone
// large disk loses to a smaller pair. If nothing can be mirrored
// (every disk a different size, or a single disk) the whole set is
// returned and the caller's own guard decides.
//
// The RAID level is chosen separately, per cluster, by
// `statefulRaidLevel`, and has to agree with what this returns: a
// two-disk selection cannot install at level 10.
func selectArrayWWNs(storage []interface{}) []string {
	disks := disksFromStorage(storage)

	type group struct {
		size  int64
		wwns  []string
		first int
	}
	bySize := map[int64]*group{}
	order := []int64{}
	for i, d := range disks {
		g, ok := bySize[d.size]
		if !ok {
			g = &group{size: d.size, first: i}
			bySize[d.size] = g
			order = append(order, d.size)
		}
		g.wwns = append(g.wwns, d.wwn)
	}

	var best *group
	for _, size := range order {
		g := bySize[size]
		if len(g.wwns) < 2 {
			continue
		}
		if best == nil || g.size*int64(len(g.wwns)) > best.size*int64(len(best.wwns)) {
			best = g
		}
	}
	if best == nil {
		return extractWWNs(storage)
	}
	return best.wwns
}

// SetupWithManager wires the reconciler. The watch is filtered to
// `app.kubernetes.io/managed-by=hetzner-robot-controller` so we
// don't get woken for every caph status update on every host
// in the namespace — only ours.
func (r *WWNFillReconciler) SetupWithManager(mgr ctrl.Manager) error {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)

	managedByFilter := predicate.NewPredicateFuncs(func(o client.Object) bool {
		return o.GetLabels()[ManagedByLabel] == ManagedByValue
	})

	return ctrl.NewControllerManagedBy(mgr).
		Named("wwnfill").
		For(obj, builder.WithPredicates(managedByFilter)).
		Complete(r)
}

// Compile-time guard: keep this type satisfying the Reconciler
// interface even after future refactors.
var _ = types.NamespacedName{}
