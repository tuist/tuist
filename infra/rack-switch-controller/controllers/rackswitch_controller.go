// Package controllers holds the RackSwitch reconciler.
package controllers

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

const (
	// StandaloneMessage is the status message of a switch this controller
	// leaves alone.
	StandaloneMessage = "standalone: changed over SSH with rack:fleet, not by the rack switch controller"

	adoptionPollInterval   = 15 * time.Second
	applyOrderPollInterval = 30 * time.Second
	maxDriftInMessage      = 5
	maxEventMessage        = 1000
)

// RackSwitchReconciler adopts and converges the RackSwitches in one namespace
// whose managedBy is controller, through the Omada controller. Standalone
// ones only get a status message saying so.
//
// A change is a write to the switch or to its site: adoption, the site
// settings, and the switch's configuration. Changes happen when the spec's
// configRevision or generation moves past what status records, or when the
// switch has just been adopted, and never while a switch of the same site
// with a lower applyOrder is not Ready. Between changes it only reads, every
// resync, and reports drift without writing over it.
type RackSwitchReconciler struct {
	client.Client
	Recorder       record.EventRecorder
	Engine         *converge.Engine
	Credentials    func() (converge.Credentials, error)
	ResyncInterval time.Duration
	Now            func() time.Time

	mu       sync.Mutex
	attempts map[types.NamespacedName]*converge.Attempt
}

