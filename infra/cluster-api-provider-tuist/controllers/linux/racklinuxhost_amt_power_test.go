package linux

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/device-management-toolkit/go-wsman-messages/v2/pkg/wsman/cim/power"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

const powerStateChangeResponse = `<?xml version="1.0" encoding="UTF-8"?>
<a:Envelope xmlns:a="http://www.w3.org/2003/05/soap-envelope" xmlns:b="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:c="http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd" xmlns:g="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService">
<a:Header>
<b:To>http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</b:To>
<b:RelatesTo>0</b:RelatesTo>
<b:Action a:mustUnderstand="true">http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService/RequestPowerStateChangeResponse</b:Action>
<b:MessageID>uuid:00000000-8086-8086-8086-0000000003B8</b:MessageID>
<c:ResourceURI>http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService</c:ResourceURI>
</a:Header>
<a:Body><g:RequestPowerStateChange_OUTPUT><g:ReturnValue>%s</g:ReturnValue></g:RequestPowerStateChange_OUTPUT></a:Body>
</a:Envelope>
`

// fakeAMTResponse answers one WS-MAN request as AMT does, by its action.
func fakeAMTResponse(body, powerReturnValue, powerState string) string {
	envelope := func(inner string) string {
		return `<?xml version="1.0" encoding="UTF-8"?><a:Envelope xmlns:a="http://www.w3.org/2003/05/soap-envelope" xmlns:g="http://example/g"><a:Header></a:Header><a:Body>` + inner + `</a:Body></a:Envelope>`
	}
	switch {
	case strings.Contains(body, "CIM_AssociatedPowerManagementService") && strings.Contains(body, "enumeration/Enumerate"):
		return envelope(`<g:EnumerateResponse><g:EnumerationContext>ctx-1</g:EnumerationContext></g:EnumerateResponse>`)
	case strings.Contains(body, "CIM_AssociatedPowerManagementService") && strings.Contains(body, "enumeration/Pull"):
		return envelope(`<g:PullResponse><g:Items><g:CIM_AssociatedPowerManagementService><g:PowerState>` + powerState + `</g:PowerState></g:CIM_AssociatedPowerManagementService></g:Items></g:PullResponse>`)
	case strings.Contains(body, "CIM_BootConfigSetting/ChangeBootOrder"):
		return envelope(`<g:ChangeBootOrder_OUTPUT><g:ReturnValue>0</g:ReturnValue></g:ChangeBootOrder_OUTPUT>`)
	case strings.Contains(body, "CIM_BootService/SetBootConfigRole"):
		return envelope(`<g:SetBootConfigRole_OUTPUT><g:ReturnValue>0</g:ReturnValue></g:SetBootConfigRole_OUTPUT>`)
	case strings.Contains(body, "AMT_BootSettingData"):
		return envelope(`<g:AMT_BootSettingData><g:ElementName>Intel(r) AMT Boot Configuration Settings</g:ElementName><g:InstanceID>Intel(r) AMT:BootSettingData 0</g:InstanceID><g:OwningEntity>Intel(r) AMT</g:OwningEntity><g:EnforceSecureBoot>false</g:EnforceSecureBoot></g:AMT_BootSettingData>`)
	}
	return strings.Replace(powerStateChangeResponse, "%s", powerReturnValue, 1)
}

// fakeAMT answers WS-MAN over TLS behind digest authentication, as an
// activated AMT does on 16993, with the host on (power state 2) unless
// powerState says otherwise.
func fakeAMT(t *testing.T, returnValue string, bodies *[]string, authorizations *[]string, powerState ...string) (dial func(context.Context, string, string) (net.Conn, error), dialled *[]string, fingerprint string) {
	t.Helper()
	state := "2"
	if len(powerState) > 0 {
		state = powerState[0]
	}
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Digest ") {
			w.Header().Set("WWW-Authenticate", `Digest realm="Digest:A3829B3827DE4D33D4449B366831FD01", nonce="bm9uY2U", stale="false", qop="auth"`)
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		body, _ := io.ReadAll(r.Body)
		*bodies = append(*bodies, string(body))
		*authorizations = append(*authorizations, auth)
		w.Header().Set("Content-Type", "application/soap+xml; charset=UTF-8")
		_, _ = io.WriteString(w, fakeAMTResponse(string(body), returnValue, state))
	}))
	t.Cleanup(server.Close)
	sum := sha256.Sum256(server.Certificate().Raw)
	var addrs []string
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		addrs = append(addrs, addr)
		var d net.Dialer
		return d.DialContext(ctx, network, server.Listener.Addr().String())
	}, &addrs, hex.EncodeToString(sum[:])
}

