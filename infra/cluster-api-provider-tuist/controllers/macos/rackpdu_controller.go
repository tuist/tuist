package macos

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
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
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

const (
	RackPDUAdoptedCondition            clusterv1.ConditionType = "Adopted"
	RackPDUConvergedCondition          clusterv1.ConditionType = "Converged"
	RackPDUCertificateChangedCondition clusterv1.ConditionType = "CertificateChanged"
	RackPDUAddressReservedCondition    clusterv1.ConditionType = "AddressReserved"

	// AcceptCertificateAnnotation, set to the SHA-256 of the certificate a
	// card now presents, pins that certificate instead of the recorded one.
	// The controller clears it after acting.
	AcceptCertificateAnnotation = "tuist.dev/accept-certificate"

	// RackPDUFinalizer holds a RackPDU until its egress Service, in another
	// namespace, is deleted.
	RackPDUFinalizer = "tuist.dev/rackpdu-egress"

	rackPDUResyncInterval = 10 * time.Minute
	rackPDURetryInterval  = time.Minute

	// The card's factory login.
	rackPDUFactoryUser     = "admin"
	rackPDUFactoryPassword = "admin"
	// The account the controller switches outlets with, in the card's
	// "operators" profile: the least predefined one with role-power-manager.
	rackPDUControllerUser    = "tuist-controller"
	rackPDUControllerProfile = "operators"
)

// Keys of the Secret the controller generates for each RackPDU.
const (
	rackPDUKeyAdminUsername   = "admin-username"
	rackPDUKeyAdminPassword   = "admin-password"
	rackPDUKeyUsername        = "username"
	rackPDUKeyPassword        = "password"
	rackPDUKeyInitialPassword = "initial-password"
	rackPDUKeyFingerprint     = "tlsFingerprint"
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

	// APIReader reads the RackPDU past the manager's cache before adopting,
	// so a cache that has not seen the last pass's status yet does not start
	// another. Nil reads through Client.
	APIReader client.Reader
}

// rackPDUPredicate wakes the reconciler for a new generation and for an
// annotation (tuist.dev/accept-certificate), not for its own status writes,
// which would otherwise read the card again after every pass.
func rackPDUPredicate() predicate.Predicate {
	return predicate.Or(predicate.GenerationChangedPredicate{}, predicate.AnnotationChangedPredicate{})
}

// adoptedAlready reports whether the API server records this generation as
// adopted, when the object read from the cache does not: the manager's cache
// can lag the status the last pass wrote, and adopting again would log the
// administrator in twice for one generation.
func (r *RackPDUReconciler) adoptedAlready(ctx context.Context, pdu *infrav1.RackPDU) bool {
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	fresh := &infrav1.RackPDU{}
	if err := reader.Get(ctx, client.ObjectKeyFromObject(pdu), fresh); err != nil {
		return false
	}
	if fresh.Generation != pdu.Generation || !fresh.Status.Adopted || fresh.Status.ObservedGeneration != pdu.Generation {
		return false
	}
	pdu.Status.Adopted = true
	pdu.Status.ObservedGeneration = fresh.Status.ObservedGeneration
	pdu.Status.Drift = fresh.Status.Drift
	return true
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackpdus,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackpdus/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackpdus/finalizers,verbs=update

func (r *RackPDUReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	pdu := &infrav1.RackPDU{}
	if getErr := r.Get(ctx, req.NamespacedName, pdu); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			forgetRackPDUMetrics(req.Name)
		}
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
	defer func() { recordRackPDUMetrics(pdu) }()

	if !pdu.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, r.reconcileDelete(ctx, pdu)
	}
	if pdu.Spec.ManagedBy != infrav1.RackPDUManagedByController {
		pdu.Status.Message = "standalone: the controller does not contact this PDU"
		pdu.Status.Drift = infrav1.RackPDUDriftUnknown
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, "Standalone", clusterv1.ConditionSeverityInfo,
			"managedBy is standalone: the controller does not contact this PDU, and no power goes through it")
		return ctrl.Result{}, nil
	}

	if r.egressConfig().enabled() {
		controllerutil.AddFinalizer(pdu, RackPDUFinalizer)
		if err := reconcileRackPDUEgressService(ctx, r.Client, r.egressConfig(), pdu); err != nil {
			return ctrl.Result{}, err
		}
	}

	secret, err := r.ensureSecret(ctx, pdu)
	if err != nil {
		return ctrl.Result{}, err
	}
	pdu.Status.CredentialsSecret = secret.Name

	if pdu.Spec.MAC == "" {
		conditions.MarkFalse(pdu, RackPDUAddressReservedCondition, "NoMAC", clusterv1.ConditionSeverityWarning,
			"spec.mac is empty, so the rack's edge reserves no address for the card: a factory card takes a provisioning address and is not found at %s until its MAC is recorded in the site definition", pdu.Spec.Address)
	} else {
		conditions.MarkTrue(pdu, RackPDUAddressReservedCondition)
	}

	return r.reconcileCard(ctx, pdu, secret)
}

