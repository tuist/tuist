package macos

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// Site requests: what the borrower of a lent host asks the env that owns its
// site to do to it, because only that env holds the PDU and the fleet
// credential. The borrower writes the request in the lease's status, the
// lender answers in its spec, one request at a time.

// PowerCycleAnnotation on a RackHostLease asks the lender to cycle the host's
// outlet. Its value is free text for the person asking; the borrower removes
// it once answered.
const PowerCycleAnnotation = "tuist.dev/power-cycle"

// leaseOSUpdateAnnotation marks an OSUpdateAnnotation on a lent host's Machine
// as one a lease request set, valued with the request's ID. A lent host takes
// no other update.
const leaseOSUpdateAnnotation = "tuist.dev/os-update-lease-request"

// serveSiteRequest answers the borrower's open site request. An update runs
// through the lent host's own update flow; the borrower drained its Node
// before asking, and converges its runtime after.
func (r *RackAppleSiliconMachineReconciler) serveSiteRequest(
	ctx context.Context,
	borrower client.Client,
	oc *osUpdateContext,
	lease *infrav1.RackHostLease,
) (ctrl.Result, error) {
	req := lease.Status.SiteRequest
	if req == nil {
		return ctrl.Result{}, nil
	}
	res := lease.Spec.SiteRequestResult
	if res != nil && res.ID == req.ID && siteRequestAnswered(res.Phase) {
		return ctrl.Result{}, nil
	}
	machine, host := oc.machine, oc.host
	next := &infrav1.RackHostLeaseSiteResult{ID: req.ID, Phase: infrav1.SiteRequestRunning}
	if res != nil && res.ID == req.ID {
		next.OSUpdateID = res.OSUpdateID
	}
	result := ctrl.Result{RequeueAfter: osUpdatePollInterval}

	switch req.Action {
	case infrav1.SiteRequestPowerCycle:
		if err := r.cycleHostPower(ctx, host); err != nil {
			next.Phase, next.Message = infrav1.SiteRequestFailed, fmt.Sprintf("could not cycle %s's outlet: %v", host.Name, err)
		} else {
			next.Phase, next.Message, next.ReturnToService = infrav1.SiteRequestSucceeded, fmt.Sprintf("cycled %s's outlet", host.Name), true
		}
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, "SiteRequest", "%s asked to power-cycle %s: %s", lease.Spec.Lender, host.Name, next.Message)

	case infrav1.SiteRequestOSUpdate:
		if !req.Drained {
			next.Message = "waiting for the borrower to drain its Node"
			break
		}
		st := machine.Status.OSUpdate
		if next.OSUpdateID == "" || st == nil || st.ID != next.OSUpdateID {
			if st != nil && !osUpdateFinished(st.Phase) {
				next.Message = fmt.Sprintf("waiting for update %s to end", st.ID)
				break
			}
			metav1.SetMetaDataAnnotation(&machine.ObjectMeta, OSUpdateAnnotation, req.Target)
			metav1.SetMetaDataAnnotation(&machine.ObjectMeta, leaseOSUpdateAnnotation, req.ID)
		}
		oc.lent = true
		if _, err := r.reconcileOSUpdate(ctx, oc); err != nil {
			return ctrl.Result{}, err
		}
		st = machine.Status.OSUpdate
		if st == nil {
			break
		}
		next.OSUpdateID = st.ID
		next.Message = fmt.Sprintf("%s: %s", st.Phase, st.Message)
		if osUpdateFinished(st.Phase) {
			next.Phase = infrav1.SiteRequestFailed
			if st.Phase == OSUpdatePhaseSucceeded {
				next.Phase = infrav1.SiteRequestSucceeded
			} else {
				next.Message = fmt.Sprintf("%s: %s", st.Reason, st.Message)
			}
			// Before Installing records the boot time, nothing on the host
			// changed.
			next.ReturnToService = st.Phase == OSUpdatePhaseSucceeded || st.BootTimeBefore == 0
			delete(machine.Annotations, leaseOSUpdateAnnotation)
			delete(machine.Annotations, OSUpdateAnnotation)
		}

	default:
		next.Phase, next.Message = infrav1.SiteRequestFailed, fmt.Sprintf("%q is not a site request this operator serves", req.Action)
	}

	if siteRequestAnswered(next.Phase) {
		now := metav1.Now()
		next.CompletedAt = &now
		result = ctrl.Result{}
	}
	if res == nil || *res != *next {
		if err := patchLease(ctx, borrower, lease, func(l *infrav1.RackHostLease) { l.Spec.SiteRequestResult = next }); err != nil {
			return ctrl.Result{}, err
		}
	}
	return result, nil
}

func siteRequestAnswered(phase string) bool {
	return phase == infrav1.SiteRequestSucceeded || phase == infrav1.SiteRequestFailed
}
