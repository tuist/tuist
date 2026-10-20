package macos

import (
	"context"
	"fmt"
	"slices"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// This file is the lending side of a rack host lent to another env
// (RackHost.spec.lendTo). The host stays this operator's: its Machine, power,
// OS updates and bootstrap from a reinstall. Its runner runtime becomes the
// borrower's, which the borrowing operator pushes and rolls with its own
// deploys (rackhostlease_controller.go).
//
// The two never push to the host at the same time. The host's runtime owner
// marker is the fence (bootstrap.RuntimeOwnerPath): every push checks it, and
// only this operator moves it, in the same step that authorizes or revokes the
// borrower's key. A lend runs Offered, Draining, Lent; a return runs
// Returning, Reclaimed. The state is recorded on the RackHost, so it survives
// the host's Machine.

// lendingGate is what the lend lets the rest of a reconcile do.
type lendingGate struct {
	// stop: the host is the borrower's or changing hands; push nothing.
	stop bool
	// skipDrift: keep the host as it is without pushing config. A host lent
	// by hand runs the borrower's runtime, which a push would pull back.
	skipDrift bool
	// forceReauth: the next bootstrap logs the host into the tailnet afresh,
	// taking it back from the borrower's tags.
	forceReauth bool
	result      ctrl.Result
}

const (
	lendingRequeue      = time.Minute
	lendingDrainRequeue = 30 * time.Second
)

func (r *RackAppleSiliconMachineReconciler) reconcileLending(ctx context.Context, oc *osUpdateContext) (lendingGate, error) {
	machine, host, sshKey, knownFingerprint := oc.machine, oc.host, oc.sshKey, oc.knownFingerprint
	want := host.Spec.LendTo
	rec := host.Status.Lease

	if machine.Spec.NodeCluster != nil {
		if want != "" {
			r.Recorder.Eventf(machine, corev1.EventTypeWarning, "LendToIgnored",
				"%s is lent by hand (nodeCluster); drop nodeCluster to lend it to %s", host.Name, want)
		}
		return lendingGate{}, nil
	}
	if want == "" && rec == nil {
		return r.reclaimOrphan(ctx, machine, host, sshKey, knownFingerprint)
	}
	if rec != nil && rec.State == infrav1.LendingReclaimed {
		return lendingGate{skipDrift: true, forceReauth: true}, nil
	}
	if rec != nil && (rec.Borrower != want || rec.State == infrav1.LendingReturning) {
		return r.returnLentHost(ctx, machine, host, sshKey, knownFingerprint)
	}
	if r.Env == "" || r.Borrowers == nil {
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "LendingUnavailable",
			"Not lending %s to %s: this operator has no --rack-env or no --rack-lease-borrower", host.Name, want)
		if rec != nil {
			return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
		}
		return lendingGate{skipDrift: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
	}

	borrower, namespace, err := r.Borrowers.Borrower(ctx, want)
	if err != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "BorrowerUnavailable",
			"Cannot reach %s to lend %s: %v", want, host.Name, err)
		if rec == nil || rec.State == infrav1.LendingOffered {
			return lendingGate{skipDrift: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
		}
		return r.holdLent(machine, rec), nil
	}
	lease, err := r.ensureLease(ctx, borrower, namespace, machine, host, knownFingerprint, rec)
	if err != nil {
		// A borrowing cluster not yet deployed with the RackHostLease kind or
		// its rack-lender identity: every env takes a lend up on its own deploy.
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "BorrowerUnavailable",
			"%s cannot take the lease of %s yet: %v", want, host.Name, err)
		if rec == nil || rec.State == infrav1.LendingOffered {
			return lendingGate{skipDrift: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
		}
		return r.holdLent(machine, rec), nil
	}

	state := ""
	if rec != nil {
		state = rec.State
	}
	if state == "" && lease.Spec.Phase == infrav1.LeaseLent && lease.Spec.GrantedKeyFingerprint != "" {
		// The record was lost while the lease stayed: the host is lent.
		if err := r.recordLending(ctx, host, &infrav1.RackHostLending{
			Borrower: want, State: infrav1.LendingLent, KeyFingerprint: lease.Spec.GrantedKeyFingerprint,
		}); err != nil {
			return lendingGate{}, err
		}
		return r.holdLent(machine, host.Status.Lease), nil
	}

	switch state {
	case "", infrav1.LendingOffered:
		if lease.Status.State != infrav1.LeaseAccepted || lease.Status.SSHPublicKey == "" {
			message := fmt.Sprintf("waiting for %s to accept", want)
			if lease.Status.State == infrav1.LeaseRefused {
				message = fmt.Sprintf("%s refused the host: it is not in its rackFleet.borrow.hosts", want)
			}
			if err := r.recordLending(ctx, host, &infrav1.RackHostLending{Borrower: want, State: infrav1.LendingOffered, Message: message}); err != nil {
				return lendingGate{}, err
			}
			return lendingGate{skipDrift: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
		}
		if err := r.recordLending(ctx, host, &infrav1.RackHostLending{Borrower: want, State: infrav1.LendingDraining}); err != nil {
			return lendingGate{}, err
		}
		fallthrough
	case infrav1.LendingDraining:
		return r.handOverToBorrower(ctx, borrower, machine, host, lease, sshKey, knownFingerprint)
	default:
		return r.keepLent(ctx, borrower, oc, lease)
	}
}

// handOverToBorrower drains this env's Node, retires the host's identity here
// and hands the runtime to the borrower with its key.
func (r *RackAppleSiliconMachineReconciler) handOverToBorrower(
	ctx context.Context,
	borrower client.Client,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	lease *infrav1.RackHostLease,
	sshKey []byte,
	knownFingerprint string,
) (lendingGate, error) {
	want := host.Spec.LendTo
	active, err := drainNodeForLease(ctx, r.Client, machine.Name, want)
	if err != nil {
		return lendingGate{}, fmt.Errorf("drain Node %s: %w", machine.Name, err)
	}
	machine.Status.Phase = "Lending"
	if len(active) > 0 {
		host.Status.Lease.Message = fmt.Sprintf("waiting for %d job(s) to finish here: %v", len(active), active)
		if err := r.recordLending(ctx, host, host.Status.Lease); err != nil {
			return lendingGate{}, err
		}
		return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingDrainRequeue}}, nil
	}
	if err := r.retireLocalNode(ctx, machine); err != nil {
		return lendingGate{}, fmt.Errorf("retire the local Node: %w", err)
	}
	// This cluster's scrapes go through the host's own tailnet device, which
	// becomes the borrower's.
	if err := r.deleteMachineEgressService(ctx, machine.Name); err != nil {
		return lendingGate{}, err
	}

	key := lease.Status.SSHPublicKey
	if err := r.handOver(ctx, machine, host, sshKey, knownFingerprint, want, key); err != nil {
		return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
	}
	fingerprint := leaseKeyFingerprint(key)
	if err := patchLease(ctx, borrower, lease, func(l *infrav1.RackHostLease) {
		l.Spec.Phase = infrav1.LeaseLent
		l.Spec.GrantedKeyFingerprint = fingerprint
	}); err != nil {
		return lendingGate{}, err
	}
	if err := r.recordLending(ctx, host, &infrav1.RackHostLending{Borrower: want, State: infrav1.LendingLent, KeyFingerprint: fingerprint}); err != nil {
		return lendingGate{}, err
	}
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Lent", "Handed %s's runtime to %s", host.Name, want)
	return r.holdLent(machine, host.Status.Lease), nil
}