func (r *RackPDUReconciler) reconcileCard(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) (ctrl.Result, error) {
	presented, err := power.ProbeTLSFingerprint(ctx, r.cardOutlet(pdu, secret, "", ""), r.timeout())
	if err != nil {
		pdu.Status.Reachable = false
		pdu.Status.Drift = infrav1.RackPDUDriftUnknown
		pdu.Status.Message = err.Error()
		if !pdu.Status.Adopted {
			conditions.MarkFalse(pdu, RackPDUAdoptedCondition, "Unreachable", clusterv1.ConditionSeverityWarning, "%v", err)
		}
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, "Unreachable", clusterv1.ConditionSeverityWarning, "%v", err)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}, nil
	}
	pdu.Status.Reachable = true

	if blocked, err := r.pinCertificate(ctx, pdu, secret, presented); err != nil || blocked {
		return ctrl.Result{RequeueAfter: rackPDUResyncInterval}, err
	}

	if (!pdu.Status.Adopted || pdu.Status.ObservedGeneration != pdu.Generation) && !r.adoptedAlready(ctx, pdu) {
		return r.adopt(ctx, pdu, secret)
	}
	return r.verify(ctx, pdu, secret), nil
}

// pinCertificate records the certificate at first contact, honours an
// accept-certificate annotation, and reports whether a changed certificate
// blocks every write.
func (r *RackPDUReconciler) pinCertificate(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret, presented string) (bool, error) {
	pinned := string(secret.Data[rackPDUKeyFingerprint])
	if accepted, ok := pdu.Annotations[AcceptCertificateAnnotation]; ok {
		delete(pdu.Annotations, AcceptCertificateAnnotation)
		if power.SameTLSFingerprint(accepted, presented) {
			pinned = ""
			r.Recorder.Eventf(pdu, corev1.EventTypeNormal, "CertificateAccepted", "Pinned the certificate the card presents, %s", presented)
		} else {
			r.Recorder.Eventf(pdu, corev1.EventTypeWarning, "CertificateNotAccepted",
				"%s names %s, but the card presents %s; nothing changed", AcceptCertificateAnnotation, accepted, presented)
		}
	}
	if pinned == "" {
		secret.Data[rackPDUKeyFingerprint] = []byte(presented)
		if err := r.Update(ctx, secret); err != nil {
			return true, fmt.Errorf("record the card's certificate in %s: %w", secret.Name, err)
		}
		pinned = presented
		r.Recorder.Eventf(pdu, corev1.EventTypeNormal, "CertificateRecorded", "Pinned the card's certificate, %s", presented)
	}
	pdu.Status.TLSFingerprint = pinned

	if !power.SameTLSFingerprint(pinned, presented) {
		if !conditions.IsTrue(pdu, RackPDUCertificateChangedCondition) {
			r.Recorder.Eventf(pdu, corev1.EventTypeWarning, "CertificateChanged",
				"The card presents %s, not the pinned %s; nothing is written to it until %s names the new one", presented, pinned, AcceptCertificateAnnotation)
		}
		pdu.Status.PresentedFingerprint = presented
		pdu.Status.Message = fmt.Sprintf("the card presents certificate %s, not the pinned %s: a replaced or factory-reset card, or something else at its address. Annotate %s=%s to pin it", presented, pinned, AcceptCertificateAnnotation, presented)
		conditions.Set(pdu, &clusterv1.Condition{
			Type: RackPDUCertificateChangedCondition, Status: corev1.ConditionTrue,
			Reason: "Changed", Severity: clusterv1.ConditionSeverityError, Message: pdu.Status.Message,
		})
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, "CertificateChanged", clusterv1.ConditionSeverityError, "%s", pdu.Status.Message)
		return true, nil
	}
	pdu.Status.PresentedFingerprint = ""
	conditions.Set(pdu, &clusterv1.Condition{Type: RackPDUCertificateChangedCondition, Status: corev1.ConditionFalse, Reason: "Pinned"})
	return false, nil
}

