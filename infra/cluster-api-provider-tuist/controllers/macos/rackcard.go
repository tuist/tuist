package macos

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

// The lifecycle every rack power device's management card shares, whichever
// device it is in: a RackPDU or a RackATS. Each is adopted on its factory
// login, keeps an unowned credentials Secret written before first contact, is
// pinned to the certificate it presented first, and reports drift rather than
// writing over it between generations.

const (
	RackCardAdoptedCondition            clusterv1.ConditionType = "Adopted"
	RackCardConvergedCondition          clusterv1.ConditionType = "Converged"
	RackCardCertificateChangedCondition clusterv1.ConditionType = "CertificateChanged"
	RackCardAddressReservedCondition    clusterv1.ConditionType = "AddressReserved"

	// AcceptCertificateAnnotation, set to the SHA-256 of the certificate a
	// card now presents, pins that certificate instead of the recorded one.
	// The controller clears it after acting.
	AcceptCertificateAnnotation = "tuist.dev/accept-certificate"

	// The card's factory login.
	rackCardFactoryUser     = "admin"
	rackCardFactoryPassword = "admin"
	// The account the controller works as, which it makes on the card.
	rackCardControllerUser = "tuist-controller"
)

// Keys of the Secret the controller generates for each card.
const (
	rackCardKeyAdminUsername   = "admin-username"
	rackCardKeyAdminPassword   = "admin-password"
	rackCardKeyUsername        = "username"
	rackCardKeyPassword        = "password"
	rackCardKeyInitialPassword = "initial-password"
	rackCardKeyFingerprint     = "tlsFingerprint"
)

// rackCard is a rack power device's object.
type rackCard interface {
	client.Object
	conditions.Setter
	CardStatus() *infrav1.RackCardStatus
}

func rackCardSecretName(name string) string {
	return name + "-credentials"
}