// keepLent grants a key the borrower rotated, and takes the host back when the
// borrower released it on its own (it no longer runs it).
func (r *RackAppleSiliconMachineReconciler) keepLent(
	ctx context.Context,
	borrower client.Client,
	oc *osUpdateContext,
	lease *infrav1.RackHostLease,
) (lendingGate, error) {
	machine, host, sshKey, knownFingerprint := oc.machine, oc.host, oc.sshKey, oc.knownFingerprint
	rec := host.Status.Lease
	if lease.Status.State == infrav1.LeaseReleased || lease.Status.State == infrav1.LeaseRefused {
		return r.reclaim(ctx, borrower, machine, host, sshKey, knownFingerprint, lease)
	}
	key := lease.Status.SSHPublicKey
	if fingerprint := leaseKeyFingerprint(key); fingerprint != "" && fingerprint != rec.KeyFingerprint {
		if err := r.handOver(ctx, machine, host, sshKey, knownFingerprint, rec.Borrower, key); err != nil {
			return r.holdLent(machine, rec), nil
		}
		if err := patchLease(ctx, borrower, lease, func(l *infrav1.RackHostLease) { l.Spec.GrantedKeyFingerprint = fingerprint }); err != nil {
			return lendingGate{}, err
		}
		next := *rec
		next.KeyFingerprint = fingerprint
		if err := r.recordLending(ctx, host, &next); err != nil {
			return lendingGate{}, err
		}
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "LeaseKeyRotated", "Authorized %s's new key on %s", rec.Borrower, host.Name)
	}
	gate := r.holdLent(machine, host.Status.Lease)
	if result, err := r.serveSiteRequest(ctx, borrower, oc, lease); err != nil {
		return lendingGate{}, err
	} else if result.RequeueAfter > 0 && result.RequeueAfter < gate.result.RequeueAfter {
		gate.result = result
	}
	return gate, nil
}

