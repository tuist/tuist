package macos

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackcard"
)

// atsCard is one kind of transfer-switch management card. The RackATS
// lifecycle is the same behind every kind; only how the card is spoken to
// differs, so a second kind (an SNMPv3 one, say) is a second implementation
// of this.
type atsCard interface {
	// Kind names the card's protocol, as status reports it.
	Kind() string
	// Fingerprint reads the certificate the card presents, trusting nothing,
	// or "" for a card that speaks no TLS.
	Fingerprint(ctx context.Context) (string, error)
	// Adopt converges the card as its administrator: the administrator's
	// password away from the factory one, the controller's own account, and
	// the preferred source. Every step reads first and writes only what
	// differs.
	Adopt(ctx context.Context, preferred int) (atsAdoption, error)
	// Observe reads the switch as the controller's account.
	Observe(ctx context.Context) (atsObservation, error)
}

// atsAdoption is what adopting a card did.
type atsAdoption struct {
	// PreferredUnrecognised, when not empty, is why the preferred source
	// could not be set: the card reports none the implementation recognises.
	PreferredUnrecognised string
	// RotationNotApplied, when set, is a card that kept the administrator
	// password the controller logged in with rather than the derived one.
	RotationNotApplied error
}

// atsObservation is the switch as its card reported it.
type atsObservation struct {
	Card                                      string
	CardModel, CardSerial, CardFirmware       string
	DeviceModel, DeviceSerial, DeviceFirmware string
	// Active is the source powering the load, 0 for neither.
	Active int32
	// Preferred is the preferred source, 0 when the card reports none the
	// implementation recognises, with PreferredDetail saying what it has.
	Preferred       int32
	PreferredDetail string
	Inputs          []infrav1.RackATSInput
}

// atsCardError is a card failure with the condition reason it is reported
// under.
type atsCardError struct {
	Reason string
	Err    error
}

func (e *atsCardError) Error() string { return e.Err.Error() }
func (e *atsCardError) Unwrap() error { return e.Err }

// atsReason is the condition reason err is reported under.
func atsReason(err error, fallback string) string {
	var cardErr *atsCardError
	if errors.As(err, &cardErr) {
		return cardErr.Reason
	}
	return fallback
}

const (
	rackATSReasonUnsupported = "UnsupportedCard"
	// The controller's account only reads the switch, in the card's
	// "viewers" profile.
	rackATSControllerProfile = "viewers"
)

// eatonATSCard is a Network-M2 or Network-M3 card in an Eaton transfer
// switch, over the REST API the rack's Eaton PDUs speak.
type eatonATSCard struct {
	r         *RackATSReconciler
	ats       *infrav1.RackATS
	secret    *corev1.Secret
	passwords rackcard.Passwords
}

func (c *eatonATSCard) Kind() string { return "eaton-mbdetnrs" }

func (c *eatonATSCard) outlet() power.Outlet {
	return rackCardOutlet(rackATSHost(c.ats), rackATSEgress(c.ats).host(c.r.egressConfig()), c.secret)
}

func (c *eatonATSCard) Fingerprint(ctx context.Context) (string, error) {
	return power.ProbeTLSFingerprint(ctx, c.outlet(), c.r.timeout())
}