// adopt converges the card to the spec, as its administrator: every step
// reads first and writes only what differs, so a pass interrupted anywhere is
// finished by the next.
func (r *RackPDUReconciler) adopt(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	admin, how, err := r.openAdmin(ctx, pdu, secret)
	if err != nil {
		reason := rackPDULoginReason(err)
		pdu.Status.Message = err.Error()
		conditions.MarkFalse(pdu, RackPDUAdoptedCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}, nil
	}
	defer func() {
		if err := admin.Close(ctx); err != nil {
			logger.Error(err, "log the administrator out of the card")
		}
	}()
	r.Recorder.Eventf(pdu, corev1.EventTypeNormal, "LoggedIn", "Logged in as %s %s", rackPDUFactoryUser, how)

	if err := r.converge(ctx, pdu, secret, admin); err != nil {
		pdu.Status.Message = err.Error()
		conditions.MarkFalse(pdu, RackPDUConvergedCondition, "ConvergeFailed", clusterv1.ConditionSeverityWarning, "%v", err)
		if !pdu.Status.Adopted {
			conditions.MarkFalse(pdu, RackPDUAdoptedCondition, "ConvergeFailed", clusterv1.ConditionSeverityWarning, "%v", err)
			conditions.MarkFalse(pdu, clusterv1.ReadyCondition, "ConvergeFailed", clusterv1.ConditionSeverityWarning, "%v", err)
		}
		r.Recorder.Eventf(pdu, corev1.EventTypeWarning, "ConvergeFailed", "%v", err)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}, nil
	}

	now := metav1.Now()
	pdu.Status.Adopted = true
	pdu.Status.ObservedGeneration = pdu.Generation
	pdu.Status.Drift = infrav1.RackPDUDriftNone
	pdu.Status.LastVerified = &now
	pdu.Status.Message = "adopted and converged"
	conditions.MarkTrue(pdu, RackPDUAdoptedCondition)
	conditions.MarkTrue(pdu, RackPDUConvergedCondition)
	conditions.MarkTrue(pdu, clusterv1.ReadyCondition)
	r.Recorder.Eventf(pdu, corev1.EventTypeNormal, "Converged", "Converged generation %d", pdu.Generation)
	return ctrl.Result{RequeueAfter: rackPDUResyncInterval}, nil
}

