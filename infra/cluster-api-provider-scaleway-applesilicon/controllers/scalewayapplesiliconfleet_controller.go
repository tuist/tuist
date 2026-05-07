package controllers

import (
	"context"
	"fmt"
	"sort"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
)

// ScalewayAppleSiliconFleetReconciler reconciles
// ScalewayAppleSiliconFleet CRs into a population of Machine CRs
// matching the fleet's desired replicas + machine template.
//
// Why this layer exists: the chart manages the fleet (one CR per
// logical pool — xcresult-processor, customer runners) and the
// operator owns Machine instance lifecycle. helm freely patches the
// fleet's spec on every upgrade; the operator handles individual
// Machine create/delete (including the awkward "rollback while
// operator is being rolled" case via finalizers + owner references).
// SKU/zone changes in helm values flow naturally to non-Ready
// Machines via the recycle path below.
//
// Adoption: Machines pre-existing the introduction of this CRD (e.g.
// the staging xcresult Mac mini that the chart was rendering directly
// before this refactor) are picked up by label selector and
// retroactively bound to a Fleet via OwnerReference. No manual
// migration needed beyond stripping helm tracking annotations from
// the existing Machine objects so helm doesn't fight the operator
// over ownership.
type ScalewayAppleSiliconFleetReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder
}

// FleetLabel is the Node + Machine + Fleet label our chart stamps
// onto every Machine it (or this controller) creates. The Fleet
// reconciler uses it to discover Machines belonging to a fleet and
// adopt orphans that match.
const FleetLabel = "tuist.dev/fleet"

// FleetFinalizer keeps the Fleet CR around until owned Machines have
// been deleted. Without it, deleting a Fleet would orphan its
// Machines (kubernetes garbage-collection runs cascade-deletion
// asynchronously and the Fleet CR could vanish before all owned
// Machines are gone, leaving the operator unable to track which
// Machines were "in flight" for what fleet during the cleanup).
const FleetFinalizer = "scalewayapplesilicon.cluster.x-k8s.io/fleet-finalizer"

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconfleets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconfleets/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconfleets/finalizers,verbs=update

func (r *ScalewayAppleSiliconFleetReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("fleet", req.NamespacedName)

	fleet := &infrav1.ScalewayAppleSiliconFleet{}
	if err := r.Get(ctx, req.NamespacedName, fleet); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	machines, err := r.listMachinesForFleet(ctx, fleet)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("list machines: %w", err)
	}

	// Adopt orphan Machines (label-matched but no OwnerReference to
	// us) before any other reconciliation so the rest of the
	// reconcile loop sees them as fleet-owned.
	if err := r.adoptOrphans(ctx, fleet, machines); err != nil {
		return ctrl.Result{}, fmt.Errorf("adopt orphans: %w", err)
	}

	// Deletion path: cascade the delete to owned Machines, then
	// drop our finalizer so kubernetes GC can complete.
	if !fleet.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, fleet, machines)
	}

	if !controllerutil.ContainsFinalizer(fleet, FleetFinalizer) {
		controllerutil.AddFinalizer(fleet, FleetFinalizer)
		if err := r.Update(ctx, fleet); err != nil {
			return ctrl.Result{}, fmt.Errorf("add finalizer: %w", err)
		}
		return ctrl.Result{Requeue: true}, nil
	}

	desired := int(fleet.Spec.Replicas)

	// Recycle non-Ready Machines whose spec doesn't match the
	// fleet's template. Ready Machines (with a Scaleway server
	// allocated) are explicitly NOT touched — disrupting a running
	// host on a values-only change would burn customer build time.
	//
	// "Non-Ready" means: ServerID is empty (so no Scaleway
	// resource is allocated) AND we're not already mid-deletion.
	// This catches the canonical "Scaleway out of stock, flip the
	// SKU in values" case: failing-Provisioning Machines get
	// auto-deleted; the next reconcile creates fresh ones with the
	// new template.
	recycled := 0
	for _, m := range machines {
		if !m.DeletionTimestamp.IsZero() {
			continue
		}
		if m.Status.ServerID != "" {
			continue
		}
		if specMatchesTemplate(&m.Spec, &fleet.Spec.MachineTemplate) {
			continue
		}
		logger.Info("recycling non-Ready Machine to match fleet template", "machine", m.Name)
		if err := r.Delete(ctx, &m); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("recycle delete %s: %w", m.Name, err)
		}
		recycled++
	}
	if recycled > 0 {
		// Re-list on the next tick to see the deletions land.
		return ctrl.Result{RequeueAfter: 5 * time.Second}, nil
	}

	// Filter to live Machines (not in deletion) for count math.
	live := make([]infrav1.ScalewayAppleSiliconMachine, 0, len(machines))
	for _, m := range machines {
		if m.DeletionTimestamp.IsZero() {
			live = append(live, m)
		}
	}

	switch {
	case len(live) < desired:
		if err := r.scaleUp(ctx, fleet, live, desired); err != nil {
			return ctrl.Result{}, err
		}
	case len(live) > desired:
		if err := r.scaleDown(ctx, fleet, live, desired); err != nil {
			return ctrl.Result{}, err
		}
	}

	// Status update — best-effort patch, logged but not gated.
	if err := r.updateStatus(ctx, fleet, machines); err != nil {
		logger.Error(err, "patch fleet status; continuing")
	}

	return ctrl.Result{}, nil
}

