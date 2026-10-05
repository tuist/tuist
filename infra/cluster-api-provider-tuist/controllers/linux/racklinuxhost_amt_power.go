package linux

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman"
	amtboot "github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/amt/boot"
	cimboot "github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/cim/boot"
	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/cim/models"
	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/cim/power"
	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/client"
	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrlclient "sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// RebootAnnotation asks for a one-off power change through the host's AMT:
// cycle, reset, or pxe (a power cycle into the network boot). The operator
// makes it once, records it in status.amt.lastPowerAction and removes the
// annotation. Whether the host is on at all is spec.online.
const RebootAnnotation = "tuist.dev/reboot"

// PowerCondition reports whether the host's power state matches spec.online.
const PowerCondition clusterv1.ConditionType = "PowerMatchesOnline"

const (
	amtPowerTimeout = time.Minute
	// amtPowerObserveInterval is how often the power state of a host the
	// tailnet cannot vouch for is read from AMT.
	amtPowerObserveInterval = 10 * time.Minute
	// amtPowerChangeBackoff spaces the power changes spec.online asks for.
	amtPowerChangeBackoff = 5 * time.Minute

	rackPowerOn  = "On"
	rackPowerOff = "Off"
)

// amtTLSPinKey holds, in a host's AMT Secret, the SHA-256 of the TLS
// certificate AMT presented to the first power change.
const amtTLSPinKey = "tls-sha256"

// amtPowerChange is a power change and, for a network boot, the boot it
// forces. A read changes nothing and reports the power state.
type amtPowerChange struct {
	state power.PowerState
	// netboot has the next boot go to the network: AMT's Force PXE Boot, which
	// boots the firmware's first network entry.
	netboot bool
	read    bool
}

var amtPowerActions = map[string]amtPowerChange{
	"on":    {state: power.PowerOn},
	"off":   {state: power.PowerOffHard},
	"cycle": {state: power.PowerCycleOffHard},
	"reset": {state: power.MasterBusReset},
	"pxe":   {state: power.PowerCycleOffHard, netboot: true},
	"read":  {read: true},
}

// amtRebootActions are the tuist.dev/reboot values.
var amtRebootActions = map[string]bool{"cycle": true, "reset": true, "pxe": true}

// amtCredentials is how the operator logs in to a host's AMT.
type amtCredentials struct {
	Username, Password string
	// TLSSHA256 is the pinned SHA-256 of AMT's self-signed TLS certificate.
	// Empty accepts the certificate AMT presents.
	TLSSHA256 string
}

// amtResponse is what AMT answered: the SHA-256 of the TLS certificate it
// presented, and for a read, its power state (On or Off).
type amtResponse struct {
	Presented  string
	PowerState string
}

// amtPowerFunc asks AMT at address for a power change, or for its power
// state, through via's SSH session.
type amtPowerFunc func(ctx context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, change amtPowerChange) (amtResponse, error)

// reconcileReboot makes the one-off power change the host's tuist.dev/reboot
// annotation asks for. AMT answers on the management segment, which only the
// edges are on, so the request goes through a connected edge of the host's
// site, another one than the host when there is one: the host may be what is
// down.
func (r *RackLinuxHostReconciler) reconcileReboot(ctx context.Context, host *infrav1.RackLinuxHost) {
	action, ok := host.Annotations[RebootAnnotation]
	if !ok {
		return
	}
	delete(host.Annotations, RebootAnnotation)
	if !amtRebootActions[action] {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTPowerFailed",
			"%s=%q is not cycle, reset or pxe; whether the host is on is spec.online", RebootAnnotation, action)
		return
	}
	if err := r.recordAMTPower(ctx, host, action); err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTPowerFailed", "Could not %s the host through AMT: %v", action, err)
		return
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "AMTPower", "Asked AMT to %s the host, through %s",
		action, host.Status.AMT.LastPowerAction.Via)
}