func TestRequestAMTPowerAsksAMTOverDigestWSMANAndPinsItsCertificate(t *testing.T) {
	var bodies, authorizations []string
	dial, dialled, fingerprint := fakeAMT(t, "0", &bodies, &authorizations)

	response, err := requestAMTPower(context.Background(), dial, "192.168.50.112", amtCredentials{Username: "admin", Password: "Secret-Pa55!"}, amtPowerChange{state: power.PowerCycleOffHard})
	if err != nil {
		t.Fatal(err)
	}

	if len(*dialled) == 0 || (*dialled)[0] != "192.168.50.112:16993" {
		t.Fatalf("dialled %v, want AMT's TLS WS-MAN port", *dialled)
	}
	if len(bodies) != 1 || !strings.Contains(bodies[0], "RequestPowerStateChange") || !strings.Contains(bodies[0], ">5</") {
		t.Fatalf("request bodies %v", bodies)
	}
	if !strings.Contains(authorizations[0], `username="admin"`) || strings.Contains(authorizations[0], "Secret-Pa55!") {
		t.Fatalf("authorization %q", authorizations[0])
	}
	if response.Presented != fingerprint {
		t.Fatalf("presented %q, want the certificate AMT presented, %q", response.Presented, fingerprint)
	}

	if _, err := requestAMTPower(context.Background(), dial, "192.168.50.112",
		amtCredentials{Username: "admin", Password: "Secret-Pa55!", TLSSHA256: strings.ToUpper(fingerprint)}, amtPowerChange{state: power.PowerOn}); err != nil {
		t.Fatalf("refused the pinned certificate: %v", err)
	}
}

func TestRequestAMTPowerRefusesACertificateOtherThanThePinnedOne(t *testing.T) {
	var bodies, authorizations []string
	dial, _, _ := fakeAMT(t, "0", &bodies, &authorizations)

	_, err := requestAMTPower(context.Background(), dial, "192.168.50.112",
		amtCredentials{Username: "admin", Password: "Secret-Pa55!", TLSSHA256: strings.Repeat("ab", 32)}, amtPowerChange{state: power.PowerOn})
	if err == nil || len(bodies) != 0 {
		t.Fatalf("err = %v, bodies %v; want the request refused before it is sent", err, bodies)
	}
}

func TestRequestAMTPowerReportsARefusal(t *testing.T) {
	var bodies, authorizations []string
	dial, _, _ := fakeAMT(t, "2", &bodies, &authorizations)

	_, err := requestAMTPower(context.Background(), dial, "192.168.50.112", amtCredentials{Username: "admin", Password: "Secret-Pa55!"}, amtPowerChange{state: power.PowerOn})
	if err == nil || !strings.Contains(err.Error(), "2") {
		t.Fatalf("err = %v, want AMT's return value", err)
	}
}

// A read reports AMT's power state, On or Off, and changes nothing.
func TestRequestAMTPowerReadsThePowerState(t *testing.T) {
	for state, want := range map[string]string{"2": rackPowerOn, "8": rackPowerOff, "6": rackPowerOff} {
		var bodies, authorizations []string
		dial, _, _ := fakeAMT(t, "0", &bodies, &authorizations, state)

		response, err := requestAMTPower(context.Background(), dial, "192.168.50.22", amtCredentials{Username: "admin", Password: "Secret-Pa55!"}, amtPowerChange{read: true})
		if err != nil {
			t.Fatal(err)
		}
		if response.PowerState != want {
			t.Errorf("power state %s read as %q, want %q", state, response.PowerState, want)
		}
		for _, b := range bodies {
			if strings.Contains(b, "RequestPowerStateChange") {
				t.Fatal("a read changed the power state")
			}
		}
	}
}