func (r *RackPDUReconciler) converge(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret, admin *power.EatonSession) error {
	accounts, err := admin.Accounts(ctx)
	if err != nil {
		return fmt.Errorf("list the card's accounts: %w", err)
	}
	adminAccount := findEatonAccount(accounts, string(secret.Data[rackPDUKeyAdminUsername]))
	if adminAccount == nil {
		return fmt.Errorf("the card lists no %s account", secret.Data[rackPDUKeyAdminUsername])
	}
	if adminAccount.Licence != "accepted" {
		if err := admin.AcceptLicence(ctx, adminAccount.ID); err != nil {
			return fmt.Errorf("accept the licence agreement for %s: %w", adminAccount.Name, err)
		}
	}

	if err := r.ensureControllerAccount(ctx, pdu, secret, admin, accounts); err != nil {
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

// ensureControllerAccount makes the controller's account exist, unlocked, in
// its profile, with the licence accepted, and able to log in with the Secret's
// password; an account that cannot is made again.
func (r *RackPDUReconciler) ensureControllerAccount(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret, admin *power.EatonSession, accounts []power.EatonAccount) error {
	username := string(secret.Data[rackPDUKeyUsername])
	profiles, err := admin.Profiles(ctx)
	if err != nil {
		return fmt.Errorf("list the card's profiles: %w", err)
	}
	var profile *power.EatonProfile
	for i := range profiles {
		if profiles[i].Name == rackPDUControllerProfile {
			profile = &profiles[i]
		}
	}
	if profile == nil {
		return fmt.Errorf("the card has no %q profile", rackPDUControllerProfile)
	}

	account := findEatonAccount(accounts, username)
	if account != nil && account.Profile != profile.Ref {
		if err := admin.DeleteAccount(ctx, account.ID); err != nil {
			return fmt.Errorf("remove %s, which is not in %s: %w", username, rackPDUControllerProfile, err)
		}
		account = nil
	}
	for attempt := 0; ; attempt++ {
		if account == nil {
			created, err := admin.CreateAccount(ctx, username, profile.Ref, string(secret.Data[rackPDUKeyInitialPassword]), "Tuist controller")
			if err != nil {
				return fmt.Errorf("create the controller's account %s: %w", username, err)
			}
			account = &created
			r.Recorder.Eventf(pdu, corev1.EventTypeNormal, "AccountCreated", "Created %s in %s", username, rackPDUControllerProfile)
		}
		if account.Locked {
			if err := admin.UnlockAccount(ctx, account.ID); err != nil {
				return fmt.Errorf("unlock %s: %w", username, err)
			}
		}
		if account.Licence != "accepted" {
			if err := admin.AcceptLicence(ctx, account.ID); err != nil {
				return fmt.Errorf("accept the licence agreement for %s: %w", username, err)
			}
		}

		eaton, err := r.eaton()
		if err != nil {
			return err
		}
		_, err = eaton.Identification(ctx, r.cardOutlet(pdu, secret, "", ""))
		var refused *power.EatonLoginError
		if err == nil {
			return nil
		}
		if attempt > 0 || !errors.As(err, &refused) || !refused.Refused() {
			return fmt.Errorf("log in as %s: %w", username, err)
		}
		if err := admin.DeleteAccount(ctx, account.ID); err != nil {
			return fmt.Errorf("remove %s, which does not take the Secret's password: %w", username, err)
		}
		r.Recorder.Eventf(pdu, corev1.EventTypeWarning, "AccountRecreated", "%s did not take the Secret's password; making it again", username)
		account = nil
	}
}

// verify reads the card as the controller's account, which the power paths
// use, and reports drift without writing.
func (r *RackPDUReconciler) verify(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) ctrl.Result {
	eaton, err := r.eaton()
	var outlets []power.EatonOutletSettings
	if err == nil {
		outlets, err = eaton.OutletSettings(ctx, r.cardOutlet(pdu, secret, "", ""))
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
		pdu.Status.Drift = infrav1.RackPDUDriftUnknown
		pdu.Status.Message = fmt.Sprintf("the controller's account cannot read the card: %v", err)
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
		conditions.MarkUnknown(pdu, RackPDUConvergedCondition, reason, "%s", pdu.Status.Message)
		return ctrl.Result{RequeueAfter: rackPDURetryInterval}
	}
	pdu.Status.OutletCount = len(outlets)
	if identity, err := eaton.Identification(ctx, r.cardOutlet(pdu, secret, "", "")); err == nil {
		pdu.Status.Model, pdu.Status.SerialNumber, pdu.Status.FirmwareVersion = identity.Model, identity.Serial, identity.Firmware
	}
	conditions.MarkTrue(pdu, clusterv1.ReadyCondition)
	if wrong := outletsNotStarting(outlets, pdu.Spec.OutletStateOnStartup); len(wrong) > 0 {
		r.markDrift(pdu, fmt.Sprintf("outlets %s do not start %s", strings.Join(wrong, ", "), pdu.Spec.OutletStateOnStartup))
		return ctrl.Result{RequeueAfter: rackPDUResyncInterval}
	}
	pdu.Status.Drift = infrav1.RackPDUDriftNone
	pdu.Status.Message = "converged"
	conditions.MarkTrue(pdu, RackPDUConvergedCondition)
	return ctrl.Result{RequeueAfter: rackPDUResyncInterval}
}

// markDrift reports drift, with one event when it starts. It is not written
// over: a new generation converges it.
func (r *RackPDUReconciler) markDrift(pdu *infrav1.RackPDU, detail string) {
	if pdu.Status.Drift != infrav1.RackPDUDriftDrifted {
		r.Recorder.Eventf(pdu, corev1.EventTypeWarning, "Drifted", "%s; not written over until the spec's next generation", detail)
	}
	pdu.Status.Drift = infrav1.RackPDUDriftDrifted
	pdu.Status.Message = detail
	conditions.MarkFalse(pdu, RackPDUConvergedCondition, "Drifted", clusterv1.ConditionSeverityWarning, "%s", detail)
}

// openAdmin logs in as the card's administrator with the Secret's password,
// and otherwise with the factory login, setting the Secret's password in the
// same request. It names which.
func (r *RackPDUReconciler) openAdmin(ctx context.Context, pdu *infrav1.RackPDU, secret *corev1.Secret) (*power.EatonSession, string, error) {
	username := string(secret.Data[rackPDUKeyAdminUsername])
	managed := r.cardOutlet(pdu, secret, username, string(secret.Data[rackPDUKeyAdminPassword]))
	session, err := power.OpenEatonSession(ctx, managed, "", r.timeout())
	if err == nil {
		return session, "with the managed password", nil
	}
	var refused *power.EatonLoginError
	if !errors.As(err, &refused) || !refused.Refused() {
		return nil, "", err
	}
	factory := r.cardOutlet(pdu, secret, rackPDUFactoryUser, rackPDUFactoryPassword)
	session, factoryErr := power.OpenEatonSession(ctx, factory, string(secret.Data[rackPDUKeyAdminPassword]), r.timeout())
	if factoryErr == nil {
		return session, "with the factory login, and set the managed password", nil
	}
	return nil, "", fmt.Errorf("the managed password: %v; the factory login: %w", err, factoryErr)
}

// rackPDULoginReason names why the administrator could not log in.
func rackPDULoginReason(err error) string {
	var refusal *power.EatonLoginError
	switch {
	case errors.Is(err, power.ErrEatonConcurrentSession):
		return "AdminSessionBusy"
	case errors.As(err, &refusal) && refusal.Status == 401:
		return "AdminLoginRefused"
	case errors.As(err, &refusal):
		return "FirstLoginBlocked"
	}
	return "Unreachable"
}

// cardOutlet is the card as the power paths reach it: its egress Service when
// configured, pinned to the Secret's fingerprint, as the controller's account
// unless username is given.
func (r *RackPDUReconciler) cardOutlet(pdu *infrav1.RackPDU, secret *corev1.Secret, username, password string) power.Outlet {
	o := rackPDUOutlet(r.egressConfig(), pdu, secret)
	if username != "" {
		o.Username, o.Password, o.InitialPassword = username, password, ""
	}
	return o
}

// rackPDUOutlet is outlet 1 of a RackPDU as its controller's account reaches
// it; callers set the outlet.
func rackPDUOutlet(egress egressConfig, pdu *infrav1.RackPDU, secret *corev1.Secret) power.Outlet {
	o := power.Outlet{
		Driver:          power.DriverEaton,
		Host:            rackPDUHost(pdu),
		Outlet:          "1",
		Dial:            rackPDUEgressHost(egress, pdu.Name),
		Username:        string(secret.Data[rackPDUKeyUsername]),
		Password:        string(secret.Data[rackPDUKeyPassword]),
		InitialPassword: string(secret.Data[rackPDUKeyInitialPassword]),
		TLSFingerprint:  string(secret.Data[rackPDUKeyFingerprint]),
	}
	return o
}

func rackPDUSecretName(pdu *infrav1.RackPDU) string {
	return pdu.Name + "-credentials"
}

// ensureSecret makes the PDU's credentials Secret, generating what it lacks
// and never replacing what it has: it is written before any password reaches
// the card, so a pass that stops after changing one finds it here.
func (r *RackPDUReconciler) ensureSecret(ctx context.Context, pdu *infrav1.RackPDU) (*corev1.Secret, error) {
	secret := &corev1.Secret{}
	key := types.NamespacedName{Namespace: pdu.Namespace, Name: rackPDUSecretName(pdu)}
	err := r.Get(ctx, key, secret)
	create := apierrors.IsNotFound(err)
	if err != nil && !create {
		return nil, err
	}
	// Deliberately unowned: it holds the only copy of the passwords set on the
	// card, so deleting or recreating the RackPDU must not collect it, or the
	// card refuses every login until someone factory-resets it.
	if create {
		secret = &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace,
			Labels: map[string]string{"app.kubernetes.io/managed-by": operatorName, "tuist.dev/rack-pdu": pdu.Name}}}
	}
	if secret.Data == nil {
		secret.Data = map[string][]byte{}
	}
	changed := false
	owners := secret.OwnerReferences[:0]
	for _, ref := range secret.OwnerReferences {
		if ref.Kind == "RackPDU" {
			changed = true
			continue
		}
		owners = append(owners, ref)
	}
	secret.OwnerReferences = owners
	for k, value := range map[string]func() (string, error){
		rackPDUKeyAdminUsername:   func() (string, error) { return rackPDUFactoryUser, nil },
		rackPDUKeyAdminPassword:   generateCardPassword,
		rackPDUKeyUsername:        func() (string, error) { return rackPDUControllerUser, nil },
		rackPDUKeyPassword:        generateCardPassword,
		rackPDUKeyInitialPassword: generateCardPassword,
	} {
		if len(secret.Data[k]) > 0 {
			continue
		}
		v, err := value()
		if err != nil {
			return nil, err
		}
		secret.Data[k] = []byte(v)
		changed = true
	}
	switch {
	case create:
		if err := r.Create(ctx, secret); err != nil {
			return nil, fmt.Errorf("create %s: %w", key.Name, err)
		}
	case changed:
		if err := r.Update(ctx, secret); err != nil {
			return nil, fmt.Errorf("update %s: %w", key.Name, err)
		}
	}
	return secret, nil
}