// reconcilePower holds the host to spec.online. A host connected to the
// tailnet is on; otherwise AMT is asked, every amtPowerObserveInterval. A host
// that should be off is shut down over SSH while it is on the tailnet, and
// powered off through AMT otherwise; one that should be on and is off is
// powered on through AMT. Changes are spaced by amtPowerChangeBackoff. It
// returns when to look again.
func (r *RackLinuxHostReconciler) reconcilePower(ctx context.Context, host *infrav1.RackLinuxHost) time.Duration {
	now := r.now()
	connected := host.Status.Tailnet != nil && host.Status.Tailnet.Connected
	switch {
	case connected:
		host.Status.Power = &infrav1.RackLinuxHostPowerStatus{State: rackPowerOn, ObservedAt: &metav1.Time{Time: now}}
	case r.amtCanPower(host):
		if p := host.Status.Power; p == nil || p.ObservedAt == nil || now.Sub(p.ObservedAt.Time) >= amtPowerObserveInterval ||
			(!host.Spec.Online && p.State != rackPowerOff) {
			state, err := r.readAMTPower(ctx, host)
			if err != nil {
				conditions.MarkFalse(host, PowerCondition, "PowerUnreadable", clusterv1.ConditionSeverityWarning, "%v", err)
				return amtPowerObserveInterval
			}
			host.Status.Power = &infrav1.RackLinuxHostPowerStatus{State: state, ObservedAt: &metav1.Time{Time: now}}
		}
	default:
		if !host.Spec.Online {
			conditions.MarkFalse(host, PowerCondition, "CannotPowerOff", clusterv1.ConditionSeverityWarning,
				"spec.online is false, but %s is not on the tailnet to shut down and its AMT is not activated", host.Spec.Hostname)
		} else {
			conditions.Delete(host, PowerCondition)
		}
		return 0
	}

	state := host.Status.Power.State
	want := rackPowerOn
	if !host.Spec.Online {
		want = rackPowerOff
	}
	if state == want {
		conditions.MarkTrue(host, PowerCondition)
		return amtPowerObserveInterval
	}
	if last := host.Status.AMT; last != nil && last.LastPowerAction != nil {
		if wait := last.LastPowerAction.At.Add(amtPowerChangeBackoff).Sub(now); wait > 0 &&
			(last.LastPowerAction.Action == "on" || last.LastPowerAction.Action == "off") {
			return wait
		}
	}
	var err error
	switch {
	case want == rackPowerOff && connected:
		err = r.shutDown(ctx, host)
		if err == nil {
			r.recordPowerChange(host, "off", "")
		}
	case want == rackPowerOff:
		err = r.recordAMTPower(ctx, host, "off")
	default:
		err = r.recordAMTPower(ctx, host, "on")
	}
	if err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "PowerNotChanged", "Could not power %s %s: %v", host.Spec.Hostname, strings.ToLower(want), err)
		conditions.MarkFalse(host, PowerCondition, "PowerNotChanged", clusterv1.ConditionSeverityWarning, "%v", err)
		return time.Minute
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "PowerChanged", "Powered %s %s to match spec.online", host.Spec.Hostname, strings.ToLower(want))
	conditions.MarkFalse(host, PowerCondition, "PowerChanging", clusterv1.ConditionSeverityInfo, "powering %s", strings.ToLower(want))
	return amtPowerChangeBackoff
}

// shutDown powers a host on the tailnet off from its own OS.
func (r *RackLinuxHostReconciler) shutDown(ctx context.Context, host *infrav1.RackLinuxHost) error {
	fleet := ""
	switch {
	case r.Install != nil:
		fleet = r.Install.FleetName
	case r.AMT != nil:
		fleet = r.AMT.FleetName
	}
	_, err := runOnRackHost(ctx, r.Client, r.CredentialsManager, fleet, r.egress(), r.RunScript, host,
		"systemd-run --quiet --on-active=5 systemctl poweroff\n", time.Minute)
	return err
}

// recordPowerChange records a power change the operator made without AMT.
func (r *RackLinuxHostReconciler) recordPowerChange(host *infrav1.RackLinuxHost, action, via string) {
	if host.Status.AMT == nil {
		host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{}
	}
	host.Status.AMT.LastPowerAction = &infrav1.RackLinuxHostAMTPowerAction{Action: action, At: metav1.NewTime(r.now()), Via: via}
}