// ensureRackCardSecret makes a card's credentials Secret, generating what it
// lacks and never replacing what it has: it is written before any password
// reaches the card, so a pass that stops after changing one finds it here.
// labelKey names the device kind, e.g. tuist.dev/rack-pdu.
func ensureRackCardSecret(ctx context.Context, c client.Client, obj client.Object, labelKey string) (*corev1.Secret, error) {
	secret := &corev1.Secret{}
	key := types.NamespacedName{Namespace: obj.GetNamespace(), Name: rackCardSecretName(obj.GetName())}
	err := c.Get(ctx, key, secret)
	create := apierrors.IsNotFound(err)
	if err != nil && !create {
		return nil, err
	}
	// Deliberately unowned: it holds the only copy of the passwords set on the
	// card, so deleting or recreating the object must not collect it, or the
	// card refuses every login until someone factory-resets it.
	if create {
		secret = &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace,
			Labels: map[string]string{"app.kubernetes.io/managed-by": operatorName, labelKey: obj.GetName()}}}
	}
	if secret.Data == nil {
		secret.Data = map[string][]byte{}
	}
	changed := false
	owners := secret.OwnerReferences[:0]
	for _, ref := range secret.OwnerReferences {
		if ref.Kind == "RackPDU" || ref.Kind == "RackATS" {
			changed = true
			continue
		}
		owners = append(owners, ref)
	}
	secret.OwnerReferences = owners
	for k, value := range map[string]func() (string, error){
		rackCardKeyAdminUsername:   func() (string, error) { return rackCardFactoryUser, nil },
		rackCardKeyAdminPassword:   generateCardPassword,
		rackCardKeyUsername:        func() (string, error) { return rackCardControllerUser, nil },
		rackCardKeyPassword:        generateCardPassword,
		rackCardKeyInitialPassword: generateCardPassword,
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
		if err := c.Create(ctx, secret); err != nil {
			return nil, fmt.Errorf("create %s: %w", key.Name, err)
		}
	case changed:
		if err := c.Update(ctx, secret); err != nil {
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

// markRackCardAddress reports whether the rack's edge reserves the card's
// address against its MAC.
func markRackCardAddress(obj rackCard, mac, address string) {
	if mac == "" {
		conditions.MarkFalse(obj, RackCardAddressReservedCondition, "NoMAC", clusterv1.ConditionSeverityWarning,
			"spec.mac is empty, so the rack's edge reserves no address for the card: a factory card takes a provisioning address and is not found at %s until its MAC is recorded in the site definition", address)
		return
	}
	conditions.MarkTrue(obj, RackCardAddressReservedCondition)
}

// markRackCardUnreachable reports a card that did not answer.
func markRackCardUnreachable(obj rackCard, err error) {
	status := obj.CardStatus()
	status.Reachable = false
	status.Drift = infrav1.RackCardDriftUnknown
	status.Message = err.Error()
	if !status.Adopted {
		conditions.MarkFalse(obj, RackCardAdoptedCondition, "Unreachable", clusterv1.ConditionSeverityWarning, "%v", err)
	}
	conditions.MarkFalse(obj, clusterv1.ReadyCondition, "Unreachable", clusterv1.ConditionSeverityWarning, "%v", err)
}

// pinRackCardCertificate records the certificate at first contact, honours an
// accept-certificate annotation, and reports whether a changed certificate
// blocks every write.
func pinRackCardCertificate(ctx context.Context, c client.Client, recorder record.EventRecorder, obj rackCard, secret *corev1.Secret, presented string) (bool, error) {
	status := obj.CardStatus()
	pinned := string(secret.Data[rackCardKeyFingerprint])
	annotations := obj.GetAnnotations()
	if accepted, ok := annotations[AcceptCertificateAnnotation]; ok {
		delete(annotations, AcceptCertificateAnnotation)
		obj.SetAnnotations(annotations)
		if power.SameTLSFingerprint(accepted, presented) {
			pinned = ""
			recorder.Eventf(obj, corev1.EventTypeNormal, "CertificateAccepted", "Pinned the certificate the card presents, %s", presented)
		} else {
			recorder.Eventf(obj, corev1.EventTypeWarning, "CertificateNotAccepted",
				"%s names %s, but the card presents %s; nothing changed", AcceptCertificateAnnotation, accepted, presented)
		}
	}
	if pinned == "" {
		secret.Data[rackCardKeyFingerprint] = []byte(presented)
		if err := c.Update(ctx, secret); err != nil {
			return true, fmt.Errorf("record the card's certificate in %s: %w", secret.Name, err)
		}
		pinned = presented
		recorder.Eventf(obj, corev1.EventTypeNormal, "CertificateRecorded", "Pinned the card's certificate, %s", presented)
	}
	status.TLSFingerprint = pinned

	if !power.SameTLSFingerprint(pinned, presented) {
		if !conditions.IsTrue(obj, RackCardCertificateChangedCondition) {
			recorder.Eventf(obj, corev1.EventTypeWarning, "CertificateChanged",
				"The card presents %s, not the pinned %s; nothing is written to it until %s names the new one", presented, pinned, AcceptCertificateAnnotation)
		}
		status.PresentedFingerprint = presented
		status.Message = fmt.Sprintf("the card presents certificate %s, not the pinned %s: a replaced or factory-reset card, or something else at its address. Annotate %s=%s to pin it", presented, pinned, AcceptCertificateAnnotation, presented)
		conditions.Set(obj, &clusterv1.Condition{
			Type: RackCardCertificateChangedCondition, Status: corev1.ConditionTrue,
			Reason: "Changed", Severity: clusterv1.ConditionSeverityError, Message: status.Message,
		})
		conditions.MarkFalse(obj, clusterv1.ReadyCondition, "CertificateChanged", clusterv1.ConditionSeverityError, "%s", status.Message)
		return true, nil
	}
	status.PresentedFingerprint = ""
	conditions.Set(obj, &clusterv1.Condition{Type: RackCardCertificateChangedCondition, Status: corev1.ConditionFalse, Reason: "Pinned"})
	return false, nil
}

// markRackCardDrift reports drift, with one event when it starts. It is not
// written over: a new generation converges it.
func markRackCardDrift(recorder record.EventRecorder, obj rackCard, detail string) {
	status := obj.CardStatus()
	if status.Drift != infrav1.RackCardDriftDrifted {
		recorder.Eventf(obj, corev1.EventTypeWarning, "Drifted", "%s; not written over until the spec's next generation", detail)
	}
	status.Drift = infrav1.RackCardDriftDrifted
	status.Message = detail
	conditions.MarkFalse(obj, RackCardConvergedCondition, "Drifted", clusterv1.ConditionSeverityWarning, "%s", detail)
}

// markRackCardNotAdopted reports a card the controller could not adopt, and
// why.
func markRackCardNotAdopted(obj rackCard, reason string, err error) {
	obj.CardStatus().Message = err.Error()
	conditions.MarkFalse(obj, RackCardAdoptedCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
	conditions.MarkFalse(obj, clusterv1.ReadyCondition, reason, clusterv1.ConditionSeverityWarning, "%v", err)
}

// markRackCardConverged records a converged generation.
func markRackCardConverged(recorder record.EventRecorder, obj rackCard) {
	now := metav1.Now()
	status := obj.CardStatus()
	status.Adopted = true
	status.ObservedGeneration = obj.GetGeneration()
	status.Drift = infrav1.RackCardDriftNone
	status.LastVerified = &now
	status.Message = "adopted and converged"
	conditions.MarkTrue(obj, RackCardAdoptedCondition)
	conditions.MarkTrue(obj, RackCardConvergedCondition)
	conditions.MarkTrue(obj, clusterv1.ReadyCondition)
	recorder.Eventf(obj, corev1.EventTypeNormal, "Converged", "Converged generation %d", obj.GetGeneration())
}

// rackCardOutlet is a card as the controller's account reaches it: through
// dial when set, pinned to the Secret's fingerprint. Callers set the outlet.
func rackCardOutlet(host, dial string, secret *corev1.Secret) power.Outlet {
	return power.Outlet{
		Driver:          power.DriverEaton,
		Host:            host,
		Outlet:          "1",
		Dial:            dial,
		Username:        string(secret.Data[rackCardKeyUsername]),
		Password:        string(secret.Data[rackCardKeyPassword]),
		InitialPassword: string(secret.Data[rackCardKeyInitialPassword]),
		TLSFingerprint:  string(secret.Data[rackCardKeyFingerprint]),
	}
}

// asAdmin is o logged in as username instead of the controller's account.
func asAdmin(o power.Outlet, username, password string) power.Outlet {
	o.Username, o.Password, o.InitialPassword = username, password, ""
	return o
}

// openEatonAdmin logs in as the card's administrator with the Secret's
// password, and otherwise with the factory login, setting the Secret's
// password in the same request. It names which.
func openEatonAdmin(ctx context.Context, card power.Outlet, secret *corev1.Secret, timeout time.Duration) (*power.EatonSession, string, error) {
	managed := asAdmin(card, string(secret.Data[rackCardKeyAdminUsername]), string(secret.Data[rackCardKeyAdminPassword]))
	session, err := power.OpenEatonSession(ctx, managed, "", timeout)
	if err == nil {
		return session, "with the managed password", nil
	}
	var refused *power.EatonLoginError
	if !errors.As(err, &refused) || !refused.Refused() {
		return nil, "", err
	}
	factory := asAdmin(card, rackCardFactoryUser, rackCardFactoryPassword)
	session, factoryErr := power.OpenEatonSession(ctx, factory, string(secret.Data[rackCardKeyAdminPassword]), timeout)
	if factoryErr == nil {
		return session, "with the factory login, and set the managed password", nil
	}
	return nil, "", fmt.Errorf("the managed password: %v; the factory login: %w", err, factoryErr)
}

// eatonLoginReason names why the administrator could not log in.
func eatonLoginReason(err error) string {
	var refusal *power.EatonLoginError
	switch {
	case errors.Is(err, power.ErrEatonConcurrentSession):
		return "AdminSessionBusy"
	case errors.As(err, &refusal) && refusal.Status == 401:
		return "AdminLoginRefused"
	case errors.As(err, &refusal) && refusal.NotServed():
		return "UnsupportedCard"
	case errors.As(err, &refusal):
		return "FirstLoginBlocked"
	}
	return "Unreachable"
}

// acceptEatonAdminLicence accepts the licence agreement for the
// administrator.
func acceptEatonAdminLicence(ctx context.Context, admin *power.EatonSession, accounts []power.EatonAccount, secret *corev1.Secret) error {
	account := findEatonAccount(accounts, string(secret.Data[rackCardKeyAdminUsername]))
	if account == nil {
		return fmt.Errorf("the card lists no %s account", secret.Data[rackCardKeyAdminUsername])
	}
	if account.Licence == "accepted" {
		return nil
	}
	if err := admin.AcceptLicence(ctx, account.ID); err != nil {
		return fmt.Errorf("accept the licence agreement for %s: %w", account.Name, err)
	}
	return nil
}

// ensureEatonControllerAccount makes the controller's account exist,
// unlocked, in profileName, with the licence accepted, and able to log in
// with the Secret's password, which verify checks through the driver's
// session; an account that cannot is made again.
func ensureEatonControllerAccount(ctx context.Context, recorder record.EventRecorder, obj client.Object, admin *power.EatonSession,
	accounts []power.EatonAccount, secret *corev1.Secret, profileName string, verify func(context.Context) error) error {
	username := string(secret.Data[rackCardKeyUsername])
	profiles, err := admin.Profiles(ctx)
	if err != nil {
		return fmt.Errorf("list the card's profiles: %w", err)
	}
	var profile *power.EatonProfile
	for i := range profiles {
		if profiles[i].Name == profileName {
			profile = &profiles[i]
		}
	}
	if profile == nil {
		return fmt.Errorf("the card has no %q profile", profileName)
	}

	account := findEatonAccount(accounts, username)
	if account != nil && account.Profile != profile.Ref {
		if err := admin.DeleteAccount(ctx, account.ID); err != nil {
			return fmt.Errorf("remove %s, which is not in %s: %w", username, profileName, err)
		}
		account = nil
	}
	for attempt := 0; ; attempt++ {
		if account == nil {
			created, err := admin.CreateAccount(ctx, username, profile.Ref, string(secret.Data[rackCardKeyInitialPassword]), "Tuist controller")
			if err != nil {
				return fmt.Errorf("create the controller's account %s: %w", username, err)
			}
			account = &created
			recorder.Eventf(obj, corev1.EventTypeNormal, "AccountCreated", "Created %s in %s", username, profileName)
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

		err := verify(ctx)
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
		recorder.Eventf(obj, corev1.EventTypeWarning, "AccountRecreated", "%s did not take the Secret's password; making it again", username)
		account = nil
	}
}

func findEatonAccount(accounts []power.EatonAccount, name string) *power.EatonAccount {
	for i := range accounts {
		if accounts[i].Name == name {
			return &accounts[i]
		}
	}
	return nil
}

// eatonDriver is the registry's eaton driver, whose sessions of the
// controller's accounts the power paths and the observers share.
func eatonDriver(registry *power.Registry) (*power.Eaton, error) {
	if registry == nil {
		return nil, fmt.Errorf("no power drivers wired into this operator build")
	}
	driver, err := registry.Get(power.DriverEaton)
	if err != nil {
		return nil, err
	}
	eaton, ok := driver.(*power.Eaton)
	if !ok {
		return nil, fmt.Errorf("the eaton driver is a %T", driver)
	}
	return eaton, nil
}

// rackCardEgressService is the egress Service fronting one card on :443.
type rackCardEgressService struct {
	// Name is the Service's name, e.g. rackpdu-<pdu>.
	Name string
	// Component is its app.kubernetes.io/component label.
	Component string
	// LabelKey and Owner label it with the object it fronts.
	LabelKey string
	Owner    string
	// Address is the card's address, which the ProxyGroup reaches through the
	// rack's edge.
	Address string
}

// host is the in-cluster DNS name the card is dialled by, empty when the
// tailnet egress is not configured.
func (s rackCardEgressService) host(cfg egressConfig) string {
	if !cfg.enabled() {
		return ""
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", s.Name, cfg.Namespace)
}

// reconcile keeps the Service. The object's finalizer deletes it: a Service
// in another namespace cannot be owned.
func (s rackCardEgressService) reconcile(ctx context.Context, c client.Client, cfg egressConfig) error {
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: s.Name, Namespace: cfg.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, c, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		svc.Labels["app.kubernetes.io/managed-by"] = cfg.ManagedBy
		svc.Labels["app.kubernetes.io/component"] = s.Component
		svc.Labels[s.LabelKey] = s.Owner
		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-ip"] = s.Address
		svc.Annotations["tailscale.com/proxy-group"] = cfg.ProxyGroup
		svc.Spec.Type = corev1.ServiceTypeExternalName
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + cfg.Namespace + ".svc.cluster.local"
		}
		svc.Spec.Ports = []corev1.ServicePort{{Name: "https", Port: 443, Protocol: corev1.ProtocolTCP}}
		return nil
	})
	if err != nil {
		return fmt.Errorf("keep egress Service %s/%s: %w", cfg.Namespace, svc.Name, err)
	}
	return nil
}

// release deletes the Service and drops the object's finalizer.
func (s rackCardEgressService) release(ctx context.Context, c client.Client, cfg egressConfig, obj client.Object, finalizer string) error {
	if !controllerutil.ContainsFinalizer(obj, finalizer) {
		return nil
	}
	if cfg.enabled() {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: s.Name, Namespace: cfg.Namespace}}
		if err := c.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete egress Service %s: %w", svc.Name, err)
		}
	}
	controllerutil.RemoveFinalizer(obj, finalizer)
	return nil
}
