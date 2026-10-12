package macos

import (
	"context"
	"errors"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackcard"
)

const (
	// RackATSRedundantCondition is whether the source not powering the load
	// could take it: False when it is not good, or when neither source powers
	// the load.
	RackATSRedundantCondition clusterv1.ConditionType = "Redundant"

	// RackATSFinalizer holds a controller-managed RackATS until the
	// controller's session on its card is logged out and its egress Service,
	// in another namespace, is deleted.
	RackATSFinalizer = "tuist.dev/rackats"
	// legacyRackATSFinalizer is the name an earlier build gave it.
	legacyRackATSFinalizer = "tuist.dev/rackats-egress"

	// rackATSObserveInterval is how often an adopted switch's sources are
	// read.
	rackATSObserveInterval = time.Minute
	rackATSRetryInterval   = time.Minute
	// rackATSUnsupportedInterval is how often a card the controller does not
	// recognise is looked at again.
	rackATSUnsupportedInterval = 10 * time.Minute
)

// rackATSHost is the card's endpoint; tests point it at a fake card.
var rackATSHost = func(ats *infrav1.RackATS) string {
	return "https://" + ats.Spec.Address
}

// RackATSReconciler adopts each controller-managed RackATS's card, keeps its
// preferred source, and observes it: every minute it records which source
// powers the load and how each source is, in status, as metrics, and as an
// event on every transfer it sees.
type RackATSReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder

	// Power holds the eaton driver, whose session of each card's controller
	// account the observations go through.
	Power *power.Registry

	// EgressNamespace and EgressProxyGroup, when both set, put an egress
	// Service in front of each card, which the controller dials.
	EgressNamespace  string
	EgressProxyGroup string

	// Timeout bounds each request to a card. Zero means 15 seconds.
	Timeout time.Duration

	// APIReader reads the RackATS past the manager's cache before adopting,
	// so a cache that has not seen the last pass's status yet does not start
	// another. Nil reads through Client.
	APIReader client.Reader

	// RootKeySecret is the Secret whose `key` every card's passwords are
	// derived from. Without it no card is adopted.
	RootKeySecret types.NamespacedName

	// loginBackoff holds off every contact with a card that refused a login
	// the pass depends on; adminBackoff only the administrator's logins to an
	// adopted card, which is still observed meanwhile.
	loginBackoff cardLoginBackoff
	adminBackoff cardLoginBackoff

	// Card, when set, replaces the card a RackATS is spoken to through; tests
	// set it.
	Card func(r *RackATSReconciler, ats *infrav1.RackATS, secret *corev1.Secret, passwords rackcard.Passwords) atsCard
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackatses,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackatses/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackatses/finalizers,verbs=update