// readAMTPower reads the host's power state from AMT.
func (r *RackLinuxHostReconciler) readAMTPower(ctx context.Context, host *infrav1.RackLinuxHost) (string, error) {
	record := &infrav1.RackLinuxHostAMTPowerAction{}
	response, err := r.powerAMT(ctx, host, "read", record)
	if err != nil {
		return "", err
	}
	return response.PowerState, nil
}

// amtCanPower reports whether the operator can ask host's AMT for a power
// change.
func (r *RackLinuxHostReconciler) amtCanPower(host *infrav1.RackLinuxHost) bool {
	amt := host.Status.AMT
	return r.AMT != nil && amt != nil && (amt.ControlMode == amtAdminControl || amt.ControlMode == amtClientControl) &&
		amt.Address != "" && amt.Address != "0.0.0.0"
}

// recordAMTPower asks host's AMT for action and records it in
// status.amt.lastPowerAction.
func (r *RackLinuxHostReconciler) recordAMTPower(ctx context.Context, host *infrav1.RackLinuxHost, action string) error {
	if host.Status.AMT == nil {
		host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{}
	}
	record := &infrav1.RackLinuxHostAMTPowerAction{Action: action, At: metav1.NewTime(r.now())}
	host.Status.AMT.LastPowerAction = record
	if _, err := r.powerAMT(ctx, host, action, record); err != nil {
		record.Error = err.Error()
		return err
	}
	return nil
}

func (r *RackLinuxHostReconciler) powerAMT(ctx context.Context, host *infrav1.RackLinuxHost, action string, record *infrav1.RackLinuxHostAMTPowerAction) (amtResponse, error) {
	change, ok := amtPowerActions[action]
	if !ok {
		return amtResponse{}, fmt.Errorf("%q is not a power action; use on, off, cycle, reset or pxe", action)
	}
	amt := host.Status.AMT
	if amt == nil || (amt.ControlMode != amtAdminControl && amt.ControlMode != amtClientControl) {
		return amtResponse{}, fmt.Errorf("AMT is not activated")
	}
	if amt.Address == "" || amt.Address == "0.0.0.0" {
		return amtResponse{}, fmt.Errorf("AMT has no address on the management port")
	}
	if r.AMT == nil {
		return amtResponse{}, fmt.Errorf("the operator has no AMT configuration")
	}
	secret := &corev1.Secret{}
	name := types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: amtSecretName(host)}
	if err := r.Get(ctx, name, secret); err != nil {
		return amtResponse{}, fmt.Errorf("read AMT's credentials from %s: %w", name, err)
	}
	creds := amtCredentials{
		Username:  string(secret.Data["username"]),
		Password:  string(secret.Data["password"]),
		TLSSHA256: string(secret.Data[amtTLSPinKey]),
	}
	if creds.Username == "" {
		creds.Username = "admin"
	}
	vias, err := r.amtTunnelHosts(ctx, host)
	if err != nil {
		return amtResponse{}, err
	}
	powerFn := r.AMTPower
	if powerFn == nil {
		powerFn = r.powerAMTOverSSH
	}
	var missed []string
	for _, via := range vias {
		response, err := powerFn(ctx, via, amt.Address, creds, change)
		if errors.Is(err, errAMTNotOnLink) {
			missed = append(missed, err.Error())
			continue
		}
		record.Via = via.Name
		if err != nil {
			return amtResponse{}, err
		}
		if creds.TLSSHA256 == "" && response.Presented != "" {
			secret.Data[amtTLSPinKey] = []byte(response.Presented)
			if err := r.Update(ctx, secret); err != nil {
				return amtResponse{}, fmt.Errorf("pin AMT's TLS certificate in %s: %w", name, err)
			}
		}
		return response, nil
	}
	return amtResponse{}, fmt.Errorf("no edge of site %q reaches AMT at %s: %s", host.Spec.Location.Site, amt.Address, strings.Join(missed, "; "))
}

