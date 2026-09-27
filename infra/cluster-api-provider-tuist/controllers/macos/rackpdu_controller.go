package macos

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

const (
	RackPDUAdoptedCondition            = RackCardAdoptedCondition
	RackPDUConvergedCondition          = RackCardConvergedCondition
	RackPDUCertificateChangedCondition = RackCardCertificateChangedCondition
	RackPDUAddressReservedCondition    = RackCardAddressReservedCondition

	// RackPDUFinalizer holds a RackPDU until its egress Service, in another
	// namespace, is deleted.
	RackPDUFinalizer = "tuist.dev/rackpdu-egress"

	rackPDUResyncInterval = 10 * time.Minute
	rackPDURetryInterval  = time.Minute

	// The controller's account switches outlets in the card's "operators"
	// profile: the least predefined one with role-power-manager.
	rackPDUControllerProfile = "operators"
)

// rackPDUHost is the card's endpoint; tests point it at a fake card.
var rackPDUHost = func(pdu *infrav1.RackPDU) string {
	return "https://" + pdu.Spec.Address
}

// RackPDUReconciler adopts each controller-managed RackPDU's card and keeps it
// configured: it records the card's certificate at first contact and pins it,
// generates and owns the card's credentials, sets the administrator password,
// accepts the licence agreement, creates the controller's own account and
// sets every outlet's startup state. Between generations it only reads, and
// reports drift.
type RackPDUReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder

	// Power holds the eaton driver, whose session of the controller's account
	// the RackHost power paths share.
	Power *power.Registry

	// EgressNamespace and EgressProxyGroup, when both set, put an egress
	// Service in front of each card, which every power path dials.
	EgressNamespace  string
	EgressProxyGroup string

	// Timeout bounds each request to a card. Zero means 15 seconds.
	Timeout time.Duration
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackpdus,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackpdus/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackpdus/finalizers,verbs=update

func (r *RackPDUReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	pdu := &infrav1.RackPDU{}
	if getErr := r.Get(ctx, req.NamespacedName, pdu); getErr != nil {
		return ctrl.Result{}, client.IgnoreNotFound(getErr)
	}
	helper, helperErr := patch.NewHelper(pdu, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := helper.Patch(ctx, pdu); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	if !pdu.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, rackPDUEgress(pdu).release(ctx, r.Client, r.egressConfig(), pdu, RackPDUFinalizer)
	}
	if pdu.Spec.ManagedBy != infrav1.RackCardManagedByController {
		pdu.Status.Message = "standalone: the controller does not contact this PDU"
		pdu.Status.Drift = infrav1.RackCardDriftUnknown
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, "Standalone", clusterv1.ConditionSeverityInfo,
			"managedBy is standalone: the controller does not contact this PDU, and no power goes through it")
		return ctrl.Result{}, nil
	}

	if r.egressConfig().enabled() {
		controllerutil.AddFinalizer(pdu, RackPDUFinalizer)
		if err := rackPDUEgress(pdu).reconcile(ctx, r.Client, r.egressConfig()); err != nil {
			return ctrl.Result{}, err
		}
	}

	secret, err := r.ensureSecret(ctx, pdu)
	if err != nil {
		return ctrl.Result{}, err
	}
	pdu.Status.CredentialsSecret = secret.Name
	markRackCardAddress(pdu, pdu.Spec.MAC, pdu.Spec.Address)

	return r.reconcileCard(ctx, pdu, secret)
}

func (r *RackPDUReconciler) reconcileCard(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) (ctrl.Result, error) {
	presented, err := power.ProbeTLSFingerprint(ctx, r.cardOutlet(pdu, secret), r.timeout())
	if err != nil {
		markRackCardUnreachable(pdu, err)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}, nil
	}
	pdu.Status.Reachable = true

	if blocked, err := pinRackCardCertificate(ctx, r.Client, r.Recorder, pdu, secret, presented); err != nil || blocked {
		return ctrl.Result{RequeueAfter: rackPDUResyncInterval}, err
	}

	if !pdu.Status.Adopted || pdu.Status.ObservedGeneration != pdu.Generation {
		return r.adopt(ctx, pdu, secret)
	}
	return r.verify(ctx, pdu, secret), nil
}

