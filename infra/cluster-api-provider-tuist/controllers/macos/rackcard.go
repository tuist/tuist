package macos

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackcard"
)

// The lifecycle every rack power device's management card shares, whichever
// device it is in: a RackPDU or a RackATS. Each card's passwords are derived
// from one root key (internal/rackcard), so a rebuilt cluster computes them
// again. Each is adopted on its factory login, keeps an unowned credentials
// Secret recording its passwords and pin, is pinned to the certificate it
// presented first, and reports drift rather than writing over it between
// generations.

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

	// rackCardAddressLabel on a credentials Secret is its card's address, so
	// every object's Secret for one card can be found.
	rackCardAddressLabel = "tuist.dev/rack-card-address"

	// rackCardAdminSetAnnotation on a credentials Secret is when its
	// administrator password was set on a card, at the card's forced
	// first-login change, and rackCardAdminSetCertificateAnnotation the
	// certificate that card presented. Only such a Secret's password is tried
	// on another object's card.
	rackCardAdminSetAnnotation            = "tuist.dev/rack-card-admin-set"
	rackCardAdminSetCertificateAnnotation = "tuist.dev/rack-card-admin-set-certificate"
)

// Keys of the Secret the controller generates for each card.
const (
	rackCardKeyAdminUsername = "admin-username"
	rackCardKeyAdminPassword = "admin-password"
	// rackCardKeyAdminPasswordPrevious is the administrator password the card
	// took before the one recorded, kept until the derived one takes alone.
	rackCardKeyAdminPasswordPrevious = "admin-password-previous"
	rackCardKeyUsername              = "username"
	rackCardKeyPassword              = "password"
	rackCardKeyInitialPassword       = "initial-password"
	rackCardKeyFingerprint           = "tlsFingerprint"
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

// rackCardRootKeyKey is the root key Secret's key holding the key.
const rackCardRootKeyKey = "key"

// rackCardRootKeyError is the root key missing or unusable, which blocks every
// adoption.
type rackCardRootKeyError struct {
	ref types.NamespacedName
	err error
}

func (e *rackCardRootKeyError) Error() string {
	return fmt.Sprintf("the rack card root key, Secret %s key %q, %v: no card's passwords can be derived, so no card is contacted", e.ref, rackCardRootKeyKey, e.err)
}

// loadRackCardRootKey reads the key every card's passwords are derived from.
func loadRackCardRootKey(ctx context.Context, c client.Reader, ref types.NamespacedName) ([]byte, error) {
	if ref.Name == "" {
		return nil, &rackCardRootKeyError{ref: ref, err: errors.New("is not configured (--rack-card-root-secret)")}
	}
	secret := &corev1.Secret{}
	if err := c.Get(ctx, ref, secret); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, &rackCardRootKeyError{ref: ref, err: errors.New("does not exist")}
		}
		return nil, fmt.Errorf("read the rack card root key %s: %w", ref, err)
	}
	key, err := rackcard.ParseRootKey(secret.Data[rackCardRootKeyKey])
	if err != nil {
		return nil, &rackCardRootKeyError{ref: ref, err: err}
	}
	return key, nil
}

// rackCardDerivedPasswords are an object's card's passwords.
func rackCardDerivedPasswords(rootKey []byte, site, mac, name string) rackcard.Passwords {
	return rackcard.Derive(rootKey, site, rackcard.Identity(mac, name))
}

// markRackCardRootKeyMissing reports a card the controller does not contact
// for want of the root key.
func markRackCardRootKeyMissing(obj rackCard, err error) {
	status := obj.CardStatus()
	status.Message = err.Error()
	status.Drift = infrav1.RackCardDriftUnknown
	conditions.MarkFalse(obj, RackCardAdoptedCondition, "RootKeyMissing", clusterv1.ConditionSeverityError, "%v", err)
	conditions.MarkFalse(obj, clusterv1.ReadyCondition, "RootKeyMissing", clusterv1.ConditionSeverityError, "%v", err)
	conditions.MarkUnknown(obj, RackCardConvergedCondition, "RootKeyMissing", "%v", err)
}