type powerCall struct {
	via, address string
	creds        amtCredentials
	state        power.PowerState
	netboot      bool
}

func activatedAMTEdge(annotation string) *infrav1.RackLinuxHost {
	h := amtEdge()
	if annotation != "" {
		h.Annotations = map[string]string{RebootAnnotation: annotation}
	}
	observed := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	h.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "192.168.50.112", ObservedAt: &observed}
	return h
}

func amtSecret(password string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: edgeUUID + "-amt", Namespace: rackTestNamespace},
		Data:       map[string][]byte{"username": []byte("admin"), "password": []byte(password)},
	}
}

// recordPower records each power change, and answers reads with the host on.
func recordPower(calls *[]powerCall) amtPowerFunc {
	return recordPowerWhile(calls, rackPowerOn)
}

// recordPowerWhile records each power change, and answers reads with state.
func recordPowerWhile(calls *[]powerCall, state string) amtPowerFunc {
	return func(_ context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, change amtPowerChange) (amtResponse, error) {
		if change.read {
			return amtResponse{Presented: "c692252b", PowerState: state}, nil
		}
		*calls = append(*calls, powerCall{via: via.Name, address: address, creds: creds, state: change.state, netboot: change.netboot})
		return amtResponse{Presented: "c692252b"}, nil
	}
}

func newPowerHarness(t *testing.T, objs ...runtime.Object) (*installHarness, *[]powerCall) {
	t.Helper()
	h := newAMTHarness(t, objs...)
	h.api.devices = append(h.api.devices, tailnet.Device{
		NodeID: "dev-2", Name: "ber1-edge-b.example.ts.net", Hostname: "ber1-edge-b",
		Addresses: []string{"100.64.0.8"}, Tags: []string{"tag:tuist-rack-edge"}, Created: "2026-09-24T08:00:00Z", ConnectedToControl: true,
	})
	var calls []powerCall
	h.r.AMTPower = recordPower(&calls)
	return h, &calls
}

func otherConnectedEdge() *infrav1.RackLinuxHost {
	h := otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true)
	h.Status.Tailnet.DeviceID = "dev-2"
	return h
}

func TestRackAMTPowerCyclesAHostThroughAnotherEdge(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("cycle"), otherConnectedEdge(), amtSecret("Stored-Pa55!"), provisioningSecret())

	got := h.reconcile(t, edgeUUID)

	want := powerCall{via: "ber1-edge-b", address: "192.168.50.112", creds: amtCredentials{Username: "admin", Password: "Stored-Pa55!"}, state: power.PowerCycleOffHard}
	if len(*calls) != 1 || (*calls)[0] != want {
		t.Fatalf("power calls %+v, want %+v", *calls, want)
	}
	if _, ok := got.Annotations[RebootAnnotation]; ok {
		t.Fatal("the annotation was not consumed")
	}
	last := got.Status.AMT.LastPowerAction
	if last == nil || last.Action != "cycle" || last.Via != "ber1-edge-b" || last.Error != "" || !last.At.Time.Equal(installEpoch) {
		t.Fatalf("lastPowerAction %+v", last)
	}
}