// returnLentHost asks the borrower for the host back and, once it has drained
// and released it, takes the runtime back.
func (r *RackAppleSiliconMachineReconciler) returnLentHost(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	knownFingerprint string,
) (lendingGate, error) {
	rec := host.Status.Lease
	borrower, namespace, borrowerErr := r.borrowerOf(ctx, rec.Borrower)

	if rec.State == infrav1.LendingOffered || rec.State == infrav1.LendingDraining {
		// The runtime never changed hands: withdraw the offer.
		if borrowerErr == nil {
			if err := deleteLease(ctx, borrower, namespace, host.Name); err != nil {
				return lendingGate{}, err
			}
		}
		if err := uncordonNodeAfterLease(ctx, r.Client, machine.Name); err != nil {
			return lendingGate{}, err
		}
		return lendingGate{}, r.recordLending(ctx, host, nil)
	}

	var lease *infrav1.RackHostLease
	if borrowerErr == nil {
		lease = &infrav1.RackHostLease{}
		if err := borrower.Get(ctx, types.NamespacedName{Namespace: namespace, Name: host.Name}, lease); err != nil {
			if !apierrors.IsNotFound(err) {
				return lendingGate{}, err
			}
			lease = nil
		}
	}
	if rec.State != infrav1.LendingReturning {
		if lease != nil {
			if err := patchLease(ctx, borrower, lease, func(l *infrav1.RackHostLease) { l.Spec.Phase = infrav1.LeaseReturning }); err != nil {
				return lendingGate{}, err
			}
		}
		next := *rec
		next.State = infrav1.LendingReturning
		next.Message = fmt.Sprintf("waiting for %s to drain and release the host", rec.Borrower)
		if err := r.recordLending(ctx, host, &next); err != nil {
			return lendingGate{}, err
		}
	}

	released := borrowerErr == nil && (lease == nil || lease.Status.State == infrav1.LeaseReleased || lease.Status.State == infrav1.LeaseRefused)
	if !released && host.Annotations[ReclaimRuntimeAnnotation] != "true" {
		machine.Status.Phase = "Returning"
		return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingDrainRequeue}}, nil
	}
	return r.reclaim(ctx, borrower, machine, host, sshKey, knownFingerprint, lease)
}

// reclaim takes the runtime back: the borrower's key goes and this env owns
// the runtime again. Bootstrap then pushes this env's runtime with a fresh
// tailnet login, and finishReclaim ends the record.
func (r *RackAppleSiliconMachineReconciler) reclaim(
	ctx context.Context,
	borrower client.Client,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	knownFingerprint string,
	lease *infrav1.RackHostLease,
) (lendingGate, error) {
	rec := host.Status.Lease
	if err := r.handOver(ctx, machine, host, sshKey, knownFingerprint, r.Env, ""); err != nil {
		return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
	}
	next := *rec
	next.State = infrav1.LendingReclaimed
	next.KeyFingerprint = ""
	next.Message = ""
	if err := r.recordLending(ctx, host, &next); err != nil {
		return lendingGate{}, err
	}
	conditions.MarkFalse(machine, BootstrappedCondition, "Reclaimed", clusterv1.ConditionSeverityInfo,
		"took %s back from %s; bootstrapping this env's runtime", host.Name, rec.Borrower)
	if borrower != nil && lease != nil {
		if err := borrower.Delete(ctx, lease); err != nil && !apierrors.IsNotFound(err) {
			log.FromContext(ctx).Error(err, "delete the returned host's lease; the borrower holds nothing on it")
		}
	}
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Reclaimed", "Took %s's runtime back from %s", host.Name, rec.Borrower)
	return lendingGate{skipDrift: true, forceReauth: true}, nil
}