func (r *ScalewayAppleSiliconFleetReconciler) listMachinesForFleet(ctx context.Context, fleet *infrav1.ScalewayAppleSiliconFleet) ([]infrav1.ScalewayAppleSiliconMachine, error) {
	var list infrav1.ScalewayAppleSiliconMachineList
	if err := r.List(ctx, &list,
		client.InNamespace(fleet.Namespace),
		client.MatchingLabels{FleetLabel: fleet.Name},
	); err != nil {
		return nil, err
	}
	return list.Items, nil
}

func (r *ScalewayAppleSiliconFleetReconciler) adoptOrphans(ctx context.Context, fleet *infrav1.ScalewayAppleSiliconFleet, machines []infrav1.ScalewayAppleSiliconMachine) error {
	for i := range machines {
		m := &machines[i]
		if metav1.IsControlledBy(m, fleet) {
			continue
		}
		// Don't take ownership of a Machine that's already
		// controlled by some other resource — it might be
		// owned by a pre-existing chart-managed lineage we
		// haven't fully migrated. Adopting only true orphans
		// avoids tug-of-wars.
		owner := metav1.GetControllerOf(m)
		if owner != nil {
			continue
		}

		if err := controllerutil.SetControllerReference(fleet, m, r.Scheme); err != nil {
			return fmt.Errorf("set owner ref on %s: %w", m.Name, err)
		}
		if err := r.Update(ctx, m); err != nil {
			return fmt.Errorf("adopt %s: %w", m.Name, err)
		}
		log.FromContext(ctx).Info("adopted orphan Machine", "machine", m.Name, "fleet", fleet.Name)
	}
	return nil
}

func (r *ScalewayAppleSiliconFleetReconciler) scaleUp(ctx context.Context, fleet *infrav1.ScalewayAppleSiliconFleet, live []infrav1.ScalewayAppleSiliconMachine, desired int) error {
	taken := make(map[int]bool, len(live))
	for _, m := range live {
		if idx, ok := indexFromName(fleet.Name, m.Name); ok {
			taken[idx] = true
		}
	}

	gap := desired - len(live)
	for created := 0; created < gap; {
		for idx := 0; ; idx++ {
			if taken[idx] {
				continue
			}
			name := fmt.Sprintf("%s-%d", fleet.Name, idx)
			m := &infrav1.ScalewayAppleSiliconMachine{
				ObjectMeta: metav1.ObjectMeta{
					Name:      name,
					Namespace: fleet.Namespace,
					Labels: map[string]string{
						FleetLabel: fleet.Name,
					},
				},
				Spec: *fleet.Spec.MachineTemplate.DeepCopy(),
			}
			// FleetName on the Machine spec drives per-fleet SSH
			// keys and the tart-kubelet `--fleet` flag. It must
			// match the Fleet CR's name regardless of what the
			// template says — the chart can leave the field
			// blank and the operator fills it in.
			m.Spec.FleetName = fleet.Name
			if err := controllerutil.SetControllerReference(fleet, m, r.Scheme); err != nil {
				return fmt.Errorf("set owner on new machine: %w", err)
			}
			if err := r.Create(ctx, m); err != nil {
				if apierrors.IsAlreadyExists(err) {
					// Lost a race; pretend we created and let
					// the next reconcile pick it up.
					taken[idx] = true
					break
				}
				return fmt.Errorf("create machine %s: %w", name, err)
			}
			r.Recorder.Eventf(fleet, "Normal", "ScaledUp",
				"Created Machine %s/%s", fleet.Namespace, name)
			taken[idx] = true
			created++
			break
		}
	}
	return nil
}