func TestRackAMTPowerNeedsActivatedAMT(t *testing.T) {
	host := activatedAMTEdge("reset")
	host.Status.AMT.ControlMode = "pre-provisioning"
	h, calls := newPowerHarness(t, host, otherConnectedEdge(), amtSecret("Stored-Pa55!"))

	got := h.reconcile(t, edgeUUID)

	if len(*calls) != 0 {
		t.Fatal("asked a pre-provisioned AMT for a power change")
	}
	if _, ok := got.Annotations[RebootAnnotation]; ok {
		t.Fatal("the annotation was not consumed")
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || last.Action != "reset" || !strings.Contains(last.Error, "not activated") {
		t.Fatalf("lastPowerAction %+v", last)
	}
}

// tuist.dev/reboot takes one-off changes only: whether the host is on is
// spec.online.
func TestRackAMTRebootRefusesWhatIsNotAReboot(t *testing.T) {
	for _, action := range []string{"on", "off", "reboot"} {
		t.Run(action, func(t *testing.T) {
			h, calls := newPowerHarness(t, activatedAMTEdge(action), otherConnectedEdge(), amtSecret("Stored-Pa55!"))

			got := h.reconcile(t, edgeUUID)

			if len(*calls) != 0 {
				t.Fatalf("made a power change for %q", action)
			}
			if _, ok := got.Annotations[RebootAnnotation]; ok {
				t.Fatal("the annotation was not consumed")
			}
			refused := false
			for _, e := range drainEvents(h) {
				refused = refused || strings.Contains(e, "is not cycle, reset or pxe")
			}
			if !refused {
				t.Fatal("no event says why nothing was done")
			}
		})
	}
}

func TestRackAMTPowerGoesThroughTheHostItselfWhenNoOtherEdgeIsUp(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("reset"), amtSecret("Stored-Pa55!"))

	h.reconcile(t, edgeUUID)

	if len(*calls) != 1 || (*calls)[0].via != edgeUUID {
		t.Fatalf("power calls %+v", *calls)
	}
}

// A host off the tailnet cannot be rebooted into its installer over SSH. With
// its AMT activated, the operator power-cycles it into its network boot.
func TestRackInstallPowerCyclesAnOfflineHostThroughAMT(t *testing.T) {
	host := reinstalling()
	observed := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "192.168.50.113", ObservedAt: &observed}
	secret := amtSecret("Stored-Pa55!")
	secret.Name = svcUUID + "-amt"
	h := newInstallHarness(t, host, otherEdge("ber1-edge-a", rackTestNamespace, "ber1", "edge", true), secret)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false)}
	h.r.AMT = &RackAMT{FleetName: rackTestFleet, ProvisioningSecret: amtTestProvisioningSecret}
	var calls []powerCall
	h.r.AMTPower = recordPower(&calls)

	h.reconcile(t, svcUUID)
	if len(calls) != 0 {
		t.Fatal("power-cycled the host before the boot server could serve its install")
	}

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got := h.reconcile(t, svcUUID)
	// The power state read of the earlier reconcile pinned AMT's certificate.
	want := powerCall{via: "ber1-edge-a", address: "192.168.50.113", creds: amtCredentials{Username: "admin", Password: "Stored-Pa55!", TLSSHA256: "c692252b"}, state: power.PowerCycleOffHard, netboot: true}
	if len(calls) != 1 || calls[0] != want {
		t.Fatalf("power calls %+v, want %+v", calls, want)
	}
	if got.Status.Install == nil || got.Status.Install.TriggeredAt == nil {
		t.Fatalf("install %+v, want it triggered", got.Status.Install)
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || last.Action != "pxe" || last.Error != "" {
		t.Fatalf("lastPowerAction %+v", last)
	}

	h.now = h.now.Add(time.Minute)
	h.reconcile(t, svcUUID)
	if len(calls) != 1 {
		t.Fatal("power-cycled the host a second time")
	}
}

func TestRackInstallLeavesAnOfflineHostWithoutAMTToAPerson(t *testing.T) {
	h := newInstallHarness(t, reinstalling(), otherEdge("ber1-edge-a", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false)}
	h.r.AMT = &RackAMT{FleetName: rackTestFleet, ProvisioningSecret: amtTestProvisioningSecret}
	h.r.AMTPower = func(context.Context, *infrav1.RackLinuxHost, string, amtCredentials, amtPowerChange) (amtResponse, error) {
		t.Fatal("powered a host whose AMT is not activated")
		return amtResponse{}, nil
	}

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got := h.reconcile(t, svcUUID)

	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "WaitingForNetboot" || !strings.Contains(c.Message, "by hand") {
		t.Fatalf("condition %+v", c)
	}
}