func (r *RackSwitchReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	var rs v1alpha1.RackSwitch
	if err := r.Get(ctx, req.NamespacedName, &rs); err != nil {
		if apierrors.IsNotFound(err) {
			r.setAttempt(req.NamespacedName, nil)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}
	before := rs.DeepCopy()

	if rs.Spec.ManagedBy != v1alpha1.ManagedByController {
		r.setAttempt(req.NamespacedName, nil)
		rs.Status.Message = StandaloneMessage
		return ctrl.Result{}, r.patchStatus(ctx, before, &rs)
	}

	result, reconcileErr := r.reconcileManaged(ctx, &rs)
	if err := r.patchStatus(ctx, before, &rs); err != nil {
		return ctrl.Result{}, errors.Join(reconcileErr, err)
	}
	return result, reconcileErr
}

func (r *RackSwitchReconciler) reconcileManaged(ctx context.Context, rs *v1alpha1.RackSwitch) (ctrl.Result, error) {
	log := logf.FromContext(ctx)
	st := &rs.Status
	key := client.ObjectKeyFromObject(rs)
	now := r.now()

	creds, err := r.Credentials()
	if err != nil {
		r.failed(rs, "CredentialsUnavailable", err)
		return ctrl.Result{}, err
	}
	blocker, err := r.blockedBy(ctx, rs)
	if err != nil {
		return ctrl.Result{}, err
	}
	siteID, err := r.Engine.SiteID(ctx)
	if err != nil {
		r.failed(rs, "ControllerUnavailable", err)
		return ctrl.Result{}, err
	}

	if blocker == nil {
		changes, err := r.Engine.EnsureSite(ctx, siteID, creds.DeviceAccount)
		r.recordChanges(ctx, rs, "SiteConverged", "site "+r.Engine.Site, changes)
		if err != nil {
			r.failed(rs, "SiteWriteFailed", err)
			return ctrl.Result{}, err
		}
	}

	dev, err := r.Engine.Find(ctx, siteID, rs.Spec.MAC)
	if err != nil {
		r.failed(rs, "ControllerUnavailable", err)
		return ctrl.Result{}, err
	}
	if dev == nil {
		r.setAttempt(key, nil)
		st.Adopted = false
		st.Reachable = false
		st.ControllerStatus = ""
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionAdopted, false, "NotSeen",
			fmt.Sprintf("%s is not in the Omada site %q; point it at the controller with rack:omada inform", omada.ControllerMAC(rs.Spec.MAC), r.Engine.Site))
		r.condition(rs, v1alpha1.ConditionConverged, false, "NotAdopted", "the switch is not adopted")
		r.ready(rs)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}
	st.ControllerStatus = dev.State()

	attempt := r.attempt(key)
	justAdopted := false
	switch {
	case dev.Status == omada.StatusConnected:
		if attempt != nil {
			r.Recorder.Eventf(rs, corev1.EventTypeNormal, "Adopted", "adopted with %s", attempt.Login)
			r.setAttempt(key, nil)
			justAdopted = true
		} else if !st.Adopted {
			justAdopted = true
		}
	case attempt != nil || dev.Status == omada.StatusPending:
		return r.adopt(ctx, rs, siteID, *dev, attempt, blocker, creds, now)
	default:
		st.Adopted = true
		st.Reachable = false
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionAdopted, true, "Adopted", fmt.Sprintf("adopted into the Omada site %q", r.Engine.Site))
		r.condition(rs, v1alpha1.ConditionConverged, false, "Unreachable", "the controller reports the switch "+dev.State())
		r.ready(rs)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}

	st.Adopted = true
	st.Reachable = true
	r.condition(rs, v1alpha1.ConditionAdopted, true, "Adopted", fmt.Sprintf("adopted into the Omada site %q", r.Engine.Site))

	if rs.Spec.Config == nil {
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionConverged, false, "ConfigMissing", "spec.config is empty, so there is nothing to converge to")
		r.ready(rs)
		return ctrl.Result{RequeueAfter: r.ResyncInterval}, nil
	}

	needsApply := justAdopted || st.ObservedRevision != rs.Spec.ConfigRevision || st.ObservedGeneration != rs.Generation
	apply := needsApply && blocker == nil
	report, err := r.Engine.Converge(ctx, siteID, rs, apply)
	r.recordChanges(ctx, rs, "Wrote", "", report.Changes)
	if err != nil {
		st.Drift = v1alpha1.DriftUnknown
		r.condition(rs, v1alpha1.ConditionConverged, false, "ConvergeFailed", err.Error())
		r.ready(rs)
		return ctrl.Result{}, err
	}

	previousDrift := st.Drift
	st.LastVerified = &metav1.Time{Time: now}
	st.Drift = v1alpha1.DriftNone
	if len(report.Drift) > 0 {
		st.Drift = v1alpha1.DriftDrifted
	}
	revision := rs.Spec.ConfigRevision
	result := ctrl.Result{RequeueAfter: r.ResyncInterval}
	switch {
	case apply && len(report.Drift) == 0:
		st.ObservedRevision = revision
		st.ObservedGeneration = rs.Generation
		r.condition(rs, v1alpha1.ConditionConverged, true, "Converged", "wrote revision "+revision)
	case apply:
		r.condition(rs, v1alpha1.ConditionConverged, false, "NotVerified",
			fmt.Sprintf("wrote revision %s, and the controller still reads: %s", revision, summarize(report.Drift)))
	case needsApply:
		r.condition(rs, v1alpha1.ConditionConverged, false, "WaitingForApplyOrder",
			fmt.Sprintf("waiting for %s (applyOrder %d) to be Ready before changing this switch", blocker.Name, blocker.Spec.ApplyOrder))
		result.RequeueAfter = applyOrderPollInterval
	case len(report.Drift) > 0:
		r.condition(rs, v1alpha1.ConditionConverged, false, "Drifted",
			fmt.Sprintf("differs from revision %s: %s", revision, summarize(report.Drift)))
		if previousDrift != v1alpha1.DriftDrifted {
			r.Recorder.Eventf(rs, corev1.EventTypeWarning, "Drifted", "%s", truncate(strings.Join(report.Drift, "; ")))
		}
		log.Info("drift", "differences", report.Drift)
	default:
		r.condition(rs, v1alpha1.ConditionConverged, true, "Converged", "matches revision "+revision)
	}
	r.ready(rs)
	return result, nil
}

