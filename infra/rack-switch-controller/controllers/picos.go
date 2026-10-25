package controllers

import (
	"context"
	"errors"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/picos"
)

// reconcilePicOS adopts and converges a PicOS switch over SSH and NETCONF.
// Adoption is the first connection: it pins the host key the switch presents
// and sets admin's password. Every write after it needs that key.
func (r *RackSwitchReconciler) reconcilePicOS(ctx context.Context, rs *v1alpha1.RackSwitch) (ctrl.Result, error) {
	st := &rs.Status
	st.ControllerStatus = ""
	if r.PicOS == nil {
		r.failed(rs, "PicOSNotConfigured", errors.New("the controller runs without a PicOS key, so it cannot reach PicOS switches"))
		return ctrl.Result{}, nil
	}
	if rs.Spec.ManagementAddress == "" {
		r.failed(rs, "NoManagementAddress", errors.New("spec.managementAddress is empty"))
		return ctrl.Result{}, nil
	}
	blocker, err := r.blockedBy(ctx, rs)
	if err != nil {
		return ctrl.Result{}, err
	}
	now := r.now()

	justAdopted := false
	if st.HostKey == "" {
		st.Adopted = false
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionConverged, false, "NotAdopted", "the switch is not adopted")
		if blocker != nil {
			r.condition(rs, v1alpha1.ConditionAdopted, false, "WaitingForApplyOrder",
				fmt.Sprintf("waiting for %s (applyOrder %d) to be Ready before adopting", blocker.Name, blocker.Spec.ApplyOrder))
			r.ready(rs)
			return ctrl.Result{RequeueAfter: applyOrderPollInterval}, nil
		}
		password, err := r.PicOSAdminPassword()
		if err != nil {
			r.failed(rs, "CredentialsUnavailable", err)
			return ctrl.Result{}, err
		}
		hostKey, err := r.PicOS.Adopt(ctx, rs.Spec.ManagementAddress, password)
		if err != nil {
			// A switch still in ZTP, or one ZTP has not provisioned yet,
			// refuses the controller's key; that is a wait, not a fault.
			st.Reachable = false
			r.condition(rs, v1alpha1.ConditionAdopted, false, "NotProvisioned",
				"the switch does not take the controller's key yet: "+err.Error())
			r.ready(rs)
			return ctrl.Result{RequeueAfter: adoptionPollInterval}, nil
		}
		st.HostKey = hostKey
		justAdopted = true
		r.Recorder.Eventf(rs, corev1.EventTypeNormal, "Adopted", "pinned host key %s and set admin's password", hostKey)
	}

	if rs.Spec.Config == nil {
		st.Adopted = true
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionAdopted, true, "Adopted", "host key "+st.HostKey)
		r.condition(rs, v1alpha1.ConditionConverged, false, "ConfigMissing", "spec.config is empty, so there is nothing to converge to")
		r.ready(rs)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}

	needsApply := justAdopted || st.ObservedRevision != rs.Spec.ConfigRevision || st.ObservedGeneration != rs.Generation
	apply := needsApply && blocker == nil
	report, err := r.PicOS.Converge(ctx, rs, st.HostKey, apply)
	if len(report.Changes) > 0 {
		r.Recorder.Eventf(rs, corev1.EventTypeNormal, "Wrote", "%s", truncate(strings.Join(report.Changes, "; ")))
	}
	switch {
	case errors.Is(err, picos.ErrHostKeyMismatch):
		st.Adopted = false
		st.Reachable = false
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionAdopted, false, "HostKeyMismatch",
			err.Error()+"; clear status.hostKey once the switch is known to be ours, as after a factory reset or a replacement")
		r.condition(rs, v1alpha1.ConditionConverged, false, "HostKeyMismatch", "not written to: the host key is not the pinned one")
		r.Recorder.Event(rs, corev1.EventTypeWarning, "HostKeyMismatch", err.Error())
		r.ready(rs)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	case err != nil:
		st.Reachable = report.HostKey != ""
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionConverged, false, "ConvergeFailed", err.Error())
		r.ready(rs)
		return ctrl.Result{}, err
	}
	st.Adopted = true
	st.Reachable = true
	r.condition(rs, v1alpha1.ConditionAdopted, true, "Adopted", "host key "+st.HostKey)
	return r.settle(ctx, rs, apply, needsApply, blocker, report.Drift, now), nil
}