// AMT presents a self-signed certificate. The first power change pins the one
// it presented in the host's AMT Secret, and later ones hold AMT to it.
func TestRackAMTPowerPinsAMTsCertificate(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("cycle"), otherConnectedEdge(), amtSecret("Stored-Pa55!"))

	h.reconcile(t, edgeUUID)
	if (*calls)[0].creds.TLSSHA256 != "" {
		t.Fatalf("the first power change carried a pin: %+v", (*calls)[0])
	}
	secret := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: edgeUUID + "-amt"}, secret); err != nil {
		t.Fatal(err)
	}
	if string(secret.Data["tls-sha256"]) != "c692252b" || string(secret.Data["password"]) != "Stored-Pa55!" {
		t.Fatalf("secret %v, want the certificate pinned beside the password", secret.Data)
	}

	h.update(t, edgeUUID, func(host *infrav1.RackLinuxHost) {
		host.Annotations = map[string]string{RebootAnnotation: "reset"}
	})
	h.reconcile(t, edgeUUID)
	if len(*calls) != 2 || (*calls)[1].creds.TLSSHA256 != "c692252b" {
		t.Fatalf("calls %+v, want the second held to the pin", *calls)
	}
}

// Only the edge holding the site's floating addresses is on AMT's link, so a
// power change goes through the first edge that reaches AMT, and only there.
func TestRackAMTPowerGoesThroughTheEdgeOnAMTsLink(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("reset"), otherConnectedEdge(), amtSecret("Stored-Pa55!"))
	record := recordPower(calls)
	h.r.AMTPower = func(ctx context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, change amtPowerChange) (amtResponse, error) {
		if via.Name == "ber1-edge-b" {
			return amtResponse{}, fmt.Errorf("%w: ber1-edge-b routes 192.168.50.112 through a gateway", errAMTNotOnLink)
		}
		return record(ctx, via, address, creds, change)
	}

	got := h.reconcile(t, edgeUUID)

	if len(*calls) != 1 || (*calls)[0].via != edgeUUID {
		t.Fatalf("power calls %+v, want one through the host itself", *calls)
	}
	if last := got.Status.AMT.LastPowerAction; last.Via != edgeUUID || last.Error != "" {
		t.Fatalf("lastPowerAction %+v", last)
	}
}

// A power change AMT refused is not sent again through another edge.
func TestRackAMTPowerDoesNotRetryARefusalElsewhere(t *testing.T) {
	h, _ := newPowerHarness(t, activatedAMTEdge("cycle"), otherConnectedEdge(), amtSecret("Stored-Pa55!"))
	var vias []string
	h.r.AMTPower = func(_ context.Context, via *infrav1.RackLinuxHost, _ string, _ amtCredentials, change amtPowerChange) (amtResponse, error) {
		if change.read {
			return amtResponse{PowerState: rackPowerOn}, nil
		}
		vias = append(vias, via.Name)
		return amtResponse{}, fmt.Errorf("AMT at 192.168.50.112 refused power state 5: return value 2")
	}

	got := h.reconcile(t, edgeUUID)

	if len(vias) != 1 || !strings.Contains(got.Status.AMT.LastPowerAction.Error, "refused") {
		t.Fatalf("tried %v, last %+v", vias, got.Status.AMT.LastPowerAction)
	}
}

// A network boot sets AMT's next boot to the network, the way AMT takes it:
// clear the boot order, write the boot settings, make the configuration the
// next one, choose the source, then power-cycle.
func TestRequestAMTPowerNetbootsThroughAMTsBootConfiguration(t *testing.T) {
	var bodies, authorizations []string
	dial, _, _ := fakeAMT(t, "0", &bodies, &authorizations)

	if _, err := requestAMTPower(context.Background(), dial, "192.168.50.22", amtCredentials{Username: "admin", Password: "Secret-Pa55!"},
		amtPowerChange{state: power.PowerCycleOffHard, netboot: true}); err != nil {
		t.Fatal(err)
	}

	var steps []string
	for _, b := range bodies {
		switch {
		case strings.Contains(b, "ChangeBootOrder") && strings.Contains(b, "Force PXE Boot"):
			steps = append(steps, "order=pxe")
		case strings.Contains(b, "ChangeBootOrder"):
			steps = append(steps, "order=none")
		case strings.Contains(b, "SetBootConfigRole"):
			steps = append(steps, "role")
		case strings.Contains(b, "AMT_BootSettingData") && strings.Contains(b, "transfer/Put"):
			steps = append(steps, "settings")
		case strings.Contains(b, "AMT_BootSettingData"):
			steps = append(steps, "read")
		case strings.Contains(b, "RequestPowerStateChange"):
			steps = append(steps, "power")
		}
	}
	if got, want := strings.Join(steps, ","), "read,order=none,settings,role,order=pxe,power"; got != want {
		t.Fatalf("steps %s, want %s", got, want)
	}
}

