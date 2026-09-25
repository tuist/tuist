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
	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/cim/power"
	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/client"
	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrlclient "sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// AMTPowerAnnotation asks a host's AMT for a power change: on, off, cycle or
// reset. The operator makes it once, records it in status.amt.lastPowerAction
// and removes the annotation.
const AMTPowerAnnotation = "tuist.dev/amt-power"

const amtPowerTimeout = time.Minute

// amtTLSPinKey holds, in a host's AMT Secret, the SHA-256 of the TLS
// certificate AMT presented to the first power change.
const amtTLSPinKey = "tls-sha256"

var amtPowerStates = map[string]power.PowerState{
	"on":    power.PowerOn,
	"off":   power.PowerOffHard,
	"cycle": power.PowerCycleOffHard,
	"reset": power.MasterBusReset,
}

// amtCredentials is how the operator logs in to a host's AMT.
type amtCredentials struct {
	Username, Password string
	// TLSSHA256 is the pinned SHA-256 of AMT's self-signed TLS certificate.
	// Empty accepts the certificate AMT presents.
	TLSSHA256 string
}

// amtPowerFunc asks AMT at address for a power change through via's SSH
// session, and returns the SHA-256 of the TLS certificate AMT presented.
type amtPowerFunc func(ctx context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, state power.PowerState) (string, error)

// reconcileAMTPower makes the power change the host's annotation asks for.
// AMT answers on the management segment, which only the edges are on, so the
// request goes through a connected edge of the host's site, another one than
// the host when there is one: the host may be what is down.
func (r *RackLinuxHostReconciler) reconcileAMTPower(ctx context.Context, host *infrav1.RackLinuxHost) {
	action, ok := host.Annotations[AMTPowerAnnotation]
	if !ok {
		return
	}
	delete(host.Annotations, AMTPowerAnnotation)
	if err := r.recordAMTPower(ctx, host, action); err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "AMTPowerFailed", "Could not %s the host through AMT: %v", action, err)
		return
	}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "AMTPower", "Asked AMT to %s the host, through %s",
		action, host.Status.AMT.LastPowerAction.Via)
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
	if err := r.powerAMT(ctx, host, action, record); err != nil {
		record.Error = err.Error()
		return err
	}
	return nil
}

func (r *RackLinuxHostReconciler) powerAMT(ctx context.Context, host *infrav1.RackLinuxHost, action string, record *infrav1.RackLinuxHostAMTPowerAction) error {
	state, ok := amtPowerStates[action]
	if !ok {
		return fmt.Errorf("%q is not a power action; use on, off, cycle or reset", action)
	}
	amt := host.Status.AMT
	if amt.ControlMode != amtAdminControl && amt.ControlMode != amtClientControl {
		return fmt.Errorf("AMT is not activated (control mode %q)", amt.ControlMode)
	}
	if amt.Address == "" || amt.Address == "0.0.0.0" {
		return fmt.Errorf("AMT has no address on the management port")
	}
	if r.AMT == nil {
		return fmt.Errorf("the operator has no AMT configuration")
	}
	secret := &corev1.Secret{}
	name := types.NamespacedName{Namespace: r.CredentialsManager.Namespace, Name: amtSecretName(host)}
	if err := r.Get(ctx, name, secret); err != nil {
		return fmt.Errorf("read AMT's credentials from %s: %w", name, err)
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
		return err
	}
	powerFn := r.AMTPower
	if powerFn == nil {
		powerFn = r.powerAMTOverSSH
	}
	var missed []string
	for _, via := range vias {
		presented, err := powerFn(ctx, via, amt.Address, creds, state)
		if errors.Is(err, errAMTNotOnLink) {
			missed = append(missed, err.Error())
			continue
		}
		record.Via = via.Name
		if err != nil {
			return err
		}
		if creds.TLSSHA256 == "" && presented != "" {
			secret.Data[amtTLSPinKey] = []byte(presented)
			if err := r.Update(ctx, secret); err != nil {
				return fmt.Errorf("pin AMT's TLS certificate in %s: %w", name, err)
			}
		}
		return nil
	}
	return fmt.Errorf("no edge of site %q reaches AMT at %s: %s", host.Spec.Location.Site, amt.Address, strings.Join(missed, "; "))
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
func (r *RackLinuxHostReconciler) powerAMTOverSSH(ctx context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, state power.PowerState) (string, error) {
	if net.ParseIP(address) == nil {
		return "", fmt.Errorf("AMT's address %q is not an IP address", address)
	}
	var presented string
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
		presented, err = requestAMTPower(ctx, c.DialContext, address, creds, state)
		return err
	})
	if err != nil && !connected {
		return "", fmt.Errorf("%w: %v", errAMTNotOnLink, err)
	}
	return presented, err
}

// requestAMTPower asks AMT at address for a power change over WS-MAN, over TLS
// with digest authentication, dialling through dial. An activated AMT serves
// WS-MAN only on its TLS port, with a self-signed certificate, which is held
// to creds.TLSSHA256 when that is set. It returns the SHA-256 of the
// certificate AMT presented.
func requestAMTPower(ctx context.Context, dial func(ctx context.Context, network, addr string) (net.Conn, error),
	address string, creds amtCredentials, state power.PowerState) (string, error) {
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
		return "", err
	}
	response, err := messages.CIM.PowerManagementService.RequestPowerStateChange(state)
	if err != nil {
		return "", fmt.Errorf("ask AMT at %s for power state %d: %w", address, state, err)
	}
	if rv := response.Body.RequestPowerStateChangeResponse.ReturnValue; rv != 0 {
		return "", fmt.Errorf("AMT at %s refused power state %d: return value %d", address, state, rv)
	}
	return presented, nil
}