func (r *ScalewayAppleSiliconFleetReconciler) scaleDown(ctx context.Context, fleet *infrav1.ScalewayAppleSiliconFleet, live []infrav1.ScalewayAppleSiliconMachine, desired int) error {
	// Delete highest-indexed Machines first so naming stays dense
	// — `<fleet>-0`, `-1`, `-2` instead of holes at -1.
	sort.SliceStable(live, func(i, j int) bool {
		ii, _ := indexFromName(fleet.Name, live[i].Name)
		ij, _ := indexFromName(fleet.Name, live[j].Name)
		return ii > ij
	})

	excess := len(live) - desired
	for i := 0; i < excess; i++ {
		m := &live[i]
		if err := r.Delete(ctx, m); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete machine %s: %w", m.Name, err)
		}
		r.Recorder.Eventf(fleet, "Normal", "ScaledDown",
			"Deleted Machine %s/%s", fleet.Namespace, m.Name)
	}
	return nil
}

func (r *ScalewayAppleSiliconFleetReconciler) reconcileDelete(ctx context.Context, fleet *infrav1.ScalewayAppleSiliconFleet, machines []infrav1.ScalewayAppleSiliconMachine) (ctrl.Result, error) {
	if len(machines) > 0 {
		// Owned Machines exist; cascade-delete via
		// kubernetes garbage collection (the OwnerReference
		// blockOwnerDeletion=true that SetControllerReference
		// stamps takes care of this). We do trigger explicit
		// deletes here too in case the GC controller is slow
		// or the owner ref was somehow missed.
		for i := range machines {
			m := &machines[i]
			if !m.DeletionTimestamp.IsZero() {
				continue
			}
			if err := r.Delete(ctx, m); err != nil && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, fmt.Errorf("cascade-delete %s: %w", m.Name, err)
			}
		}
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	if controllerutil.RemoveFinalizer(fleet, FleetFinalizer) {
		if err := r.Update(ctx, fleet); err != nil {
			return ctrl.Result{}, fmt.Errorf("clear finalizer: %w", err)
		}
	}
	return ctrl.Result{}, nil
}

func (r *ScalewayAppleSiliconFleetReconciler) updateStatus(ctx context.Context, fleet *infrav1.ScalewayAppleSiliconFleet, machines []infrav1.ScalewayAppleSiliconMachine) error {
	var ready int32
	for _, m := range machines {
		if m.Status.Ready {
			ready++
		}
	}
	fleet.Status.Replicas = int32(len(machines))
	fleet.Status.ReadyReplicas = ready
	return r.Status().Update(ctx, fleet)
}

// specMatchesTemplate compares the spec fields the Fleet's template
// drives. Status / ProviderID are operator-set on the Machine and
// not part of the template comparison.
func specMatchesTemplate(spec, tmpl *infrav1.ScalewayAppleSiliconMachineSpec) bool {
	if spec.Type != tmpl.Type {
		return false
	}
	if spec.Zone != tmpl.Zone {
		return false
	}
	if spec.OS != tmpl.OS {
		return false
	}
	if spec.KubeletVersion != tmpl.KubeletVersion {
		return false
	}
	return true
}

// indexFromName parses the trailing index from a Machine name of
// shape `<fleet>-<int>`. Returns (-1, false) on mismatch — the
// caller treats those as opaque and won't reuse their slot.
func indexFromName(fleet, name string) (int, bool) {
	prefix := fleet + "-"
	if len(name) <= len(prefix) || name[:len(prefix)] != prefix {
		return -1, false
	}
	suffix := name[len(prefix):]
	idx := 0
	for _, c := range suffix {
		if c < '0' || c > '9' {
			return -1, false
		}
		idx = idx*10 + int(c-'0')
	}
	return idx, true
}

func (r *ScalewayAppleSiliconFleetReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayAppleSiliconFleet{}).
		Owns(&infrav1.ScalewayAppleSiliconMachine{}).
		// Watch un-owned Machines that match a Fleet's label
		// so the adoption path fires on day-zero migration
		// (existing chart-rendered Machines pre-CRD).
		Watches(
			&infrav1.ScalewayAppleSiliconMachine{},
			handler.EnqueueRequestsFromMapFunc(func(ctx context.Context, obj client.Object) []ctrl.Request {
				m, ok := obj.(*infrav1.ScalewayAppleSiliconMachine)
				if !ok {
					return nil
				}
				name, ok := m.Labels[FleetLabel]
				if !ok || name == "" {
					return nil
				}
				return []ctrl.Request{{NamespacedName: client.ObjectKey{
					Namespace: m.Namespace,
					Name:      name,
				}}}
			}),
		).
		Complete(r)
}