func (r *RackSwitchReconciler) adopt(ctx context.Context, rs *v1alpha1.RackSwitch, siteID string, dev omada.Device, attempt *converge.Attempt, blocker *v1alpha1.RackSwitch, creds converge.Credentials, now time.Time) (ctrl.Result, error) {
	st := &rs.Status
	key := client.ObjectKeyFromObject(rs)
	st.Adopted = false
	st.Reachable = false
	st.Drift = v1alpha1.DriftUnknown
	r.condition(rs, v1alpha1.ConditionConverged, false, "NotAdopted", "the switch is not adopted")

	if blocker != nil && attempt == nil {
		r.condition(rs, v1alpha1.ConditionAdopted, false, "WaitingForApplyOrder",
			fmt.Sprintf("pending; waiting for %s (applyOrder %d) to be Ready before adopting", blocker.Name, blocker.Spec.ApplyOrder))
		r.ready(rs)
		return ctrl.Result{RequeueAfter: applyOrderPollInterval}, nil
	}

	adoption, err := r.Engine.Adopt(ctx, siteID, dev, attempt, creds, now)
	for _, note := range adoption.Notes {
		eventType := corev1.EventTypeNormal
		if note.Warning {
			eventType = corev1.EventTypeWarning
		}
		r.Recorder.Event(rs, eventType, note.Reason, note.Message)
	}
	if err != nil {
		r.setAttempt(key, nil)
		r.condition(rs, v1alpha1.ConditionAdopted, false, "AdoptionError", err.Error())
		r.ready(rs)
		return ctrl.Result{}, err
	}
	r.setAttempt(key, adoption.Attempt)

	result := ctrl.Result{RequeueAfter: r.ResyncInterval}
	switch adoption.Outcome {
	case converge.AdoptionWaiting:
		r.condition(rs, v1alpha1.ConditionAdopted, false, "Adopting",
			fmt.Sprintf("adopting with %s; the controller reports it %s", adoption.Attempt.Login, dev.State()))
		result.RequeueAfter = adoptionPollInterval
	case converge.AdoptionFailed:
		r.condition(rs, v1alpha1.ConditionAdopted, false, "AdoptionFailed", lastNote(adoption.Notes))
	case converge.AdoptionManagedByOthers:
		r.condition(rs, v1alpha1.ConditionAdopted, false, "ManagedByOthers", lastNote(adoption.Notes))
	}
	r.ready(rs)
	return result, nil
}

// blockedBy is the switch of the same site with the lowest applyOrder below
// this one's that is not Ready, or nil. A controller-managed switch is Ready
// by its condition; a standalone one when rack:fleet publish last saw it at
// its revision with no drift.
func (r *RackSwitchReconciler) blockedBy(ctx context.Context, rs *v1alpha1.RackSwitch) (*v1alpha1.RackSwitch, error) {
	var switches v1alpha1.RackSwitchList
	if err := r.List(ctx, &switches, client.InNamespace(rs.Namespace)); err != nil {
		return nil, err
	}
	var blocker *v1alpha1.RackSwitch
	for i := range switches.Items {
		other := &switches.Items[i]
		if other.Spec.Site != rs.Spec.Site || other.Spec.ApplyOrder >= rs.Spec.ApplyOrder || isReady(other) {
			continue
		}
		if blocker == nil || other.Spec.ApplyOrder < blocker.Spec.ApplyOrder {
			blocker = other
		}
	}
	return blocker, nil
}

// isReady also requires the Ready condition to be about the current spec, so
// a switch whose new revision has not been reconciled yet holds the ones
// after it.
func isReady(rs *v1alpha1.RackSwitch) bool {
	atRevision := rs.Status.ObservedRevision == rs.Spec.ConfigRevision
	if rs.Spec.ManagedBy == v1alpha1.ManagedByController {
		ready := meta.FindStatusCondition(rs.Status.Conditions, v1alpha1.ConditionReady)
		return atRevision && ready != nil && ready.Status == metav1.ConditionTrue && ready.ObservedGeneration == rs.Generation
	}
	return atRevision && rs.Status.Drift == v1alpha1.DriftNone
}

func (r *RackSwitchReconciler) failed(rs *v1alpha1.RackSwitch, reason string, err error) {
	rs.Status.Drift = v1alpha1.DriftUnknown
	r.condition(rs, v1alpha1.ConditionConverged, false, reason, err.Error())
	r.ready(rs)
}