func TestRequestAMTPowerLeavesTheBootAloneWithoutANetboot(t *testing.T) {
	var bodies, authorizations []string
	dial, _, _ := fakeAMT(t, "0", &bodies, &authorizations)

	if _, err := requestAMTPower(context.Background(), dial, "192.168.50.22", amtCredentials{Username: "admin", Password: "Secret-Pa55!"},
		amtPowerChange{state: power.PowerCycleOffHard}); err != nil {
		t.Fatal(err)
	}
	if len(bodies) != 1 || !strings.Contains(bodies[0], "RequestPowerStateChange") {
		t.Fatalf("sent %d requests, want only the power change", len(bodies))
	}
}

// A host connected to the tailnet is on, whatever AMT would say, so it is not
// asked.
func TestRackPowerTakesAConnectedHostToBeOn(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge(""), otherConnectedEdge(), amtSecret("Stored-Pa55!"))
	var reads int
	h.r.AMTPower = func(context.Context, *infrav1.RackLinuxHost, string, amtCredentials, amtPowerChange) (amtResponse, error) {
		reads++
		return amtResponse{}, nil
	}

	got := h.reconcile(t, edgeUUID)

	if reads != 0 || len(*calls) != 0 {
		t.Fatalf("asked AMT %d times", reads)
	}
	if got.Status.Power == nil || got.Status.Power.State != rackPowerOn || !conditions.IsTrue(got, PowerCondition) {
		t.Fatalf("power %+v condition %+v", got.Status.Power, conditions.Get(got, PowerCondition))
	}
}

// A host that should be on and that AMT reports off is powered on, once per
// backoff.
func TestRackPowerPowersOnAHostThatIsOff(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge(""), otherConnectedEdge(), amtSecret("Stored-Pa55!"))
	h.api.devices[0].ConnectedToControl = false
	h.r.AMTPower = recordPowerWhile(calls, rackPowerOff)

	got := h.reconcile(t, edgeUUID)

	if len(*calls) != 1 || (*calls)[0].state != power.PowerOn || (*calls)[0].via != "ber1-edge-b" {
		t.Fatalf("power calls %+v", *calls)
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || last.Action != "on" {
		t.Fatalf("lastPowerAction %+v", last)
	}

	h.now = installEpoch.Add(time.Minute)
	h.reconcile(t, edgeUUID)
	if len(*calls) != 1 {
		t.Fatal("powered the host on again inside the backoff")
	}
}

// A host that should be off is shut down from its own OS while it is on the
// tailnet, and powered off through AMT once it is not.
func TestRackPowerTakesAHostThatShouldBeOffDown(t *testing.T) {
	host := activatedAMTEdge("")
	host.Spec.Online = false
	h, calls := newPowerHarness(t, host, otherConnectedEdge(), amtSecret("Stored-Pa55!"))

	got := h.reconcile(t, edgeUUID)

	if len(*calls) != 0 {
		t.Fatalf("power calls %+v; a host on the tailnet is shut down from its OS", *calls)
	}
	shutDown := false
	for _, run := range h.runner.runs {
		shutDown = shutDown || strings.Contains(run.script, "systemctl poweroff")
	}
	if !shutDown {
		t.Fatal("the host was not shut down")
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || last.Action != "off" {
		t.Fatalf("lastPowerAction %+v", last)
	}

	h.api.devices[0].ConnectedToControl = false
	h.now = installEpoch.Add(amtPowerChangeBackoff + time.Minute)
	got = h.reconcile(t, edgeUUID)
	if len(*calls) != 1 || (*calls)[0].state != power.PowerOffHard {
		t.Fatalf("power calls %+v, want AMT to power off a host still on", *calls)
	}
	if got.Status.Power == nil || got.Status.Power.State != rackPowerOn {
		t.Fatalf("power %+v", got.Status.Power)
	}
}