// errAMTNotOnLink is an edge that cannot put a request on AMT's link: it is
// unreachable, or AMT's address is not on one of its links. Only the edge
// holding the site's floating addresses has an address on the management
// segment.
var errAMTNotOnLink = errors.New("not on AMT's link")

// amtTunnelHosts are the connected edges of host's site to reach AMT through,
// in the order to try them: other edges first, then the host itself.
func (r *RackLinuxHostReconciler) amtTunnelHosts(ctx context.Context, host *infrav1.RackLinuxHost) ([]*infrav1.RackLinuxHost, error) {
	list := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, list, ctrlclient.InNamespace(host.Namespace)); err != nil {
		return nil, fmt.Errorf("list the site's edges: %w", err)
	}
	var edges []*infrav1.RackLinuxHost
	for i := range list.Items {
		h := &list.Items[i]
		if h.Name == host.Name {
			h = host
		}
		if h.Spec.Role != "edge" || h.Spec.Location.Site != host.Spec.Location.Site || !h.DeletionTimestamp.IsZero() ||
			h.Status.Tailnet == nil || !h.Status.Tailnet.Connected {
			continue
		}
		edges = append(edges, h)
	}
	sort.SliceStable(edges, func(i, j int) bool {
		if (edges[i].Name == host.Name) != (edges[j].Name == host.Name) {
			return edges[j].Name == host.Name
		}
		return edges[i].Name < edges[j].Name
	})
	if len(edges) == 0 {
		return nil, fmt.Errorf("no edge of site %q is on the tailnet to reach AMT through", host.Spec.Location.Site)
	}
	return edges, nil
}

// powerAMTOverSSH sends the power change through via's SSH session once via
// shows AMT's address is on one of its links. It returns errAMTNotOnLink,
// before sending anything, when via is unreachable or routes the address
// through a gateway.
func (r *RackLinuxHostReconciler) powerAMTOverSSH(ctx context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, change amtPowerChange) (amtResponse, error) {
	if net.ParseIP(address) == nil {
		return amtResponse{}, fmt.Errorf("AMT's address %q is not an IP address", address)
	}
	var response amtResponse
	connected := false
	err := withRackHostSSH(ctx, r.Client, r.CredentialsManager, r.AMT.FleetName, r.egress(), via, amtPowerTimeout, func(c *ssh.Client) error {
		connected = true
		session, err := c.NewSession()
		if err != nil {
			return fmt.Errorf("%w: open a session on %s: %v", errAMTNotOnLink, via.Name, err)
		}
		route, err := session.Output("ip -o route get " + address)
		session.Close()
		if err != nil || strings.Contains(string(route), " via ") {
			return fmt.Errorf("%w: %s does not reach %s on a link of its own (%s)", errAMTNotOnLink, via.Name, address, strings.TrimSpace(string(route)))
		}
		response, err = requestAMTPower(ctx, c.DialContext, address, creds, change)
		return err
	})
	if err != nil && !connected {
		return amtResponse{}, fmt.Errorf("%w: %v", errAMTNotOnLink, err)
	}
	return response, err
}