func (c *eatonATSCard) Adopt(ctx context.Context, preferred int) (atsAdoption, error) {
	logger := log.FromContext(ctx)
	login, err := openRackCardAdmin(ctx, c.r.Client, c.r.Recorder, c.ats, c.outlet(), c.secret, c.passwords, c.r.timeout())
	if err != nil {
		return atsAdoption{}, &atsCardError{Reason: eatonLoginReason(err), Err: err}
	}
	admin := login.Session
	adopted := atsAdoption{RotationNotApplied: login.RotationNotApplied}
	defer func() {
		if err := admin.Close(ctx); err != nil {
			logger.Error(err, "log the administrator out of the card")
		}
	}()
	c.r.Recorder.Eventf(c.ats, corev1.EventTypeNormal, "LoggedIn", "Logged in as %s %s", rackCardFactoryUser, login.How)

	// What the card is, before anything else is written to it. The login may
	// already have changed a factory card's administrator password: the card
	// forces that before it answers anything else.
	state, err := admin.ATS(ctx)
	if err != nil {
		var unsupported *power.EatonUnsupportedError
		if errors.As(err, &unsupported) {
			return atsAdoption{}, &atsCardError{Reason: rackATSReasonUnsupported, Err: rackCardWrongKind(err, c.secret)}
		}
		return atsAdoption{}, err
	}

	accounts, err := admin.Accounts(ctx)
	if err != nil {
		return atsAdoption{}, fmt.Errorf("list the card's accounts: %w", err)
	}
	if err := acceptEatonAdminLicence(ctx, admin, accounts, c.secret); err != nil {
		return atsAdoption{}, err
	}
	if err := ensureEatonControllerAccount(ctx, c.r.Recorder, c.ats, admin, accounts, rackCardControllerAccount(c.passwords), rackATSControllerProfile, func(ctx context.Context) error {
		eaton, err := eatonDriver(c.r.Power)
		if err != nil {
			return err
		}
		_, err = eaton.Identification(ctx, rackCardDerivedOutlet(rackATSHost(c.ats), rackATSEgress(c.ats).host(c.r.egressConfig()), c.secret, c.passwords))
		return err
	}); err != nil {
		return atsAdoption{}, err
	}
	if err := recordRackCardController(ctx, c.r.Client, c.secret, c.passwords); err != nil {
		return atsAdoption{}, err
	}

	if state.PreferredKey == "" {
		adopted.PreferredUnrecognised = eatonPreferredUnrecognised(state)
		return adopted, nil
	}
	if state.Preferred == preferred {
		return adopted, nil
	}
	if err := admin.SetATSPreferredSource(ctx, state, preferred); err != nil {
		return atsAdoption{}, fmt.Errorf("set the preferred source to %d: %w", preferred, err)
	}
	if state, err = admin.ATS(ctx); err != nil {
		return atsAdoption{}, eatonATSError(err)
	}
	if state.Preferred != preferred {
		return atsAdoption{}, fmt.Errorf("the preferred source reads %d after being set to %d", state.Preferred, preferred)
	}
	return adopted, nil
}

func (c *eatonATSCard) Observe(ctx context.Context) (atsObservation, error) {
	eaton, err := eatonDriver(c.r.Power)
	if err != nil {
		return atsObservation{}, err
	}
	state, err := eaton.ATS(ctx, c.outlet())
	if err != nil {
		var refused *power.EatonLoginError
		var unreachable *url.Error
		switch {
		case errors.As(err, &refused) && refused.NotServed():
			return atsObservation{}, &atsCardError{Reason: rackATSReasonUnsupported, Err: err}
		case errors.As(err, &refused) && refused.Code == "AccountBlocked":
			return atsObservation{}, &atsCardError{Reason: "AccountBlocked", Err: err}
		case errors.As(err, &refused):
			return atsObservation{}, &atsCardError{Reason: "ControllerLoginFailed", Err: err}
		case errors.As(err, &unreachable):
			return atsObservation{}, &atsCardError{Reason: "Unreachable", Err: err}
		}
		return atsObservation{}, eatonATSError(err)
	}
	active, err := state.Active()
	if err != nil {
		return atsObservation{}, &atsCardError{Reason: rackATSReasonUnsupported, Err: err}
	}
	obs := atsObservation{
		Card:      fmt.Sprintf("%s %s (%s, firmware %s) over /rest/mbdetnrs/2.0", c.Kind(), state.Card.Product, state.Card.Model, state.Card.Firmware),
		CardModel: state.Card.Model, CardSerial: state.Card.Serial, CardFirmware: state.Card.Firmware,
		DeviceModel: state.Model, DeviceSerial: state.Serial, DeviceFirmware: state.Firmware,
		Active:    int32(active),
		Preferred: int32(state.Preferred),
	}
	if state.PreferredKey == "" {
		obs.PreferredDetail = eatonPreferredUnrecognised(state)
	}
	for _, in := range state.Inputs {
		s, detail := in.State()
		input := infrav1.RackATSInput{Source: int32(in.Number), State: infrav1.RackATSInputState(s), Detail: detail}
		if in.Voltage != nil {
			input.Voltage = strconv.FormatFloat(*in.Voltage, 'f', -1, 64)
		}
		if in.Frequency != nil {
			input.Frequency = strconv.FormatFloat(*in.Frequency, 'f', -1, 64)
		}
		obs.Inputs = append(obs.Inputs, input)
	}
	return obs, nil
}

// eatonATSError reports a card that is not a transfer switch the driver knows
// as unsupported.
func eatonATSError(err error) error {
	var unsupported *power.EatonUnsupportedError
	if errors.As(err, &unsupported) {
		return &atsCardError{Reason: rackATSReasonUnsupported, Err: err}
	}
	return err
}

func eatonPreferredUnrecognised(state power.EatonATS) string {
	return fmt.Sprintf("the card's settings carry no preferred source the controller recognises; they have %s",
		strings.Join(state.SettingsKeys(), ", "))
}