// adopt converges the card to the spec, as its administrator: every step
// reads first and writes only what differs, so a pass interrupted anywhere is
// finished by the next.
func (r *RackPDUReconciler) adopt(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	admin, how, err := openEatonAdmin(ctx, r.cardOutlet(pdu, secret), secret, r.timeout())
	if err != nil {
		markRackCardNotAdopted(pdu, eatonLoginReason(err), err)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}, nil
	}
	defer func() {
		if err := admin.Close(ctx); err != nil {
			logger.Error(err, "log the administrator out of the card")
		}
	}()
	r.Recorder.Eventf(pdu, corev1.EventTypeNormal, "LoggedIn", "Logged in as %s %s", rackCardFactoryUser, how)

	if err := r.converge(ctx, pdu, secret, admin); err != nil {
		pdu.Status.Message = err.Error()
		conditions.MarkFalse(pdu, RackPDUConvergedCondition, "ConvergeFailed", clusterv1.ConditionSeverityWarning, "%v", err)
		if !pdu.Status.Adopted {
			markRackCardNotAdopted(pdu, "ConvergeFailed", err)
		}
		r.Recorder.Eventf(pdu, corev1.EventTypeWarning, "ConvergeFailed", "%v", err)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}, nil
	}

	markRackCardConverged(r.Recorder, pdu)
	return ctrl.Result{RequeueAfter: rackPDUResyncInterval}, nil
}

func (r *RackPDUReconciler) converge(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret, admin *power.EatonSession) error {
	accounts, err := admin.Accounts(ctx)
	if err != nil {
		return fmt.Errorf("list the card's accounts: %w", err)
	}
	if err := acceptEatonAdminLicence(ctx, admin, accounts, secret); err != nil {
		return err
	}
	if err := ensureEatonControllerAccount(ctx, r.Recorder, pdu, admin, accounts, secret, rackPDUControllerProfile, func(ctx context.Context) error {
		eaton, err := eatonDriver(r.Power)
		if err != nil {
			return err
		}
		_, err = eaton.Identification(ctx, r.cardOutlet(pdu, secret))
		return err
	}); err != nil {
		return err
	}

	outlets, err := admin.OutletSettings(ctx)
	if err != nil {
		return fmt.Errorf("read the outlets' settings: %w", err)
	}
	for _, outlet := range outlets {
		if outlet.StateOnStartup == pdu.Spec.OutletStateOnStartup {
			continue
		}
		settings := outlet.Settings
		if settings == nil {
			settings = map[string]any{}
		}
		settings["stateOnStartup"] = pdu.Spec.OutletStateOnStartup
		if err := admin.SetOutletSettings(ctx, outlet.Number, settings); err != nil {
			return fmt.Errorf("set outlet %d to start %s: %w", outlet.Number, pdu.Spec.OutletStateOnStartup, err)
		}
	}
	if outlets, err = admin.OutletSettings(ctx); err != nil {
		return fmt.Errorf("read the outlets' settings back: %w", err)
	}
	if wrong := outletsNotStarting(outlets, pdu.Spec.OutletStateOnStartup); len(wrong) > 0 {
		return fmt.Errorf("outlets %s still do not start %s after being set", strings.Join(wrong, ", "), pdu.Spec.OutletStateOnStartup)
	}
	pdu.Status.OutletCount = len(outlets)

	identity, err := admin.Identification(ctx)
	if err != nil {
		return fmt.Errorf("read the card's identification: %w", err)
	}
	pdu.Status.Model, pdu.Status.SerialNumber, pdu.Status.FirmwareVersion = identity.Model, identity.Serial, identity.Firmware
	return nil
}