// requestAMTPower asks AMT at address for a power change, or for its power
// state, over WS-MAN, over TLS with digest authentication, dialling through
// dial. An activated AMT serves
// WS-MAN only on its TLS port, with a self-signed certificate, which is held
// to creds.TLSSHA256 when that is set. It returns the SHA-256 of the
// certificate AMT presented and, for a read, the power state.
func requestAMTPower(ctx context.Context, dial func(ctx context.Context, network, addr string) (net.Conn, error),
	address string, creds amtCredentials, change amtPowerChange) (amtResponse, error) {
	var presented string
	transport := &http.Transport{
		DialContext:       dial,
		DisableKeepAlives: true,
		TLSClientConfig: &tls.Config{
			MinVersion: tls.VersionTLS12,
			// AMT's certificate is self-signed; the pin below is what holds
			// AMT to it.
			InsecureSkipVerify: true,
			VerifyPeerCertificate: func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
				if len(rawCerts) == 0 {
					return fmt.Errorf("AMT presented no certificate")
				}
				sum := sha256.Sum256(rawCerts[0])
				presented = hex.EncodeToString(sum[:])
				if creds.TLSSHA256 != "" && !strings.EqualFold(presented, creds.TLSSHA256) {
					return fmt.Errorf("AMT presented certificate %s, not the pinned %s", presented, creds.TLSSHA256)
				}
				return nil
			},
		},
	}
	defer transport.CloseIdleConnections()
	messages := wsman.NewMessages(client.Parameters{
		Target:    address,
		Username:  creds.Username,
		Password:  creds.Password,
		UseDigest: true,
		UseTLS:    true,
		Transport: transport,
		Timeout:   30 * time.Second,
	})
	if err := ctx.Err(); err != nil {
		return amtResponse{}, err
	}
	if change.read {
		state, err := amtPowerState(messages)
		if err != nil {
			return amtResponse{}, fmt.Errorf("read AMT at %s's power state: %w", address, err)
		}
		return amtResponse{Presented: presented, PowerState: state}, nil
	}
	if change.netboot {
		if err := amtBootFromNetwork(messages); err != nil {
			return amtResponse{}, fmt.Errorf("set AMT at %s to boot from the network: %w", address, err)
		}
	}
	response, err := messages.CIM.PowerManagementService.RequestPowerStateChange(change.state)
	if err != nil {
		return amtResponse{}, fmt.Errorf("ask AMT at %s for power state %d: %w", address, change.state, err)
	}
	if rv := response.Body.RequestPowerStateChangeResponse.ReturnValue; rv != 0 {
		return amtResponse{}, fmt.Errorf("AMT at %s refused power state %d: return value %d", address, change.state, rv)
	}
	return amtResponse{Presented: presented}, nil
}

// amtBootFromNetwork sets AMT's next boot to the network, the way AMT takes
// it: the boot order cleared, the boot settings written back without any
// override of their own, the configuration made the next one, and the source
// chosen.
func amtBootFromNetwork(m wsman.Messages) error {
	current, err := m.AMT.BootSettingData.Get()
	if err != nil {
		return fmt.Errorf("read the boot settings: %w", err)
	}
	settings := current.Body.BootSettingDataGetResponse
	if _, err := m.CIM.BootConfigSetting.ChangeBootOrder(""); err != nil {
		return fmt.Errorf("clear the boot order: %w", err)
	}
	if _, err := m.AMT.BootSettingData.Put(amtboot.BootSettingDataRequest{
		H:                 "http://intel.com/wbem/wscim/1/amt-schema/1/AMT_BootSettingData",
		ElementName:       settings.ElementName,
		InstanceID:        settings.InstanceID,
		OwningEntity:      settings.OwningEntity,
		EnforceSecureBoot: settings.EnforceSecureBoot,
		FirmwareVerbosity: settings.FirmwareVerbosity,
	}); err != nil {
		return fmt.Errorf("write the boot settings: %w", err)
	}
	if _, err := m.CIM.BootService.SetBootConfigRole("Intel(r) AMT: Boot Configuration 0", 1); err != nil {
		return fmt.Errorf("make the boot configuration the next one: %w", err)
	}
	if _, err := m.CIM.BootConfigSetting.ChangeBootOrder(cimboot.PXE); err != nil {
		return fmt.Errorf("choose the network boot: %w", err)
	}
	return nil
}

// amtPowerState reads the host's power state from AMT's
// CIM_AssociatedPowerManagementService: On, or Off for every off and sleep
// state.
func amtPowerState(m wsman.Messages) (string, error) {
	enumerated, err := m.CIM.AssociatedPowerManagementService.Enumerate()
	if err != nil {
		return "", err
	}
	pulled, err := m.CIM.AssociatedPowerManagementService.Pull(enumerated.Body.EnumerateResponse.EnumerationContext)
	if err != nil {
		return "", err
	}
	items := pulled.Body.PullResponse.AssociatedPowerManagementServiceItems
	if len(items) == 0 {
		return "", fmt.Errorf("AMT reported no power state")
	}
	if items[0].PowerState == models.PowerStateOn {
		return rackPowerOn, nil
	}
	return rackPowerOff, nil
}
