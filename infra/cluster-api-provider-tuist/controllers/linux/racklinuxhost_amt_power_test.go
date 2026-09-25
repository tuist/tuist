package linux

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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

// fakeAMT answers WS-MAN over TLS behind digest authentication, as an
// activated AMT does on 16993.
func fakeAMT(t *testing.T, returnValue string, bodies *[]string, authorizations *[]string) (dial func(context.Context, string, string) (net.Conn, error), dialled *[]string, fingerprint string) {
	t.Helper()
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
		_, _ = io.WriteString(w, strings.Replace(powerStateChangeResponse, "%s", returnValue, 1))
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

	pinned, err := requestAMTPower(context.Background(), dial, "192.168.50.112", amtCredentials{Username: "admin", Password: "Secret-Pa55!"}, power.PowerCycleOffHard)
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
	if pinned != fingerprint {
		t.Fatalf("pinned %q, want the certificate AMT presented, %q", pinned, fingerprint)
	}

	if _, err := requestAMTPower(context.Background(), dial, "192.168.50.112",
		amtCredentials{Username: "admin", Password: "Secret-Pa55!", TLSSHA256: strings.ToUpper(fingerprint)}, power.PowerOn); err != nil {
		t.Fatalf("refused the pinned certificate: %v", err)
	}
}

func TestRequestAMTPowerRefusesACertificateOtherThanThePinnedOne(t *testing.T) {
	var bodies, authorizations []string
	dial, _, _ := fakeAMT(t, "0", &bodies, &authorizations)

	_, err := requestAMTPower(context.Background(), dial, "192.168.50.112",
		amtCredentials{Username: "admin", Password: "Secret-Pa55!", TLSSHA256: strings.Repeat("ab", 32)}, power.PowerOn)
	if err == nil || len(bodies) != 0 {
		t.Fatalf("err = %v, bodies %v; want the request refused before it is sent", err, bodies)
	}
}

func TestRequestAMTPowerReportsARefusal(t *testing.T) {
	var bodies, authorizations []string
	dial, _, _ := fakeAMT(t, "2", &bodies, &authorizations)

	_, err := requestAMTPower(context.Background(), dial, "192.168.50.112", amtCredentials{Username: "admin", Password: "Secret-Pa55!"}, power.PowerOn)
	if err == nil || !strings.Contains(err.Error(), "2") {
		t.Fatalf("err = %v, want AMT's return value", err)
	}
}

type powerCall struct {
	via, address string
	creds        amtCredentials
	state        power.PowerState
}

func activatedAMTEdge(annotation string) *infrav1.RackLinuxHost {
	h := amtEdge()
	if annotation != "" {
		h.Annotations = map[string]string{AMTPowerAnnotation: annotation}
	}
	observed := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	h.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "192.168.50.112", ObservedAt: &observed}
	return h
}

func amtSecret(password string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge-amt", Namespace: rackTestNamespace},
		Data:       map[string][]byte{"username": []byte("admin"), "password": []byte(password)},
	}
}