// finishReclaim ends the record of a returned host once bootstrap pushed this
// env's runtime to it.
func (r *RackAppleSiliconMachineReconciler) finishReclaim(ctx context.Context, host *infrav1.RackHost) {
	if host.Status.Lease == nil || host.Status.Lease.State != infrav1.LendingReclaimed {
		return
	}
	if err := r.recordLending(ctx, host, nil); err != nil {
		log.FromContext(ctx).Error(err, "end the returned host's lease record; will retry")
	}
}

func (r *RackAppleSiliconMachineReconciler) holdLent(machine *infrav1.RackAppleSiliconMachine, rec *infrav1.RackHostLending) lendingGate {
	machine.Status.Ready = true
	if !terminalPhasePinned(machine.Status.FailureReason) {
		machine.Status.Phase = "Lent"
	}
	if rec != nil {
		conditions.MarkTrue(machine, LentCondition)
	}
	return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}
}

// LentCondition is True on the Machine of a host whose runtime another env
// owns.
const LentCondition clusterv1.ConditionType = "Lent"

func (r *RackAppleSiliconMachineReconciler) handOver(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	knownFingerprint, owner, key string,
) error {
	handOver := r.handOverRuntime
	if handOver == nil {
		handOver = bootstrap.HandOverRuntime
	}
	cfg := bootstrap.Config{
		IP:                   r.dialTarget(host),
		SSHUser:              host.Spec.SSHUser,
		SSHPrivateKey:        sshKey,
		KnownHostFingerprint: knownFingerprint,
	}
	fingerprint, err := handOver(ctx, cfg, owner, key)
	r.persistFingerprint(ctx, machine, fingerprint, knownFingerprint)
	if err != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeWarning, "HandOverFailed",
			"Could not hand %s's runtime to %s: %v (will retry)", host.Name, owner, err)
		return err
	}
	return nil
}

func (r *RackAppleSiliconMachineReconciler) borrowerOf(ctx context.Context, env string) (client.Client, string, error) {
	if r.Borrowers == nil {
		return nil, "", fmt.Errorf("this operator lends to no env")
	}
	return r.Borrowers.Borrower(ctx, env)
}

// ensureLease keeps the lease's facts current. Its phase and granted key are
// set only by the step that changes them.
func (r *RackAppleSiliconMachineReconciler) ensureLease(
	ctx context.Context,
	borrower client.Client,
	namespace string,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	knownFingerprint string,
	rec *infrav1.RackHostLending,
) (*infrav1.RackHostLease, error) {
	lease := &infrav1.RackHostLease{ObjectMeta: metav1.ObjectMeta{Name: host.Name, Namespace: namespace}}
	_, err := controllerutil.CreateOrPatch(ctx, borrower, lease, func() error {
		if lease.Labels == nil {
			lease.Labels = map[string]string{}
		}
		lease.Labels["app.kubernetes.io/managed-by"] = operatorName
		lease.Labels[RackHostLabel] = host.Name
		lease.Spec.Lender = r.Env
		if lease.Spec.Phase == "" {
			lease.Spec.Phase = infrav1.LeaseOffered
			if rec != nil && rec.State == infrav1.LendingLent {
				lease.Spec.Phase = infrav1.LeaseLent
				lease.Spec.GrantedKeyFingerprint = rec.KeyFingerprint
			}
		}
		lease.Spec.PreviousNodeName = machine.Name
		if knownFingerprint != "" {
			lease.Spec.Host.HostKeyFingerprint = knownFingerprint
		}
		lease.Spec.Host.Serial = host.Spec.Serial
		lease.Spec.Host.Address = host.Spec.Address
		lease.Spec.Host.SSHUser = host.Spec.SSHUser
		// The rack's edges, which every dial to the host arrives from, the
		// lender's included: the borrower's guard must keep admitting them.
		lease.Spec.Host.SSHIngressAllowCIDRs = slices.Clone(host.Spec.SSHIngressAllowCIDRs)
		lease.Spec.Host.Site = host.Spec.Location.Site
		lease.Spec.Host.Machine = r.leaseMachine(machine, host)
		return nil
	})
	return lease, err
}