// verify reads the card as the controller's account, which the power paths
// use, and reports drift without writing.
func (r *RackPDUReconciler) verify(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) ctrl.Result {
	eaton, err := eatonDriver(r.Power)
	var outlets []power.EatonOutletSettings
	if err == nil {
		outlets, err = eaton.OutletSettings(ctx, r.cardOutlet(pdu, secret))
	}
	now := metav1.Now()
	pdu.Status.LastVerified = &now
	if err != nil {
		// Nothing on the card was read, so this says nothing about drift.
		reason := "ControllerLoginFailed"
		var refusal *power.EatonLoginError
		if !errors.As(err, &refusal) {
			reason = "Unreachable"
		}
		pdu.Status.Drift = infrav1.RackCardDriftUnknown
		pdu.Status.Message = fmt.Sprintf("the controller's account cannot read the card: %v", err)
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		conditions.MarkUnknown(pdu, RackPDUConvergedCondition, reason, "%s", pdu.Status.Message)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}
	}
	pdu.Status.OutletCount = len(outlets)
	if identity, err := eaton.Identification(ctx, r.cardOutlet(pdu, secret)); err == nil {
		pdu.Status.Model, pdu.Status.SerialNumber, pdu.Status.FirmwareVersion = identity.Model, identity.Serial, identity.Firmware
	}
	conditions.MarkTrue(pdu, clusterv1.ReadyCondition)
	if wrong := outletsNotStarting(outlets, pdu.Spec.OutletStateOnStartup); len(wrong) > 0 {
		markRackCardDrift(r.Recorder, pdu, fmt.Sprintf("outlets %s do not start %s", strings.Join(wrong, ", "), pdu.Spec.OutletStateOnStartup))
		return ctrl.Result{RequeueAfter: rackPDUResyncInterval}
	}
	pdu.Status.Drift = infrav1.RackCardDriftNone
	pdu.Status.Message = "converged"
	conditions.MarkTrue(pdu, RackPDUConvergedCondition)
	return ctrl.Result{RequeueAfter: rackPDUResyncInterval}
}

// cardOutlet is the card as the power paths reach it: its egress Service when
// configured, pinned to the Secret's fingerprint, as the controller's account.
func (r *RackPDUReconciler) cardOutlet(pdu *infrav1.RackPDU, secret *corev1.Secret) power.Outlet {
	return rackPDUOutlet(r.egressConfig(), pdu, secret)
}

// rackPDUOutlet is outlet 1 of a RackPDU as its controller's account reaches
// it; callers set the outlet.
func rackPDUOutlet(egress egressConfig, pdu *infrav1.RackPDU, secret *corev1.Secret) power.Outlet {
	return rackCardOutlet(rackPDUHost(pdu), rackPDUEgress(pdu).host(egress), secret)
}

// rackPDUEgress is the egress Service fronting one RackPDU's card.
func rackPDUEgress(pdu *infrav1.RackPDU) rackCardEgressService {
	return rackCardEgressService{
		Name: "rackpdu-" + pdu.Name, Component: "rack-pdu-egress",
		LabelKey: "tuist.dev/rack-pdu", Owner: pdu.Name, Address: pdu.Spec.Address,
	}
}

func rackPDUSecretName(pdu *infrav1.RackPDU) string {
	return rackCardSecretName(pdu.Name)
}

// ensureSecret makes the PDU's credentials Secret.
func (r *RackPDUReconciler) ensureSecret(ctx context.Context, pdu *infrav1.RackPDU) (*corev1.Secret, error) {
	return ensureRackCardSecret(ctx, r.Client, pdu, "tuist.dev/rack-pdu")
}

func (r *RackPDUReconciler) timeout() time.Duration {
	if r.Timeout > 0 {
		return r.Timeout
	}
	return 15 * time.Second
}

func (r *RackPDUReconciler) egressConfig() egressConfig {
	return egressConfig{Namespace: r.EgressNamespace, ProxyGroup: r.EgressProxyGroup, ManagedBy: operatorName}
}

func (r *RackPDUReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackPDU{}).
		WithOptions(controller.Options{MaxConcurrentReconciles: 1}).
		Complete(r)
}

func outletsNotStarting(outlets []power.EatonOutletSettings, state string) []string {
	var wrong []string
	for _, o := range outlets {
		if o.StateOnStartup != state {
			wrong = append(wrong, fmt.Sprintf("%d (%s)", o.Number, o.StateOnStartup))
		}
	}
	return wrong
}