// rackCardCredentialsCurrent reports whether the Secret records the derived
// passwords: anything else is a card an earlier build or an earlier root key
// set, which an adoption pass moves onto them.
func rackCardCredentialsCurrent(secret *corev1.Secret, passwords rackcard.Passwords) bool {
	for k, v := range rackCardDerivedData(passwords) {
		if string(secret.Data[k]) != v {
			return false
		}
	}
	return true
}

func rackCardDerivedData(passwords rackcard.Passwords) map[string]string {
	return map[string]string{
		rackCardKeyAdminUsername:   rackCardFactoryUser,
		rackCardKeyAdminPassword:   passwords.Admin,
		rackCardKeyUsername:        rackCardControllerUser,
		rackCardKeyPassword:        passwords.Controller,
		rackCardKeyInitialPassword: passwords.ControllerInitial,
	}
}

// ensureRackCardSecret makes a card's credentials Secret, the record of what
// the card holds: the derived passwords for keys it lacks, and what it has
// left as it is until the card is moved onto the derived passwords, since a
// card an earlier build adopted is only reached with them. labelKey names the
// device kind, e.g. tuist.dev/rack-pdu.
func ensureRackCardSecret(ctx context.Context, c client.Client, obj client.Object, labelKey, address string, passwords rackcard.Passwords) (*corev1.Secret, error) {
	secret := &corev1.Secret{}
	key := types.NamespacedName{Namespace: obj.GetNamespace(), Name: rackCardSecretName(obj.GetName())}
	err := c.Get(ctx, key, secret)
	create := apierrors.IsNotFound(err)
	if err != nil && !create {
		return nil, err
	}
	// Unowned, so deleting or recreating the object does not collect the pin
	// and the record of a card not yet moved onto the derived passwords.
	if create {
		secret = &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace,
			Labels: map[string]string{"app.kubernetes.io/managed-by": operatorName, labelKey: obj.GetName()}}}
	}
	if secret.Data == nil {
		secret.Data = map[string][]byte{}
	}
	changed := false
	if secret.Labels[rackCardAddressLabel] != address {
		if secret.Labels == nil {
			secret.Labels = map[string]string{}
		}
		secret.Labels[rackCardAddressLabel] = address
		changed = true
	}
	owners := secret.OwnerReferences[:0]
	for _, ref := range secret.OwnerReferences {
		if ref.Kind == "RackPDU" || ref.Kind == "RackATS" {
			changed = true
			continue
		}
		owners = append(owners, ref)
	}
	secret.OwnerReferences = owners
	for k, v := range rackCardDerivedData(passwords) {
		if len(secret.Data[k]) > 0 {
			continue
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

// rackCardAdoptedPastCache reports whether the API server records obj's
// generation as adopted when the object read from the cache does not: the
// manager's cache can lag the status the last pass wrote, and adopting again
// would log the administrator in twice for one generation. fresh is an empty
// object of obj's kind; a nil reader reads through fallback.
func rackCardAdoptedPastCache(ctx context.Context, reader, fallback client.Reader, obj, fresh rackCard) bool {
	if reader == nil {
		reader = fallback
	}
	if err := reader.Get(ctx, client.ObjectKeyFromObject(obj), fresh); err != nil {
		return false
	}
	status := fresh.CardStatus()
	if fresh.GetGeneration() != obj.GetGeneration() || !status.Adopted || status.ObservedGeneration != obj.GetGeneration() {
		return false
	}
	cached := obj.CardStatus()
	cached.Adopted = true
	cached.ObservedGeneration = status.ObservedGeneration
	cached.Drift = status.Drift
	return true
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
	conditions.MarkUnknown(obj, RackCardConvergedCondition, "Unreachable", "%v", err)
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
// dial when set, pinned to the Secret's fingerprint. It names no outlet; the
// power paths set theirs.
func rackCardOutlet(host, dial string, secret *corev1.Secret) power.Outlet {
	return power.Outlet{
		Driver:          power.DriverEaton,
		Host:            host,
		Dial:            dial,
		Username:        string(secret.Data[rackCardKeyUsername]),
		Password:        string(secret.Data[rackCardKeyPassword]),
		InitialPassword: string(secret.Data[rackCardKeyInitialPassword]),
		TLSFingerprint:  string(secret.Data[rackCardKeyFingerprint]),
	}
}

// rackCardDerivedOutlet is the card as the controller's account reaches it on
// its derived passwords, which adoption moves the account onto before the
// Secret records them.
func rackCardDerivedOutlet(host, dial string, secret *corev1.Secret, passwords rackcard.Passwords) power.Outlet {
	o := rackCardOutlet(host, dial, secret)
	o.Username, o.Password, o.InitialPassword = rackCardControllerUser, passwords.Controller, passwords.ControllerInitial
	return o
}

// rackCardControllerAccount is the controller's account as adoption makes it.
func rackCardControllerAccount(passwords rackcard.Passwords) eatonControllerAccount {
	return eatonControllerAccount{Username: rackCardControllerUser, InitialPassword: passwords.ControllerInitial}
}

// asAdmin is o logged in as username instead of the controller's account.
func asAdmin(o power.Outlet, username, password string) power.Outlet {
	o.Username, o.Password, o.InitialPassword = username, password, ""
	return o
}

// rackCardReasonRotationNotApplied is a card that took a login asking for the
// derived administrator password and then refused that password.
const rackCardReasonRotationNotApplied = "PasswordRotationNotApplied"

// markRackCardRotationNotApplied reports a card managed on a password the
// controller could not move it off: adopted in all but its password, so
// Ready stays what the pass found.
func markRackCardRotationNotApplied(obj rackCard, err error) {
	obj.CardStatus().Message = err.Error()
	conditions.MarkFalse(obj, RackCardAdoptedCondition, rackCardReasonRotationNotApplied, clusterv1.ConditionSeverityWarning, "%v", err)
}

// rackCardAdminLogin is the administrator's session on a card, and how it was
// reached.
type rackCardAdminLogin struct {
	Session *power.EatonSession
	How     string
	// RotationNotApplied, when set, is a card that took a login asking for
	// the derived password and then refused it: the session is on the
	// password that worked, which the Secret keeps.
	RotationNotApplied error
}

// rackCardRotationError is a card that took a login with the derived
// password as newPassword, then refused the derived password.
type rackCardRotationError struct {
	from string
	err  error
}

func (e *rackCardRotationError) Error() string {
	return fmt.Sprintf("the card took %s with the derived administrator password as newPassword, then refused the derived password (%v); the card keeps the password that worked", e.from, e.err)
}

func (e *rackCardRotationError) Unwrap() error { return e.err }

// openRackCardAdmin logs in as the card's administrator and moves the card
// onto the derived administrator password. It tries, in order: the derived
// password; the password the Secret records and the one it recorded before,
// when they are others (a card an earlier build or an earlier root key set);
// the administrator password of at most one other object's Secret for the
// same card address, one that recorded setting it on a card presenting this
// certificate (an object that logged in to a card of a kind it could not
// drive: the card forces the change before it can be asked what it is); and
// the factory login. Each but the first asks for the derived password in the
// same request, the token endpoint's newPassword. A change is believed only
// once a fresh login with the derived password takes: then the Secret records
// it, keeping the password it replaced under admin-password-previous. A card
// that refuses it keeps the password that worked, in the card and in the
// Secret, and the login reports RotationNotApplied.
func openRackCardAdmin(ctx context.Context, c client.Client, recorder record.EventRecorder, obj client.Object, card power.Outlet,
	secret *corev1.Secret, passwords rackcard.Passwords, timeout time.Duration) (rackCardAdminLogin, error) {
	open := func(password, newPassword string) (*power.EatonSession, error) {
		return power.OpenEatonSession(ctx, asAdmin(card, rackCardFactoryUser, password), newPassword, timeout)
	}
	session, err := open(passwords.Admin, "")
	if err == nil {
		if err := recordRackCardAdmin(ctx, c, secret, rackCardAdminRecord{Password: passwords.Admin, DropPrevious: true}); err != nil {
			_ = session.Close(ctx)
			return rackCardAdminLogin{}, err
		}
		return rackCardAdminLogin{Session: session, How: "with the derived password"}, nil
	}
	if !adminLoginRefused(err) {
		return rackCardAdminLogin{}, err
	}
	failures := []string{fmt.Sprintf("the derived password: %v", err)}
	tried := map[string]bool{passwords.Admin: true}

	type candidate struct {
		password, from string
		mark           func(*corev1.Secret)
	}
	var candidates []candidate
	for _, key := range []string{rackCardKeyAdminPassword, rackCardKeyAdminPasswordPrevious} {
		if stored := string(secret.Data[key]); stored != "" && !tried[stored] {
			tried[stored] = true
			candidates = append(candidates, candidate{password: stored, from: fmt.Sprintf("the password Secret %s/%s records as %s", secret.Namespace, secret.Name, key)})
		}
	}
	sibling, ok, err := rackCardMarkedSibling(ctx, c, secret, card.TLSFingerprint, tried)
	if err != nil {
		return rackCardAdminLogin{}, err
	}
	if ok {
		candidates = append(candidates, candidate{
			password: string(sibling.Data[rackCardKeyAdminPassword]),
			from:     fmt.Sprintf("the administrator password another object set, from Secret %s/%s", sibling.Namespace, sibling.Name),
			mark: func(s *corev1.Secret) {
				markRackCardAdminSet(s, sibling.Annotations[rackCardAdminSetAnnotation], sibling.Annotations[rackCardAdminSetCertificateAnnotation])
			},
		})
	}
	for _, cand := range candidates {
		changed, err := open(cand.password, passwords.Admin)
		if err != nil {
			if !adminLoginRefused(err) {
				return rackCardAdminLogin{}, err
			}
			failures = append(failures, fmt.Sprintf("%s: %v", cand.from, err))
			continue
		}
		verified, err := proveRackCardAdmin(ctx, changed, open, passwords)
		if err != nil && !adminLoginRefused(err) {
			return rackCardAdminLogin{}, err
		}
		if err == nil {
			if err := recordRackCardAdmin(ctx, c, secret, rackCardAdminRecord{Password: passwords.Admin, Previous: cand.password,
				SetOn: card.TLSFingerprint}); err != nil {
				_ = verified.Close(ctx)
				return rackCardAdminLogin{}, err
			}
			recorder.Eventf(obj, corev1.EventTypeNormal, "PasswordRotated",
				"Moved the card's admin password onto the derived one; it was %s", cand.from)
			return rackCardAdminLogin{Session: verified, How: fmt.Sprintf("with %s, and moved it onto the derived password", cand.from)}, nil
		}

		notApplied := &rackCardRotationError{from: cand.from, err: err}
		again, err := open(cand.password, "")
		if err != nil {
			return rackCardAdminLogin{}, fmt.Errorf("%v, and then refused it too: %w", notApplied, err)
		}
		if string(secret.Data[rackCardKeyAdminPassword]) != cand.password {
			if err := recordRackCardAdmin(ctx, c, secret, rackCardAdminRecord{Password: cand.password,
				Previous: string(secret.Data[rackCardKeyAdminPassword]), Mark: cand.mark}); err != nil {
				_ = again.Close(ctx)
				return rackCardAdminLogin{}, err
			}
		}
		recorder.Eventf(obj, corev1.EventTypeWarning, "PasswordRotationNotApplied", "%v", notApplied)
		return rackCardAdminLogin{Session: again, How: fmt.Sprintf("with %s, which the card keeps", cand.from), RotationNotApplied: notApplied}, nil
	}

	changed, factoryErr := open(rackCardFactoryPassword, passwords.Admin)
	if factoryErr != nil {
		return rackCardAdminLogin{}, fmt.Errorf("%s; the factory login: %w", strings.Join(failures, "; "), factoryErr)
	}
	verified, err := proveRackCardAdmin(ctx, changed, open, passwords)
	if err != nil && !adminLoginRefused(err) {
		return rackCardAdminLogin{}, err
	}
	if err != nil {
		// The factory password is public: nothing is recorded, and the card is
		// not adopted on it.
		notApplied := &rackCardRotationError{from: "the factory login", err: err}
		recorder.Eventf(obj, corev1.EventTypeWarning, "PasswordRotationNotApplied", "%v", notApplied)
		return rackCardAdminLogin{}, notApplied
	}
	if err := recordRackCardAdmin(ctx, c, secret, rackCardAdminRecord{Password: passwords.Admin,
		Previous: string(secret.Data[rackCardKeyAdminPassword]), SetOn: card.TLSFingerprint}); err != nil {
		_ = verified.Close(ctx)
		return rackCardAdminLogin{}, err
	}
	return rackCardAdminLogin{Session: verified, How: "with the factory login, and set the derived password"}, nil
}

// proveRackCardAdmin logs out the session that asked for the derived
// password, since the card allows one session per account, and logs in with
// the derived password alone: the session, or the card's answer to it.
func proveRackCardAdmin(ctx context.Context, changed *power.EatonSession, open func(password, newPassword string) (*power.EatonSession, error),
	passwords rackcard.Passwords) (*power.EatonSession, error) {
	if err := changed.Close(ctx); err != nil {
		return nil, fmt.Errorf("log out before logging in with the derived password: %w", err)
	}
	return open(passwords.Admin, "")
}

func adminLoginRefused(err error) bool {
	var refused *power.EatonLoginError
	return errors.As(err, &refused) && refused.Refused()
}

// rackCardAdminRecord is an administrator password that took on the card, to
// record in its Secret.
type rackCardAdminRecord struct {
	Password string
	// Previous, when set, is kept as admin-password-previous: the password
	// the card took before, so no write drops the last one known to work.
	Previous string
	// DropPrevious removes admin-password-previous, once Password took
	// without it.
	DropPrevious bool
	// SetOn, when set, marks the Secret as having set Password, now, on the
	// card presenting this certificate.
	SetOn string
	// Mark, when set, copies another Secret's mark.
	Mark func(*corev1.Secret)
}

// recordRackCardAdmin records in the Secret an administrator password the
// card took.
func recordRackCardAdmin(ctx context.Context, c client.Client, secret *corev1.Secret, record rackCardAdminRecord) error {
	before := map[string]string{}
	for k, v := range secret.Data {
		before[k] = string(v)
	}
	annotations := fmt.Sprint(secret.Annotations)
	secret.Data[rackCardKeyAdminUsername] = []byte(rackCardFactoryUser)
	secret.Data[rackCardKeyAdminPassword] = []byte(record.Password)
	switch {
	case record.Previous != "" && record.Previous != record.Password:
		secret.Data[rackCardKeyAdminPasswordPrevious] = []byte(record.Previous)
	case record.DropPrevious:
		delete(secret.Data, rackCardKeyAdminPasswordPrevious)
	}
	if record.SetOn != "" {
		markRackCardAdminSet(secret, time.Now().UTC().Format(time.RFC3339), record.SetOn)
	}
	if record.Mark != nil {
		record.Mark(secret)
	}
	changed := len(before) != len(secret.Data) || annotations != fmt.Sprint(secret.Annotations)
	for k, v := range secret.Data {
		changed = changed || before[k] != string(v)
	}
	if !changed {
		return nil
	}
	if err := c.Update(ctx, secret); err != nil {
		return fmt.Errorf("record the card's administrator password in %s: %w", secret.Name, err)
	}
	return nil
}

// recordRackCardController records the controller's account's derived
// passwords in the Secret, once the card's account takes them.
func recordRackCardController(ctx context.Context, c client.Client, secret *corev1.Secret, passwords rackcard.Passwords) error {
	changed := false
	for k, v := range map[string]string{
		rackCardKeyUsername:        rackCardControllerUser,
		rackCardKeyPassword:        passwords.Controller,
		rackCardKeyInitialPassword: passwords.ControllerInitial,
	} {
		if string(secret.Data[k]) != v {
			secret.Data[k] = []byte(v)
			changed = true
		}
	}
	if !changed {
		return nil
	}
	if err := c.Update(ctx, secret); err != nil {
		return fmt.Errorf("record the controller's account's password in %s: %w", secret.Name, err)
	}
	return nil
}

// rackCardMarkedSibling is the one other credentials Secret for the card's
// address whose administrator password may be tried on it: of those that
// recorded setting the password on a card presenting this certificate, the
// most recent, skipping passwords already tried. Every other Secret is
// skipped, so a card that blocks an account after a few failed logins is
// never walked through leftovers.
func rackCardMarkedSibling(ctx context.Context, c client.Client, secret *corev1.Secret, fingerprint string, tried map[string]bool) (*corev1.Secret, bool, error) {
	address := secret.Labels[rackCardAddressLabel]
	if address == "" {
		return nil, false, nil
	}
	siblings := &corev1.SecretList{}
	if err := c.List(ctx, siblings, client.InNamespace(secret.Namespace), client.MatchingLabels{rackCardAddressLabel: address}); err != nil {
		return nil, false, fmt.Errorf("list the other credentials Secrets for %s: %w", address, err)
	}
	var best *corev1.Secret
	var bestAt time.Time
	for i := range siblings.Items {
		sibling := &siblings.Items[i]
		password := string(sibling.Data[rackCardKeyAdminPassword])
		if sibling.Name == secret.Name || password == "" || tried[password] {
			continue
		}
		at, err := time.Parse(time.RFC3339, sibling.Annotations[rackCardAdminSetAnnotation])
		if err != nil || !power.SameTLSFingerprint(sibling.Annotations[rackCardAdminSetCertificateAnnotation], fingerprint) {
			continue
		}
		if best == nil || at.After(bestAt) {
			best, bestAt = sibling, at
		}
	}
	return best, best != nil, nil
}

// markRackCardAdminSet records on a Secret when its administrator password
// was set on a card, and that card's certificate.
func markRackCardAdminSet(secret *corev1.Secret, at, fingerprint string) {
	if secret.Annotations == nil {
		secret.Annotations = map[string]string{}
	}
	secret.Annotations[rackCardAdminSetAnnotation] = at
	secret.Annotations[rackCardAdminSetCertificateAnnotation] = fingerprint
}

// rackCardUnexpectedResponse reports a card answering unlike the API it was
// adopted through: its login or a read missing, or a page instead of JSON.
func rackCardUnexpectedResponse(err error) bool {
	var refusal *power.EatonLoginError
	var status *power.EatonHTTPError
	var unsupported *power.EatonUnsupportedError
	switch {
	case errors.As(err, &refusal):
		return refusal.NotServed()
	case errors.As(err, &status):
		return status.Status == 404 || (status.Body != "" && !json.Valid([]byte(status.Body)))
	}
	return errors.As(err, &unsupported)
}

// markRackCardUnexpected reports an adopted card answering unlike its API,
// such as a card restarting, without taking its adoption back: the object
// stays Adopted, and is not Ready until the card answers as it did.
func markRackCardUnexpected(obj rackCard, err error) {
	status := obj.CardStatus()
	status.Drift = infrav1.RackCardDriftUnknown
	status.Message = fmt.Sprintf("the adopted card answered unlike its API: %v", err)
	conditions.MarkFalse(obj, clusterv1.ReadyCondition, "UnexpectedResponse", clusterv1.ConditionSeverityWarning, "%s", status.Message)
	conditions.MarkUnknown(obj, RackCardConvergedCondition, "UnexpectedResponse", "%s", status.Message)
}

// rackCardWrongKind reports a card an object logged in to as administrator
// and found to be of a kind it does not drive. The login already changed the
// card's administrator password, so the error names the Secret that holds it,
// where the object for the card's real kind finds it.
func rackCardWrongKind(err error, secret *corev1.Secret) error {
	return fmt.Errorf("%w. Its administrator password is now the one in Secret %s/%s (%s), which the object for this card's kind logs in with",
		err, secret.Namespace, secret.Name, rackCardKeyAdminPassword)
}

// eatonLoginReason names why the administrator could not log in.
func eatonLoginReason(err error) string {
	var refusal *power.EatonLoginError
	var rotation *rackCardRotationError
	switch {
	case errors.As(err, &rotation):
		return rackCardReasonRotationNotApplied
	case errors.Is(err, power.ErrEatonConcurrentSession):
		return "AdminSessionBusy"
	case errors.As(err, &refusal) && refusal.Code == "AccountBlocked":
		return "AccountBlocked"
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

// eatonControllerAccount is the controller's account as adoption makes it:
// its name, and the password it is made with, which the card makes it change
// at its first login.
type eatonControllerAccount struct {
	Username        string
	InitialPassword string
}

// ensureEatonControllerAccount makes the controller's account exist,
// unlocked, in profileName, with the licence accepted, and able to log in
// with its derived password, which verify checks through the driver's
// session; an account that cannot (one on a password an earlier build or an
// earlier root key set) is made again on the derived password.
func ensureEatonControllerAccount(ctx context.Context, recorder record.EventRecorder, obj client.Object, admin *power.EatonSession,
	accounts []power.EatonAccount, want eatonControllerAccount, profileName string, verify func(context.Context) error) error {
	username := want.Username
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
	remade := false
	for attempt := 0; ; attempt++ {
		if account == nil {
			created, err := admin.CreateAccount(ctx, username, profile.Ref, want.InitialPassword, "Tuist controller")
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
			if remade {
				recorder.Eventf(obj, corev1.EventTypeNormal, "PasswordRotated", "Moved the card's controller password onto the derived one, by making %s again", username)
			}
			return nil
		}
		if attempt > 0 || !errors.As(err, &refused) || !refused.Refused() {
			return fmt.Errorf("log in as %s: %w", username, err)
		}
		if err := admin.DeleteAccount(ctx, account.ID); err != nil {
			return fmt.Errorf("remove %s, which does not take its derived password: %w", username, err)
		}
		recorder.Eventf(obj, corev1.EventTypeWarning, "AccountRecreated", "%s did not take its derived password; making it again", username)
		account, remade = nil, true
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

// rackCardLogOut ends the controller's session on the card, so a person can
// log in with the account and the card's one session for it is free. A card
// that cannot be reached keeps it until its idle timeout, which the event
// says.
func rackCardLogOut(ctx context.Context, recorder record.EventRecorder, registry *power.Registry, obj client.Object, host, dial string) {
	eaton, err := eatonDriver(registry)
	if err == nil {
		err = eaton.Logout(ctx, power.Outlet{Driver: power.DriverEaton, Host: host, Dial: dial})
	}
	if err != nil {
		recorder.Eventf(obj, corev1.EventTypeWarning, "LogoutFailed",
			"Could not log the controller's account out of the card, which keeps its session until the card's idle timeout: %v", err)
	}
}

// releaseRackCard lets a deleted object go once the controller's session on
// its card is logged out and its egress Service is deleted. finalizers are
// the names the object may hold, current and earlier; any of them holds it.
func releaseRackCard(ctx context.Context, c client.Client, cfg egressConfig, logOut func(), egress rackCardEgressService, obj client.Object, finalizers ...string) error {
	held := false
	for _, f := range finalizers {
		held = held || controllerutil.ContainsFinalizer(obj, f)
	}
	if !held {
		return nil
	}
	logOut()
	if cfg.enabled() {
		svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: egress.Name, Namespace: cfg.Namespace}}
		if err := c.Delete(ctx, svc); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete egress Service %s: %w", svc.Name, err)
		}
	}
	for _, f := range finalizers {
		controllerutil.RemoveFinalizer(obj, f)
	}
	return nil
}

// cardLoginRefused reports a login the card refused for the account's
// password or because it blocked the account: what the login backoff spaces
// out.
func cardLoginRefused(err error) bool {
	var refusal *power.EatonLoginError
	return errors.As(err, &refusal) && (refusal.Refused() || refusal.Code == "AccountBlocked")
}