func (r *RackATSReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	ats := &infrav1.RackATS{}
	if getErr := r.Get(ctx, req.NamespacedName, ats); getErr != nil {
		if client.IgnoreNotFound(getErr) == nil {
			forgetRackATSMetrics(req.Name)
		}
		return ctrl.Result{}, client.IgnoreNotFound(getErr)
	}
	helper, helperErr := patch.NewHelper(ats, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := helper.Patch(ctx, ats); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	if !ats.DeletionTimestamp.IsZero() {
		forgetRackATSMetrics(ats.Name)
		return ctrl.Result{}, releaseRackCard(ctx, r.Client, r.egressConfig(), func() { r.logOut(ctx, ats) },
			rackATSEgress(ats), ats, RackATSFinalizer, legacyRackATSFinalizer)
	}
	if ats.Spec.ManagedBy != infrav1.RackCardManagedByController {
		ats.Status.Message = "standalone: the controller does not contact this transfer switch"
		conditions.MarkFalse(ats, clusterv1.ReadyCondition, "Standalone", clusterv1.ConditionSeverityInfo,
			"managedBy is %s: the controller neither adopts nor observes this transfer switch", ats.Spec.ManagedBy)
		r.markUnobserved(ats, "Standalone", "the controller does not observe a standalone transfer switch")
		forgetRackATSMetrics(ats.Name)
		r.logOut(ctx, ats)
		return ctrl.Result{}, nil
	}
	defer func() { recordRackATSMetrics(ats) }()

	rootKey, err := loadRackCardRootKey(ctx, r.Client, r.RootKeySecret)
	var missing *rackCardRootKeyError
	if errors.As(err, &missing) {
		markRackCardRootKeyMissing(ats, err)
		r.markUnobserved(ats, "RootKeyMissing", err.Error())
		return ctrl.Result{RequeueAfter: rackATSRetryInterval}, nil
	}
	if err != nil {
		return ctrl.Result{}, err
	}
	passwords := rackCardDerivedPasswords(rootKey, ats.Spec.Site, ats.Spec.MAC, ats.Name)

	controllerutil.AddFinalizer(ats, RackATSFinalizer)
	controllerutil.RemoveFinalizer(ats, legacyRackATSFinalizer)
	if wait := r.loginBackoff.wait(ats); wait > 0 {
		return ctrl.Result{RequeueAfter: wait}, nil
	}
	if r.egressConfig().enabled() {
		if err := rackATSEgress(ats).reconcile(ctx, r.Client, r.egressConfig()); err != nil {
			return ctrl.Result{}, err
		}
	}

	secret, err := ensureRackCardSecret(ctx, r.Client, ats, "tuist.dev/rack-ats", ats.Spec.Address, passwords)
	if err != nil {
		return ctrl.Result{}, err
	}
	ats.Status.CredentialsSecret = secret.Name
	markRackCardAddress(ats, ats.Spec.MAC, ats.Spec.Address)

	card := r.card(ats, secret, passwords)
	presented, err := card.Fingerprint(ctx)
	if err != nil {
		markRackCardUnreachable(ats, err)
		r.markUnobserved(ats, "Unreachable", err.Error())
		return ctrl.Result{RequeueAfter: rackATSRetryInterval}, nil
	}
	ats.Status.Reachable = true
	pinned := string(secret.Data[rackCardKeyFingerprint])
	if presented != "" {
		blocked, err := pinRackCardCertificate(ctx, r.Client, r.Recorder, ats, secret, presented)
		if err != nil || blocked {
			r.markUnobserved(ats, "CertificateChanged", ats.Status.Message)
			return ctrl.Result{RequeueAfter: rackATSRetryInterval}, err
		}
	}

	// A Secret recording other passwords than the derived ones is a card an
	// earlier build or root key set, and a certificate pinned anew (an
	// accepted one) may be a card reset to its factory state: adopting moves
	// either onto the derived passwords and the spec.
	var convergeErr error
	adopting := false
	if !rackCardCredentialsCurrent(secret, passwords) || pinned != string(secret.Data[rackCardKeyFingerprint]) ||
		((!ats.Status.Adopted || ats.Status.ObservedGeneration != ats.Generation) &&
			!rackCardAdoptedPastCache(ctx, r.APIReader, r.Client, ats, &infrav1.RackATS{})) {
		adopting = true
		if wait := r.adminBackoff.wait(ats); wait > 0 {
			convergeErr = fmt.Errorf("the administrator's login is held off for %s after the card refused it", wait.Round(time.Second))
		} else {
			res, done, err := r.adopt(ctx, ats, card)
			if done {
				return res, nil
			}
			convergeErr = err
		}
	}
	res, refused := r.observe(ctx, ats, card)
	if refused && !adopting && r.adminBackoff.wait(ats) == 0 {
		// The controller's account no longer takes its password: a card reset
		// to its factory state, or an account changed by hand. Adopting again
		// remakes it, under the administrator's login backoff.
		adopted, done, err := r.adopt(ctx, ats, card)
		if done {
			return adopted, nil
		}
		if err == nil {
			res, _ = r.observe(ctx, ats, card)
		} else if !cardLoginRefused(err) {
			r.adminBackoff.refused(ats)
		}
	}
	if convergeErr != nil {
		ats.Status.Message = fmt.Sprintf("generation %d did not converge: %v", ats.Generation, convergeErr)
		conditions.MarkFalse(ats, RackCardConvergedCondition, atsReason(convergeErr, "ConvergeFailed"), clusterv1.ConditionSeverityWarning, "%s", ats.Status.Message)
	}
	return res, nil
}

// adopt converges the card to the spec. It reports done when the pass ends
// here rather than going on to observe: an adopted switch whose new
// generation failed to converge is still observed, and tried again at the
// next observation.
func (r *RackATSReconciler) adopt(ctx context.Context, ats *infrav1.RackATS, card atsCard) (ctrl.Result, bool, error) {
	adoption, err := card.Adopt(ctx, int(ats.Spec.PreferredSource))
	if err != nil {
		reason := atsReason(err, "ConvergeFailed")
		if reason == rackATSReasonUnsupported {
			return ctrl.Result{RequeueAfter: r.markUnsupported(ats, err)}, true, nil
		}
		r.Recorder.Eventf(ats, corev1.EventTypeWarning, reason, "%v", err)
		refused := cardLoginRefused(err)
		if ats.Status.Adopted {
			// Observation goes on as the controller's account; only the
			// administrator's logins are held off.
			if refused {
				r.adminBackoff.refused(ats)
			}
			return ctrl.Result{}, false, err
		}
		ats.Status.Drift = infrav1.RackCardDriftUnknown
		conditions.MarkFalse(ats, RackCardConvergedCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		markRackCardNotAdopted(ats, reason, err)
		r.markUnobserved(ats, reason, err.Error())
		retry := rackATSRetryInterval
		if refused {
			retry = r.loginBackoff.refused(ats)
		}
		return ctrl.Result{RequeueAfter: retry}, true, nil
	}
	r.loginBackoff.succeeded(ats)
	if adoption.RotationNotApplied != nil {
		// Observed on the password that works; each try at moving it is a
		// refused derived login, so the next waits out a growing backoff.
		defer markRackCardRotationNotApplied(ats, adoption.RotationNotApplied)
		r.adminBackoff.refused(ats)
	} else {
		r.adminBackoff.succeeded(ats)
	}

	if adoption.PreferredUnrecognised == "" {
		markRackCardConverged(r.Recorder, ats)
		return ctrl.Result{}, false, nil
	}
	now := metav1.Now()
	ats.Status.Adopted = true
	ats.Status.ObservedGeneration = ats.Generation
	ats.Status.Drift = infrav1.RackCardDriftUnknown
	ats.Status.LastVerified = &now
	conditions.MarkTrue(ats, RackCardAdoptedCondition)
	r.Recorder.Eventf(ats, corev1.EventTypeWarning, "PreferredSourceUnrecognised",
		"Adopted generation %d, but could not set the preferred source to %d: %s", ats.Generation, ats.Spec.PreferredSource, adoption.PreferredUnrecognised)
	return ctrl.Result{}, false, nil
}

// observe reads the switch as the controller's account: which source powers
// the load, each source's state, and the preferred source, which is reported
// when it drifts and not written over. It reports whether the card refused the
// account's password, which only adopting the card again can mend.
func (r *RackATSReconciler) observe(ctx context.Context, ats *infrav1.RackATS, card atsCard) (ctrl.Result, bool) {
	obs, err := card.Observe(ctx)
	now := metav1.Now()
	ats.Status.LastVerified = &now
	if err != nil {
		reason := atsReason(err, "ObservationFailed")
		if reason == rackATSReasonUnsupported {
			return ctrl.Result{RequeueAfter: r.markUnsupported(ats, err)}, false
		}
		ats.Status.Drift = infrav1.RackCardDriftUnknown
		ats.Status.Message = fmt.Sprintf("the controller's account cannot read the transfer switch: %v", err)
		conditions.MarkFalse(ats, clusterv1.ReadyCondition, reason, clusterv1.ConditionSeverityWarning, "%s", ats.Status.Message)
		conditions.MarkUnknown(ats, RackCardConvergedCondition, reason, "%s", ats.Status.Message)
		r.markUnobserved(ats, reason, ats.Status.Message)
		retry := rackATSRetryInterval
		if cardLoginRefused(err) {
			retry = r.loginBackoff.refused(ats)
		}
		return ctrl.Result{RequeueAfter: retry}, loginPasswordRefused(err)
	}
	r.loginBackoff.succeeded(ats)

	previous, observedBefore := ats.Status.ActiveSource, ats.Status.LastObserved != nil
	ats.Status.Card = obs.Card
	ats.Status.Model, ats.Status.SerialNumber, ats.Status.FirmwareVersion = obs.CardModel, obs.CardSerial, obs.CardFirmware
	ats.Status.DeviceModel, ats.Status.DeviceSerialNumber, ats.Status.DeviceFirmwareVersion = obs.DeviceModel, obs.DeviceSerial, obs.DeviceFirmware
	ats.Status.PreferredSource = obs.Preferred
	ats.Status.Inputs = obs.Inputs
	ats.Status.LastObserved = &now
	if obs.ActiveUnrecognised == "" {
		ats.Status.ActiveSource = obs.Active
		if observedBefore {
			r.recordTransfer(ats, previous, obs, now)
		}
		r.markRedundancy(ats, obs)
	} else {
		// The inputs were read; which one powers the load was not, so neither
		// it nor redundancy is claimed.
		r.markUnobserved(ats, "ActiveSourceUnrecognised", "the card does not say which source powers the load: "+obs.ActiveUnrecognised)
	}
	conditions.MarkTrue(ats, clusterv1.ReadyCondition)

	switch {
	case obs.Preferred == 0:
		ats.Status.Drift = infrav1.RackCardDriftUnknown
		ats.Status.Message = obs.PreferredDetail
		conditions.MarkFalse(ats, RackCardConvergedCondition, "PreferredSourceUnrecognised", clusterv1.ConditionSeverityWarning, "%s", obs.PreferredDetail)
	case obs.Preferred != ats.Spec.PreferredSource:
		markRackCardDrift(r.Recorder, ats, fmt.Sprintf("the preferred source is %d, not %d", obs.Preferred, ats.Spec.PreferredSource))
	default:
		ats.Status.Drift = infrav1.RackCardDriftNone
		ats.Status.Message = "converged"
		conditions.MarkTrue(ats, RackCardConvergedCondition)
	}
	return ctrl.Result{RequeueAfter: rackATSObserveInterval}, false
}

// recordTransfer notes a change of the source powering the load, with an
// event, and a load neither source powers.
//
// Every change of the active source between two reads is recorded the same
// way, in status.lastTransfer and the counter, with 0 for neither source: a
// transfer between the sources, the load losing power (to 0) and the load
// coming back (from 0). Only the event tells them apart.
func (r *RackATSReconciler) recordTransfer(ats *infrav1.RackATS, previous int32, obs atsObservation, now metav1.Time) {
	if obs.Active == previous {
		return
	}
	ats.Status.LastTransfer = &infrav1.RackATSTransfer{From: previous, To: obs.Active, ObservedAt: now}
	rackATSTransfers.WithLabelValues(ats.Name, ats.Spec.Site, fmt.Sprint(previous), fmt.Sprint(obs.Active)).Inc()
	inputs := describeRackATSInputs(obs.Inputs)
	kind := corev1.EventTypeWarning
	if obs.Active == ats.Spec.PreferredSource {
		kind = corev1.EventTypeNormal
	}
	switch {
	case obs.Active == 0:
		r.Recorder.Eventf(ats, corev1.EventTypeWarning, "LoadNotPowered", "Neither source powers the load; it was on source %d. %s", previous, inputs)
	case previous == 0:
		r.Recorder.Eventf(ats, kind, "LoadRestored", "The load is powered again, from source %d, after neither source powered it. %s", obs.Active, inputs)
	default:
		r.Recorder.Eventf(ats, kind, "Transferred", "The load moved from source %d to source %d. %s", previous, obs.Active, inputs)
	}
}

// markRedundancy sets Redundant: whether the source not powering the load is
// good, so the switch could take the load to it.
func (r *RackATSReconciler) markRedundancy(ats *infrav1.RackATS, obs atsObservation) {
	was := conditions.Get(ats, RackATSRedundantCondition)
	var reason, message string
	switch {
	case obs.Active == 0:
		reason, message = "LoadNotPowered", "neither source powers the load. "+describeRackATSInputs(obs.Inputs)
	default:
		alternate := rackATSInput(obs.Inputs, 3-obs.Active)
		if alternate == nil || alternate.State != infrav1.RackATSInputGood {
			state := infrav1.RackATSInputUnknown
			if alternate != nil {
				state = alternate.State
			}
			reason = "AlternateSourceNotGood"
			message = fmt.Sprintf("source %d, which the load would move to, is %s: losing source %d drops the load. %s",
				3-obs.Active, state, obs.Active, describeRackATSInputs(obs.Inputs))
		}
	}
	if reason == "" {
		if was != nil && was.Status == corev1.ConditionFalse {
			r.Recorder.Eventf(ats, corev1.EventTypeNormal, "RedundancyRestored", "Both sources are good again; the load is on source %d", obs.Active)
		}
		conditions.MarkTrue(ats, RackATSRedundantCondition)
		return
	}
	if was == nil || was.Status != corev1.ConditionFalse {
		r.Recorder.Eventf(ats, corev1.EventTypeWarning, "RedundancyLost", "%s", message)
	}
	conditions.MarkFalse(ats, RackATSRedundantCondition, reason, clusterv1.ConditionSeverityError, "%s", message)
}

// markUnobserved says the sources are not known right now, so nothing reads
// a stale observation as current.
func (r *RackATSReconciler) markUnobserved(ats *infrav1.RackATS, reason, message string) {
	conditions.MarkUnknown(ats, RackATSRedundantCondition, reason, "%s", message)
}

// markUnsupported reports a card that answered in a way the controller does
// not recognise, with what it answered.
// An adopted card that answers so is not unadopted: it is reported as
// UnexpectedResponse, which a card briefly serving something else (a restart,
// an upgrade) clears on its own. It returns when to look again.
func (r *RackATSReconciler) markUnsupported(ats *infrav1.RackATS, err error) time.Duration {
	if ats.Status.Adopted {
		if conditions.GetReason(ats, clusterv1.ReadyCondition) != "UnexpectedResponse" {
			r.Recorder.Eventf(ats, corev1.EventTypeWarning, "UnexpectedResponse", "The adopted card answered unlike its API: %v", err)
		}
		markRackCardUnexpected(ats, err)
		r.markUnobserved(ats, "UnexpectedResponse", ats.Status.Message)
		return rackATSRetryInterval
	}
	message := fmt.Sprintf("the card at %s is not one the controller can drive: %v", ats.Spec.Address, err)
	if cond := conditions.Get(ats, RackCardAdoptedCondition); cond == nil || cond.Reason != rackATSReasonUnsupported {
		r.Recorder.Eventf(ats, corev1.EventTypeWarning, rackATSReasonUnsupported, "%s", message)
	}
	ats.Status.Message = message
	ats.Status.Drift = infrav1.RackCardDriftUnknown
	ats.Status.Adopted = false
	conditions.MarkFalse(ats, RackCardAdoptedCondition, rackATSReasonUnsupported, clusterv1.ConditionSeverityError, "%s", message)
	conditions.MarkFalse(ats, clusterv1.ReadyCondition, rackATSReasonUnsupported, clusterv1.ConditionSeverityError, "%s", message)
	r.markUnobserved(ats, rackATSReasonUnsupported, message)
	return rackATSUnsupportedInterval
}

func (r *RackATSReconciler) card(ats *infrav1.RackATS, secret *corev1.Secret, passwords rackcard.Passwords) atsCard {
	if r.Card != nil {
		return r.Card(r, ats, secret, passwords)
	}
	return &eatonATSCard{r: r, ats: ats, secret: secret, passwords: passwords}
}

// logOut ends the controller's session on the transfer switch's card.
func (r *RackATSReconciler) logOut(ctx context.Context, ats *infrav1.RackATS) {
	rackCardLogOut(ctx, r.Recorder, r.Power, ats, rackATSHost(ats), rackATSEgress(ats).host(r.egressConfig()))
}

// rackATSEgress is the egress Service fronting one RackATS's card.
func rackATSEgress(ats *infrav1.RackATS) rackCardEgressService {
	return rackCardEgressService{
		Name: "rackats-" + ats.Name, Component: "rack-ats-egress",
		LabelKey: "tuist.dev/rack-ats", Owner: ats.Name, Address: ats.Spec.Address,
	}
}

func (r *RackATSReconciler) timeout() time.Duration {
	if r.Timeout > 0 {
		return r.Timeout
	}
	return 15 * time.Second
}

func (r *RackATSReconciler) egressConfig() egressConfig {
	return egressConfig{Namespace: r.EgressNamespace, ProxyGroup: r.EgressProxyGroup, ManagedBy: operatorName}
}

// rackATSEvents lets through what the controller acts on: a new generation, an
// annotation (accept-certificate), and deletion. Its own status writes do not
// start another pass; the observation interval does.
var rackATSEvents = predicate.Or(
	predicate.GenerationChangedPredicate{},
	predicate.AnnotationChangedPredicate{},
	predicate.Funcs{UpdateFunc: func(e event.UpdateEvent) bool {
		return e.ObjectNew != nil && !e.ObjectNew.GetDeletionTimestamp().IsZero()
	}},
)

func (r *RackATSReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackATS{}, builder.WithPredicates(rackATSEvents)).
		WithOptions(controller.Options{MaxConcurrentReconciles: 1}).
		Complete(r)
}

func rackATSInput(inputs []infrav1.RackATSInput, source int32) *infrav1.RackATSInput {
	for i := range inputs {
		if inputs[i].Source == source {
			return &inputs[i]
		}
	}
	return nil
}

func describeRackATSInputs(inputs []infrav1.RackATSInput) string {
	out := ""
	for _, in := range inputs {
		if out != "" {
			out += "; "
		}
		out += fmt.Sprintf("source %d is %s", in.Source, in.State)
		if in.Voltage != "" && in.State != infrav1.RackATSInputMissing {
			out += " at " + in.Voltage + " V"
		}
	}
	return out
}