func recordPower(calls *[]powerCall) amtPowerFunc {
	return func(_ context.Context, via *infrav1.RackLinuxHost, address string, creds amtCredentials, state power.PowerState) (string, error) {
		*calls = append(*calls, powerCall{via: via.Name, address: address, creds: creds, state: state})
		return "c692252b", nil
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

	got := h.reconcile(t, "ber1-edge")

	want := powerCall{via: "ber1-edge-b", address: "192.168.50.112", creds: amtCredentials{Username: "admin", Password: "Stored-Pa55!"}, state: power.PowerCycleOffHard}
	if len(*calls) != 1 || (*calls)[0] != want {
		t.Fatalf("power calls %+v, want %+v", *calls, want)
	}
	if _, ok := got.Annotations[AMTPowerAnnotation]; ok {
		t.Fatal("the annotation was not consumed")
	}
	last := got.Status.AMT.LastPowerAction
	if last == nil || last.Action != "cycle" || last.Via != "ber1-edge-b" || last.Error != "" || !last.At.Time.Equal(installEpoch) {
		t.Fatalf("lastPowerAction %+v", last)
	}
}

func TestRackAMTPowersAHostThatIsOffTheTailnet(t *testing.T) {
	host := activatedAMTEdge("on")
	h, calls := newPowerHarness(t, host, otherConnectedEdge(), amtSecret("Stored-Pa55!"), provisioningSecret())
	h.api.devices[0].ConnectedToControl = false

	h.reconcile(t, "ber1-edge")

	if len(*calls) != 1 || (*calls)[0].state != power.PowerOn || (*calls)[0].via != "ber1-edge-b" {
		t.Fatalf("power calls %+v", *calls)
	}
}

func TestRackAMTPowerNeedsActivatedAMT(t *testing.T) {
	host := activatedAMTEdge("reset")
	host.Status.AMT.ControlMode = "pre-provisioning"
	h, calls := newPowerHarness(t, host, otherConnectedEdge(), amtSecret("Stored-Pa55!"))

	got := h.reconcile(t, "ber1-edge")

	if len(*calls) != 0 {
		t.Fatal("asked a pre-provisioned AMT for a power change")
	}
	if _, ok := got.Annotations[AMTPowerAnnotation]; ok {
		t.Fatal("the annotation was not consumed")
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || last.Action != "reset" || !strings.Contains(last.Error, "not activated") {
		t.Fatalf("lastPowerAction %+v", last)
	}
}

func TestRackAMTPowerRefusesAnUnknownAction(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("reboot"), otherConnectedEdge(), amtSecret("Stored-Pa55!"))

	got := h.reconcile(t, "ber1-edge")

	if len(*calls) != 0 {
		t.Fatal("made a power change for an unknown action")
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || !strings.Contains(last.Error, "on, off, cycle or reset") {
		t.Fatalf("lastPowerAction %+v", last)
	}
}

func TestRackAMTPowerGoesThroughTheHostItselfWhenNoOtherEdgeIsUp(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("reset"), amtSecret("Stored-Pa55!"))

	h.reconcile(t, "ber1-edge")

	if len(*calls) != 1 || (*calls)[0].via != "ber1-edge" {
		t.Fatalf("power calls %+v", *calls)
	}
}

// A host off the tailnet cannot be rebooted into its installer over SSH. With
// its AMT activated, the operator power-cycles it instead, and the install
// stick, which the MS-01 boots first, installs what is published.
func TestRackInstallPowerCyclesAnOfflineHostThroughAMT(t *testing.T) {
	host := svcHost()
	host.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	observed := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "192.168.50.113", ObservedAt: &observed}
	secret := amtSecret("Stored-Pa55!")
	secret.Name = "ber1-svc-amt"
	h := newInstallHarness(t, host, otherEdge("ber1-edge-a", rackTestNamespace, "ber1", "edge", true), secret)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false)}
	h.r.AMT = &RackAMT{FleetName: rackTestFleet, ProvisioningSecret: amtTestProvisioningSecret}
	var calls []powerCall
	h.r.AMTPower = recordPower(&calls)

	h.reconcile(t, "ber1-svc")
	if len(calls) != 0 {
		t.Fatal("power-cycled the host before the boot server could serve its install")
	}

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got := h.reconcile(t, "ber1-svc")
	want := powerCall{via: "ber1-edge-a", address: "192.168.50.113", creds: amtCredentials{Username: "admin", Password: "Stored-Pa55!"}, state: power.PowerCycleOffHard}
	if len(calls) != 1 || calls[0] != want {
		t.Fatalf("power calls %+v, want %+v", calls, want)
	}
	if got.Status.Install == nil || got.Status.Install.TriggeredAt == nil {
		t.Fatalf("install %+v, want it triggered", got.Status.Install)
	}
	if last := got.Status.AMT.LastPowerAction; last == nil || last.Action != "cycle" || last.Error != "" {
		t.Fatalf("lastPowerAction %+v", last)
	}

	h.now = h.now.Add(time.Minute)
	h.reconcile(t, "ber1-svc")
	if len(calls) != 1 {
		t.Fatal("power-cycled the host a second time")
	}
}

func TestRackInstallLeavesAnOfflineHostWithoutAMTToAPerson(t *testing.T) {
	host := svcHost()
	host.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	h := newInstallHarness(t, host, otherEdge("ber1-edge-a", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false)}
	h.r.AMT = &RackAMT{FleetName: rackTestFleet, ProvisioningSecret: amtTestProvisioningSecret}
	h.r.AMTPower = func(context.Context, *infrav1.RackLinuxHost, string, amtCredentials, power.PowerState) (string, error) {
		t.Fatal("powered a host whose AMT is not activated")
		return "", nil
	}

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got := h.reconcile(t, "ber1-svc")

	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "WaitingForNetboot" || !strings.Contains(c.Message, "by hand") {
		t.Fatalf("condition %+v", c)
	}
}

// AMT presents a self-signed certificate. The first power change pins the one
// it presented in the host's AMT Secret, and later ones hold AMT to it.
func TestRackAMTPowerPinsAMTsCertificate(t *testing.T) {
	h, calls := newPowerHarness(t, activatedAMTEdge("cycle"), otherConnectedEdge(), amtSecret("Stored-Pa55!"))

	h.reconcile(t, "ber1-edge")
	if (*calls)[0].creds.TLSSHA256 != "" {
		t.Fatalf("the first power change carried a pin: %+v", (*calls)[0])
	}
	secret := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge-amt"}, secret); err != nil {
		t.Fatal(err)
	}
	if string(secret.Data["tls-sha256"]) != "c692252b" || string(secret.Data["password"]) != "Stored-Pa55!" {
		t.Fatalf("secret %v, want the certificate pinned beside the password", secret.Data)
	}

	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge"}, host); err != nil {
		t.Fatal(err)
	}
	host.Annotations = map[string]string{AMTPowerAnnotation: "on"}
	if err := h.c.Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
	h.reconcile(t, "ber1-edge")
	if len(*calls) != 2 || (*calls)[1].creds.TLSSHA256 != "c692252b" {
		t.Fatalf("calls %+v, want the second held to the pin", *calls)
	}
}