func (r *RackSwitchReconciler) condition(rs *v1alpha1.RackSwitch, conditionType string, status bool, reason, message string) {
	s := metav1.ConditionFalse
	if status {
		s = metav1.ConditionTrue
	}
	meta.SetStatusCondition(&rs.Status.Conditions, metav1.Condition{
		Type:               conditionType,
		Status:             s,
		Reason:             reason,
		Message:            message,
		ObservedGeneration: rs.Generation,
	})
}

// ready sets the Ready condition and the status message from the other two
// conditions and the revision.
func (r *RackSwitchReconciler) ready(rs *v1alpha1.RackSwitch) {
	st := &rs.Status
	adopted := meta.FindStatusCondition(st.Conditions, v1alpha1.ConditionAdopted)
	converged := meta.FindStatusCondition(st.Conditions, v1alpha1.ConditionConverged)
	switch {
	case adopted != nil && adopted.Status != metav1.ConditionTrue:
		r.condition(rs, v1alpha1.ConditionReady, false, adopted.Reason, adopted.Message)
	case converged != nil && converged.Status != metav1.ConditionTrue:
		r.condition(rs, v1alpha1.ConditionReady, false, converged.Reason, converged.Message)
	case !st.Adopted || !st.Reachable || st.ObservedRevision != rs.Spec.ConfigRevision || st.Drift != v1alpha1.DriftNone:
		r.condition(rs, v1alpha1.ConditionReady, false, "NotConverged", "not yet at revision "+rs.Spec.ConfigRevision)
	default:
		r.condition(rs, v1alpha1.ConditionReady, true, "Ready", "adopted, connected, and at revision "+rs.Spec.ConfigRevision)
	}
	st.Message = meta.FindStatusCondition(st.Conditions, v1alpha1.ConditionReady).Message
}

func (r *RackSwitchReconciler) recordChanges(ctx context.Context, rs *v1alpha1.RackSwitch, reason, prefix string, changes []converge.Change) {
	if len(changes) == 0 {
		return
	}
	lines := make([]string, len(changes))
	for i, c := range changes {
		lines[i] = c.String()
	}
	logf.FromContext(ctx).Info(reason, "changes", lines)
	message := strings.Join(lines, "; ")
	if prefix != "" {
		message = prefix + ": " + message
	}
	r.Recorder.Event(rs, corev1.EventTypeNormal, reason, truncate(message))
}

func (r *RackSwitchReconciler) patchStatus(ctx context.Context, before, after *v1alpha1.RackSwitch) error {
	if equality.Semantic.DeepEqual(before.Status, after.Status) {
		return nil
	}
	return r.Status().Patch(ctx, after, client.MergeFrom(before))
}

func (r *RackSwitchReconciler) attempt(key types.NamespacedName) *converge.Attempt {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.attempts[key]
}

func (r *RackSwitchReconciler) setAttempt(key types.NamespacedName, attempt *converge.Attempt) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if attempt == nil {
		delete(r.attempts, key)
		return
	}
	if r.attempts == nil {
		r.attempts = map[types.NamespacedName]*converge.Attempt{}
	}
	r.attempts[key] = attempt
}

func (r *RackSwitchReconciler) now() time.Time {
	if r.Now != nil {
		return r.Now()
	}
	return time.Now()
}

func summarize(drift []string) string {
	if len(drift) <= maxDriftInMessage {
		return strings.Join(drift, "; ")
	}
	return fmt.Sprintf("%s; and %d more", strings.Join(drift[:maxDriftInMessage], "; "), len(drift)-maxDriftInMessage)
}

func truncate(s string) string {
	if len(s) <= maxEventMessage {
		return s
	}
	return s[:maxEventMessage-3] + "..."
}

func lastNote(notes []converge.Note) string {
	if len(notes) == 0 {
		return ""
	}
	return notes[len(notes)-1].Message
}

// SetupWithManager watches RackSwitches for spec changes only: status writes
// do not trigger a reconcile, and the resync interval brings each back.
func (r *RackSwitchReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&v1alpha1.RackSwitch{}, builder.WithPredicates(predicate.GenerationChangedPredicate{})).
		WithOptions(controller.Options{MaxConcurrentReconciles: 1}).
		Named("rackswitch").
		Complete(r)
}
