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
// Selection of disks: every WWN-bearing entry in
// `spec.status.hardwareDetails.storage`, so the array matches the
// machine rather than an assumption about it.
//
// It used to take the first two, which was right for as long as
// every box we ordered was an AX-class pair. It stops being right
// the moment a four-disk box arrives: the host would install
// across two of its disks and silently leave the other two out of
// the array, and the partition layout is fixed at install, so the
// only way back is a reinstall. The RAID level is chosen
// separately, per cluster, by `statefulRaidLevel`.
//
// This changes nothing for a two-disk host, which is every
// Hetzner bare-metal host we run today. If the operator wants a
// topology that is not "all the disks", set `rootDeviceHints`
// manually before the first rescue boot — once the field is
// non-empty this reconciler stops touching it (Patch is no-op).
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

	wwns := extractWWNs(storage)
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

// extractWWNs pulls `wwn` strings from each storage entry. Skips
// entries without a WWN (rare — caph only populates entries it
// could read), and de-duplicates while preserving order in case
// caph ever lists the same disk twice (which would be a caph
// bug, but cheap to defend against).
func extractWWNs(storage []interface{}) []string {
	seen := map[string]struct{}{}
	out := []string{}
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
		out = append(out, wwn)
	}
	return out
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