// leaseMachine is the host's sizing with this operator's defaults applied.
func (r *RackAppleSiliconMachineReconciler) leaseMachine(machine *infrav1.RackAppleSiliconMachine, host *infrav1.RackHost) infrav1.RackHostMachine {
	sizing := r.hostSizing(machine)
	m := infrav1.RackHostMachine{
		HostCPU:              sizing.HostCPU,
		HostMemoryMB:         sizing.HostMemoryMB,
		GuestCapacity:        sizing.GuestCapacity,
		MaxPods:              sizing.MaxPods,
		RunnerCacheVolumeGiB: ptr.To(sizing.RunnerCacheVolumeGiB),
	}
	if v := host.Spec.Machine.HostCPU; v > 0 {
		m.HostCPU = v
	}
	if v := host.Spec.Machine.HostMemoryMB; v > 0 {
		m.HostMemoryMB = v
	}
	if v := host.Spec.Machine.GuestCapacity; v > 0 {
		m.GuestCapacity = v
	}
	if v := host.Spec.Machine.MaxPods; v > 0 {
		m.MaxPods = v
	}
	if v := host.Spec.Machine.RunnerCacheVolumeGiB; v != nil && *v >= 0 {
		m.RunnerCacheVolumeGiB = ptr.To(*v)
	}
	return m
}

// recordLending writes the lend's state on the host, stamping when it changed.
// A nil record ends the lend.
func (r *RackAppleSiliconMachineReconciler) recordLending(ctx context.Context, host *infrav1.RackHost, rec *infrav1.RackHostLending) error {
	fresh := &infrav1.RackHost{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(host), fresh); err != nil {
		return err
	}
	if rec != nil {
		rec = rec.DeepCopy()
		if prev := fresh.Status.Lease; prev != nil && prev.State == rec.State && prev.Borrower == rec.Borrower && prev.Since != nil {
			rec.Since = prev.Since
		} else {
			rec.Since = &metav1.Time{Time: time.Now()}
		}
	}
	fresh.Status.Lease = rec
	if err := r.Status().Update(ctx, fresh); err != nil {
		return err
	}
	host.Status.Lease = rec
	return nil
}

func (r *RackAppleSiliconMachineReconciler) deleteMachineEgressService(ctx context.Context, name string) error {
	if r.EgressProxyGroup == "" || r.EgressNamespace == "" {
		return nil
	}
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: r.EgressNamespace}}
	if err := r.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("delete egress Service %s/%s: %w", r.EgressNamespace, name, err)
	}
	return nil
}

func patchLease(ctx context.Context, c client.Client, lease *infrav1.RackHostLease, mutate func(*infrav1.RackHostLease)) error {
	base := lease.DeepCopy()
	mutate(lease)
	return c.Patch(ctx, lease, client.MergeFrom(base))
}

func deleteLease(ctx context.Context, c client.Client, namespace, name string) error {
	lease := &infrav1.RackHostLease{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace}}
	if err := c.Delete(ctx, lease); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	return nil
}

// reclaimOrphan takes back a host whose runtime another env owns with no lend
// on record here, which bootstrap refuses (RuntimeOwnedElsewhere): only on
// ReclaimRuntimeAnnotation, since that env may be running jobs on it.
func (r *RackAppleSiliconMachineReconciler) reclaimOrphan(
	ctx context.Context,
	machine *infrav1.RackAppleSiliconMachine,
	host *infrav1.RackHost,
	sshKey []byte,
	knownFingerprint string,
) (lendingGate, error) {
	if host.Annotations[ReclaimRuntimeAnnotation] != "true" ||
		conditions.GetReason(machine, BootstrappedCondition) != "RuntimeOwnedElsewhere" || r.Env == "" {
		return lendingGate{}, nil
	}
	if err := r.handOver(ctx, machine, host, sshKey, knownFingerprint, r.Env, ""); err != nil {
		return lendingGate{stop: true, result: ctrl.Result{RequeueAfter: lendingRequeue}}, nil
	}
	conditions.MarkFalse(machine, BootstrappedCondition, "Reclaimed", clusterv1.ConditionSeverityInfo,
		"took %s back from the env that owned its runtime; bootstrapping this env's runtime", host.Name)
	r.Recorder.Eventf(machine, corev1.EventTypeNormal, "Reclaimed", "Took %s's runtime back", host.Name)
	return lendingGate{forceReauth: true}, nil
}