// generateCardPassword makes a password the card's default policy accepts: 24
// characters with upper and lower case letters, digits and a special
// character.
func generateCardPassword() (string, error) {
	const (
		upper   = "ABCDEFGHJKLMNPQRSTUVWXYZ"
		lower   = "abcdefghijkmnopqrstuvwxyz"
		digits  = "23456789"
		special = "-_.+=!#%"
	)
	classes := []string{upper, lower, digits, special}
	all := upper + lower + digits
	out := make([]byte, 24)
	for i := range out {
		set := all
		if i < len(classes) {
			set = classes[i]
		}
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(set))))
		if err != nil {
			return "", err
		}
		out[i] = set[n.Int64()]
	}
	for i := len(out) - 1; i > 0; i-- {
		j, err := rand.Int(rand.Reader, big.NewInt(int64(i+1)))
		if err != nil {
			return "", err
		}
		out[i], out[j.Int64()] = out[j.Int64()], out[i]
	}
	return string(out), nil
}

func (r *RackPDUReconciler) reconcileDelete(ctx context.Context, pdu *infrav1.RackPDU) error {
	if !controllerutil.ContainsFinalizer(pdu, RackPDUFinalizer) {
		return nil
	}
	if cfg := r.egressConfig(); cfg.enabled() {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: rackPDUEgressServiceName(pdu.Name), Namespace: cfg.Namespace}}
		if err := r.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete egress Service %s: %w", svc.Name, err)
		}
	}
	controllerutil.RemoveFinalizer(pdu, RackPDUFinalizer)
	return nil
}

func (r *RackPDUReconciler) eaton() (*power.Eaton, error) {
	if r.Power == nil {
		return nil, fmt.Errorf("no power drivers wired into this operator build")
	}
	driver, err := r.Power.Get(power.DriverEaton)
	if err != nil {
		return nil, err
	}
	eaton, ok := driver.(*power.Eaton)
	if !ok {
		return nil, fmt.Errorf("the eaton driver is a %T", driver)
	}
	return eaton, nil
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
		For(&infrav1.RackPDU{}, builder.WithPredicates(rackPDUPredicate())).
		WithOptions(controller.Options{MaxConcurrentReconciles: 1}).
		Complete(r)
}

func findEatonAccount(accounts []power.EatonAccount, name string) *power.EatonAccount {
	for i := range accounts {
		if accounts[i].Name == name {
			return &accounts[i]
		}
	}
	return nil
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
