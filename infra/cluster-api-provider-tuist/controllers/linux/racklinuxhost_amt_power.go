package linux

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"sort"
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

var amtPowerStates = map[string]power.PowerState{
	"on":    power.PowerOn,
	"off":   power.PowerOffHard,
	"cycle": power.PowerCycleOffHard,
	"reset": power.MasterBusReset,
}

// AMTPowerFunc asks AMT at address for a power change through via's SSH
// session.
type AMTPowerFunc func(ctx context.Context, via *infrav1.RackLinuxHost, address, username, password string, state power.PowerState) error

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
	username := string(secret.Data["username"])
	if username == "" {
		username = "admin"
	}
	via, err := r.amtTunnelHost(ctx, host)
	if err != nil {
		return err
	}
	record.Via = via.Name
	powerFn := r.AMTPower
	if powerFn == nil {
		powerFn = r.powerAMTOverSSH
	}
	return powerFn(ctx, via, amt.Address, username, string(secret.Data["password"]), state)
}

// amtTunnelHost is the connected edge of host's site to reach AMT through:
// another edge first, then the host itself.
func (r *RackLinuxHostReconciler) amtTunnelHost(ctx context.Context, host *infrav1.RackLinuxHost) (*infrav1.RackLinuxHost, error) {
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
	return edges[0], nil
}

func (r *RackLinuxHostReconciler) powerAMTOverSSH(ctx context.Context, via *infrav1.RackLinuxHost, address, username, password string, state power.PowerState) error {
	return withRackHostSSH(ctx, r.Client, r.CredentialsManager, r.AMT.FleetName, r.egress(), via, amtPowerTimeout, func(c *ssh.Client) error {
		return requestAMTPower(ctx, c.DialContext, address, username, password, state)
	})
}

// requestAMTPower asks AMT at address for a power change over WS-MAN with
// digest authentication, dialling through dial.
func requestAMTPower(ctx context.Context, dial func(ctx context.Context, network, addr string) (net.Conn, error),
	address, username, password string, state power.PowerState) error {
	transport := &http.Transport{DialContext: dial, DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	messages := wsman.NewMessages(client.Parameters{
		Target:    address,
		Username:  username,
		Password:  password,
		UseDigest: true,
		Transport: transport,
		Timeout:   30 * time.Second,
	})
	if err := ctx.Err(); err != nil {
		return err
	}
	response, err := messages.CIM.PowerManagementService.RequestPowerStateChange(state)
	if err != nil {
		return fmt.Errorf("ask AMT at %s for power state %d: %w", address, state, err)
	}
	if rv := response.Body.RequestPowerStateChangeResponse.ReturnValue; rv != 0 {
		return fmt.Errorf("AMT at %s refused power state %d: return value %d", address, state, rv)
	}
	return nil
}
