package linux

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

const (
	svcMAC     = "38:05:25:38:b5:b5"
	svcMACPath = "38-05-25-38-b5-b5"
)

var installEpoch = time.Date(2026, 9, 24, 8, 0, 0, 0, time.UTC)

// tailnetKeyDescriptionRule is what the Tailscale API accepts as a key's
// description, and refuses anything else with HTTP 400.
var tailnetKeyDescriptionRule = regexp.MustCompile(`^[A-Za-z0-9 -]{0,50}$`)

func (f *fakeTailnet) CreateAuthKey(_ context.Context, tags []string, expiry time.Duration, description string) (tailnet.AuthKey, error) {
	if !tailnetKeyDescriptionRule.MatchString(description) {
		return tailnet.AuthKey{}, fmt.Errorf(`HTTP 400: {"message":"keys: description had invalid characters"}: %q`, description)
	}
	f.minted = append(f.minted, strings.Join(tags, ","))
	id := fmt.Sprintf("kMINT%dCNTRL", len(f.minted))
	return tailnet.AuthKey{ID: id, Key: "tskey-auth-" + id + "-secret", Expires: installEpoch.Add(expiry).Format(time.RFC3339)}, nil
}

func (f *fakeTailnet) DeleteAuthKey(_ context.Context, id string) error {
	f.revoked = append(f.revoked, id)
	return nil
}

func svcHost() *infrav1.RackLinuxHost {
	return &infrav1.RackLinuxHost{
		ObjectMeta: metav1.ObjectMeta{Name: svcUUID, Namespace: rackTestNamespace},
		Spec: infrav1.RackLinuxHostSpec{
			Hostname: "ber1-svc",
			Online:   true,
			Role:     "services",
			Location: infrav1.RackHostLocation{Site: "ber1"},
			SSHUser:  "tuist",
			Tailnet:  infrav1.RackLinuxHostTailnet{Tags: []string{"tag:tuist-rack-node"}},
			BootMAC:  svcMAC,
		},
	}
}

func svcDevice(id, created string, connected bool) tailnet.Device {
	return tailnet.Device{
		NodeID:             id,
		Name:               "ber1-svc.example.ts.net",
		Hostname:           "ber1-svc",
		Addresses:          []string{"100.64.0.9"},
		Tags:               []string{"tag:tuist-rack-node"},
		Created:            created,
		ConnectedToControl: connected,
	}
}

type installHarness struct {
	r      *RackLinuxHostReconciler
	c      client.Client
	api    *fakeTailnet
	runner *fakeRunner
	now    time.Time
}

func newInstallHarness(t *testing.T, objs ...runtime.Object) *installHarness {
	t.Helper()
	objs = append(objs, &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-ssh", Namespace: rackTestNamespace},
		Data:       map[string][]byte{"id_ed25519": testFleetPrivateKey(t)},
	})
	c := fake.NewClientBuilder().WithScheme(rackTestScheme(t)).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackLinuxHost{}).Build()
	h := &installHarness{c: c, api: &fakeTailnet{}, runner: &fakeRunner{}, now: installEpoch}
	h.r = &RackLinuxHostReconciler{
		Client:             c,
		Recorder:           record.NewFakeRecorder(50),
		Tailnet:            h.api,
		CredentialsManager: &credentials.Manager{Client: c, Namespace: rackTestNamespace},
		Install: &RackInstall{
			FleetName:      rackTestFleet,
			ServerURL:      "http://192.168.50.1:8480",
			AuthorizedKeys: []string{"ssh-ed25519 AAAAHUMAN someone"},
		},
		EgressNamespace:  "tailscale-operator",
		EgressProxyGroup: "macmini-egress",
		RunScript:        h.runner.run,
		Now:              func() time.Time { return h.now },
	}
	return h
}

func (h *installHarness) reconcile(t *testing.T, name string) *infrav1.RackLinuxHost {
	t.Helper()
	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: name}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, host); err != nil {
		t.Fatal(err)
	}
	return host
}

// update changes a host the way a person or Helm does, between reconciles.
func (h *installHarness) update(t *testing.T, name string, change func(*infrav1.RackLinuxHost)) {
	t.Helper()
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, host); err != nil {
		t.Fatal(err)
	}
	change(host)
	if err := h.c.Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
}

func (h *installHarness) boot(t *testing.T) map[string][]byte {
	t.Helper()
	secret := &corev1.Secret{}
	err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: rackTestFleet + "-boot"}, secret)
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	return secret.Data
}

// servable reports the host's published install servable, as the boot server
// holding the site's provisioning address does.
func (h *installHarness) servable(t *testing.T, name string) {
	t.Helper()
	h.reportedBy(t, name, "ber1-edge-b", true)
}

// reportedBy reports the host's published install servable by node's boot
// server.
func (h *installHarness) reportedBy(t *testing.T, name, node string, holdsAddress bool) {
	t.Helper()
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, host); err != nil {
		t.Fatal(err)
	}
	if host.Status.Install == nil {
		t.Fatal("no install is published")
	}
	if host.Status.Boot == nil || host.Status.Boot.KeyID != host.Status.Install.KeyID {
		host.Status.Boot = &infrav1.RackLinuxHostBootStatus{KeyID: host.Status.Install.KeyID}
	}
	host.Status.Boot.Servers = append(host.Status.Boot.Servers, infrav1.RackLinuxHostBootServer{Node: node, HoldsAddress: holdsAddress, At: metav1.NewTime(h.now)})
	if err := h.c.Status().Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
}

func withInstall(host *infrav1.RackLinuxHost, keyID, previous string, offered time.Time, triggered *time.Time) *infrav1.RackLinuxHost {
	host.Status.Install = &infrav1.RackLinuxHostInstallStatus{
		KeyID:            keyID,
		BootMAC:          host.Spec.BootMAC,
		Generation:       host.Spec.ReinstallGeneration,
		PreviousDeviceID: previous,
		OfferedAt:        metav1.NewTime(offered),
		ExpiresAt:        metav1.NewTime(offered.Add(rackInstallKeyLifetime)),
	}
	if triggered != nil {
		t := metav1.NewTime(*triggered)
		host.Status.Install.TriggeredAt = &t
	}
	return host
}

// reinstalling is svcHost asking for its first reinstall.
func reinstalling() *infrav1.RackLinuxHost {
	host := svcHost()
	host.Spec.ReinstallGeneration = 1
	return host
}

func publishedBoot(keyID string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-boot", Namespace: rackTestNamespace},
		Data: map[string][]byte{
			svcMACPath + ".user-data":     []byte("#cloud-config " + keyID),
			svcMACPath + ".meta-data":     []byte("instance-id: x"),
			svcMACPath + ".ipxe":          []byte("#!ipxe"),
			svcMACPath + ".uuid":          []byte(svcUUID),
			svcMACPath + ".install":       []byte(keyID),
			"aa-bb-cc-dd-ee-ff.ipxe":      []byte("another host"),
			"aa-bb-cc-dd-ee-ff.user-data": []byte("another host"),
			"aa-bb-cc-dd-ee-ff.meta-data": []byte("another host"),
		},
	}
}

func TestRackInstallPublishesAnInstallForAHostNotOnTheTailnet(t *testing.T) {
	h := newInstallHarness(t, svcHost())
	host := h.reconcile(t, svcUUID)

	if len(h.api.minted) != 1 || h.api.minted[0] != "tag:tuist-rack-node" {
		t.Fatalf("minted %v, want one key tagged with the host's tags", h.api.minted)
	}
	inst := host.Status.Install
	if inst == nil || inst.KeyID != "kMINT1CNTRL" || inst.BootMAC != svcMAC || inst.PreviousDeviceID != "" || inst.TriggeredAt != nil || inst.Generation != 0 {
		t.Fatalf("install status %+v", inst)
	}
	if !inst.ExpiresAt.Time.Equal(installEpoch.Add(rackInstallKeyLifetime)) {
		t.Fatalf("expires %v", inst.ExpiresAt)
	}
	c := conditions.Get(host, InstalledCondition)
	if c == nil || c.Status != corev1.ConditionFalse || c.Reason != "WaitingForNetboot" {
		t.Fatalf("Installed condition %+v", c)
	}
	if p := host.Status.Provisioning; p.State != infrav1.RackLinuxHostProvisioning || p.LastTransitionTime == nil {
		t.Fatalf("provisioning %+v", p)
	}

	boot := h.boot(t)
	userData := string(boot[svcMACPath+".user-data"])
	for _, want := range []string{
		"hostname: ber1-svc",
		"tskey-auth-kMINT1CNTRL-secret",
		"ssh-ed25519 AAAAHUMAN someone",
		" " + rackTestFleet + "\"",
		"TAILNET_TAGS=%s\\n' 'tag:tuist-rack-node'",
	} {
		if !strings.Contains(userData, want) {
			t.Errorf("user-data lacks %q", want)
		}
	}
	if string(boot[svcMACPath+".meta-data"]) != "instance-id: ber1-svc-kmint1cntrl\nlocal-hostname: ber1-svc\n" {
		t.Errorf("meta-data %q", boot[svcMACPath+".meta-data"])
	}
	if script := string(boot[svcMACPath+".ipxe"]); !strings.Contains(script, "BOOTIF=01-"+svcMACPath) || !strings.Contains(script, "s=http://192.168.50.1:8480/hosts/"+svcMACPath+"/") {
		t.Errorf("ipxe %q", script)
	}
	if string(boot[svcMACPath+".uuid"]) != svcUUID {
		t.Errorf("uuid %q, want the host's, which a network boot from another NIC asks for", boot[svcMACPath+".uuid"])
	}
	if string(boot[svcMACPath+".install"]) != "kMINT1CNTRL" {
		t.Errorf("install %q, want the join key's ID, which the boot server reports on", boot[svcMACPath+".install"])
	}
	if !strings.HasPrefix(inst.HostKeyFingerprint, "SHA256:") || !strings.Contains(userData, "/target/etc/ssh/ssh_host_ed25519_key") {
		t.Errorf("host key %q; the install gives the host the key the operator trusts it by", inst.HostKeyFingerprint)
	}

	console := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: rackTestFleet + "-console"}, console); err != nil {
		t.Fatal(err)
	}
	if len(console.Data[svcUUID]) != rackConsolePasswordChars {
		t.Fatalf("console password %q", console.Data[svcUUID])
	}
	if strings.Contains(userData, string(console.Data[svcUUID])) {
		t.Fatal("the console password is in the seed in the clear")
	}
}

// laggingCache returns the host once as it was before the last reconcile, as
// the operator's cache does until that reconcile's status patch reaches it.
type laggingCache struct {
	client.Client
	stale *infrav1.RackLinuxHost
}

func (c *laggingCache) Get(ctx context.Context, key client.ObjectKey, obj client.Object, opts ...client.GetOption) error {
	if host, ok := obj.(*infrav1.RackLinuxHost); ok && c.stale != nil && key.Name == c.stale.Name {
		c.stale.DeepCopyInto(host)
		c.stale = nil
		return nil
	}
	return c.Client.Get(ctx, key, obj, opts...)
}

func TestRackInstallMintsOneKeyWhileTheCacheLagsBehindTheInstall(t *testing.T) {
	h := newInstallHarness(t, svcHost())
	before := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: svcUUID}, before); err != nil {
		t.Fatal(err)
	}
	h.reconcile(t, svcUUID)

	h.r.Client, h.r.APIReader = &laggingCache{Client: h.c, stale: before}, h.c
	_, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: svcUUID}})

	if len(h.api.minted) != 1 {
		t.Fatalf("minted %v; the install the cache has not seen yet is kept", h.api.minted)
	}
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
}

func TestRackInstallWithdrawsTheInstallOnceTheHostJoins(t *testing.T) {
	h := newInstallHarness(t, withInstall(svcHost(), "kMINT1CNTRL", "", installEpoch.Add(-30*time.Minute), nil), publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("new", "2026-09-24T07:50:00Z", true)}
	host := h.reconcile(t, svcUUID)

	if host.Status.Install != nil {
		t.Fatalf("install %+v, want it withdrawn", host.Status.Install)
	}
	if !conditions.IsTrue(host, InstalledCondition) || host.Status.Provisioning.State != infrav1.RackLinuxHostProvisioned {
		t.Fatalf("Installed %+v provisioning %+v", conditions.Get(host, InstalledCondition), host.Status.Provisioning)
	}
	boot := h.boot(t)
	for _, suffix := range []string{".user-data", ".meta-data", ".ipxe"} {
		if _, ok := boot[svcMACPath+suffix]; ok {
			t.Errorf("%s is still published", suffix)
		}
		if _, ok := boot["aa-bb-cc-dd-ee-ff"+suffix]; !ok {
			t.Errorf("another host's %s was withdrawn", suffix)
		}
	}
	if len(h.api.minted) != 0 {
		t.Fatalf("minted %v", h.api.minted)
	}
}

// A host is reinstalled by raising spec.reinstallGeneration, and the
// generation its install ran for is recorded once the new install joins.
func TestRackInstallReinstallsARunningHost(t *testing.T) {
	h := newInstallHarness(t, reinstalling())
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}

	got := h.reconcile(t, svcUUID)
	if got.Status.Install == nil || got.Status.Install.PreviousDeviceID != "old" || got.Status.Install.TriggeredAt != nil || got.Status.Install.Generation != 1 {
		t.Fatalf("install %+v", got.Status.Install)
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the host before the boot server could serve its install")
	}

	h.servable(t, svcUUID)
	got = h.reconcile(t, svcUUID)
	if len(h.runner.runs) != 1 {
		t.Fatalf("runs %d, want the netboot-once script", len(h.runner.runs))
	}
	run := h.runner.runs[0]
	if run.host != "rack-linux-"+svcUUID+".tailscale-operator.svc.cluster.local" || !strings.Contains(run.script, "mac=380525"+"38b5b5") {
		t.Fatalf("run %+v", run)
	}
	if got.Status.Install.TriggeredAt == nil || len(h.api.minted) != 1 || got.Status.Provisioning.State != infrav1.RackLinuxHostProvisioning {
		t.Fatalf("install %+v minted %v provisioning %+v", got.Status.Install, h.api.minted, got.Status.Provisioning)
	}

	h.now = h.now.Add(time.Minute)
	got = h.reconcile(t, svcUUID)
	if len(h.runner.runs) != 1 {
		t.Fatal("rebooted the host a second time")
	}

	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false), svcDevice("new", "2026-09-24T08:20:00Z", true)}
	got = h.reconcile(t, svcUUID)
	if got.Status.Install != nil || got.Status.Provisioning.InstalledGeneration != 1 || got.Status.Provisioning.State != infrav1.RackLinuxHostProvisioned {
		t.Fatalf("install %+v provisioning %+v, want the reinstall finished at generation 1", got.Status.Install, got.Status.Provisioning)
	}
	if !conditions.IsTrue(got, InstalledCondition) {
		t.Fatal("Installed is not True")
	}

	h.now = h.now.Add(time.Hour)
	h.reconcile(t, svcUUID)
	if len(h.api.minted) != 1 || len(h.runner.runs) != 1 {
		t.Fatalf("minted %v runs %d; the installed generation is not installed again", h.api.minted, len(h.runner.runs))
	}
}

// A generation raised while an install for the previous one is published
// replaces it.
func TestRackInstallPublishesAgainForAGenerationRaisedMeanwhile(t *testing.T) {
	host := withInstall(reinstalling(), "kOLDCNTRL", "old", installEpoch.Add(-time.Minute), nil)
	host.Spec.ReinstallGeneration = 2
	h := newInstallHarness(t, host, publishedBoot("kOLDCNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}

	got := h.reconcile(t, svcUUID)

	inst := got.Status.Install
	if len(h.api.minted) != 1 || inst == nil || inst.KeyID != "kMINT1CNTRL" || inst.Generation != 2 || inst.PreviousDeviceID != "old" {
		t.Fatalf("install %+v minted %v", inst, h.api.minted)
	}
}

func TestRackInstallReportsAReinstallThatDidNotNetboot(t *testing.T) {
	triggered := installEpoch.Add(-rackReinstallBootTimeout - time.Minute)
	h := newInstallHarness(t, withInstall(reinstalling(), "kMINT1CNTRL", "old", triggered.Add(-time.Minute), &triggered), publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	got := h.reconcile(t, svcUUID)
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "ReinstallDidNotBoot" || !strings.Contains(c.Message, "reinstallGeneration") {
		t.Fatalf("Installed %+v", c)
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the host again")
	}
}

// Lowering the generation back to the installed one cancels the reinstall.
func TestRackInstallWithdrawsWhenTheReinstallIsCancelled(t *testing.T) {
	cancelled := withInstall(reinstalling(), "kMINT1CNTRL", "old", installEpoch.Add(-time.Minute), nil)
	cancelled.Spec.ReinstallGeneration = 0
	h := newInstallHarness(t, cancelled, publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	got := h.reconcile(t, svcUUID)
	if got.Status.Install != nil || h.boot(t)[svcMACPath+".user-data"] != nil || len(h.runner.runs) != 0 {
		t.Fatalf("install %+v runs %d, want it withdrawn untouched", got.Status.Install, len(h.runner.runs))
	}
	if got.Status.Provisioning.State != infrav1.RackLinuxHostProvisioned {
		t.Fatalf("provisioning %+v", got.Status.Provisioning)
	}
}

// A host whose spec.online is false is not rebooted into its install.
func TestRackInstallDoesNotRebootAHostThatShouldBeOff(t *testing.T) {
	host := reinstalling()
	host.Spec.Online = false
	h := newInstallHarness(t, host)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	h.reconcile(t, svcUUID)
	h.servable(t, svcUUID)
	got := h.reconcile(t, svcUUID)
	for _, run := range h.runner.runs {
		if strings.Contains(run.script, "efibootmgr") {
			t.Fatal("a host that should be off was rebooted into its installer")
		}
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "Offline" {
		t.Fatalf("Installed %+v", c)
	}
}

func installableEdge() *infrav1.RackLinuxHost {
	host := edgeHost()
	host.Spec.BootMAC = svcMAC
	return host
}

func otherEdge(name, namespace, site, role string, connected bool) *infrav1.RackLinuxHost {
	host := edgeHost()
	host.Name, host.Namespace = name, namespace
	host.Spec.Hostname = name
	host.Spec.Role = role
	host.Spec.Location.Site = site
	host.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: name + "-device", Name: name + ".example.ts.net", Address: "100.64.0.20", Connected: connected}
	return host
}

func TestRackInstallPublishesForAnEdgeAnotherEdgeOfItsSiteServes(t *testing.T) {
	h := newInstallHarness(t, installableEdge(), otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true))
	got := h.reconcile(t, edgeUUID)

	if len(h.api.minted) != 1 || h.api.minted[0] != "tag:tuist-rack-edge" {
		t.Fatalf("minted %v, want one key tagged with the edge's tags", h.api.minted)
	}
	if got.Status.Install == nil || got.Status.Install.BootMAC != svcMAC {
		t.Fatalf("install %+v", got.Status.Install)
	}
	boot := h.boot(t)
	for _, suffix := range []string{".ipxe", ".user-data", ".meta-data"} {
		if _, ok := boot[svcMACPath+suffix]; !ok {
			t.Errorf("%s is not published", suffix)
		}
	}
	if !strings.Contains(string(boot[svcMACPath+".user-data"]), "hostname: ber1-edge") {
		t.Error("the published seed is not the edge's")
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "WaitingForNetboot" {
		t.Fatalf("Installed %+v", c)
	}
}

func TestRackInstallNeverPublishesForAnEdgeNoOtherEdgeServes(t *testing.T) {
	for name, others := range map[string][]runtime.Object{
		"the only edge":                  nil,
		"the other edge is disconnected": {otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", false)},
		"the other edge is off the tailnet": {func() runtime.Object {
			o := otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true)
			o.Status.Tailnet = nil
			return o
		}()},
		"the other edge is in another site":      {otherEdge("fra1-edge", rackTestNamespace, "fra1", "edge", true)},
		"the other edge is in another namespace": {otherEdge("ber1-edge-b", "tuist-production", "ber1", "edge", true)},
		"the connected host is not an edge":      {otherEdge("ber1-svc", rackTestNamespace, "ber1", "services", true)},
		"the connected edge is being deleted": {func() runtime.Object {
			o := otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true)
			o.Finalizers = []string{RackLinuxHostFinalizer}
			now := metav1.NewTime(installEpoch)
			o.DeletionTimestamp = &now
			return o
		}()},
	} {
		t.Run(name, func(t *testing.T) {
			h := newInstallHarness(t, append([]runtime.Object{installableEdge()}, others...)...)
			got := h.reconcile(t, edgeUUID)
			if len(h.api.minted) != 0 || got.Status.Install != nil || h.boot(t) != nil {
				t.Fatalf("minted %v install %+v", h.api.minted, got.Status.Install)
			}
			c := conditions.Get(got, InstalledCondition)
			if c == nil || c.Reason != "ServesTheNetboot" || !strings.Contains(c.Message, "no other edge of site ber1") || !strings.Contains(c.Message, "rack:write-install-usb") {
				t.Fatalf("Installed %+v", c)
			}
			if got.Status.Provisioning.State != infrav1.RackLinuxHostRegistering {
				t.Fatalf("provisioning %+v", got.Status.Provisioning)
			}
		})
	}
}

func reinstallingEdge() *infrav1.RackLinuxHost {
	host := installableEdge()
	host.Spec.ReinstallGeneration = 1
	return host
}

func TestRackInstallWithdrawsAnEdgeInstallWhoseServingEdgeWentAway(t *testing.T) {
	h := newInstallHarness(t, reinstallingEdge(), otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{edgeDevice("old", "ber1-edge", "2026-09-01T00:00:00Z", true, "100.64.0.7")}

	got := h.reconcile(t, edgeUUID)
	if got.Status.Install == nil || got.Status.Install.PreviousDeviceID != "old" {
		t.Fatalf("install %+v, want one published while ber1-edge-b serves", got.Status.Install)
	}

	serving := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge-b"}, serving); err != nil {
		t.Fatal(err)
	}
	serving.Status.Tailnet.Connected = false
	if err := h.c.Status().Update(context.Background(), serving); err != nil {
		t.Fatal(err)
	}

	h.servable(t, edgeUUID)
	got = h.reconcile(t, edgeUUID)
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the edge into a netboot no other edge serves")
	}
	if got.Status.Install != nil {
		t.Fatalf("install %+v, want it withdrawn", got.Status.Install)
	}
	for _, suffix := range []string{".user-data", ".meta-data", ".ipxe"} {
		if _, ok := h.boot(t)[svcMACPath+suffix]; ok {
			t.Errorf("%s is still published", suffix)
		}
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "ServesTheNetboot" {
		t.Fatalf("Installed %+v", c)
	}
}

func TestRackInstallKeepsAnEdgeInstallItAlreadyRebootedIntoWhenItsServingEdgeDrops(t *testing.T) {
	h := newInstallHarness(t, reinstallingEdge(), otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{edgeDevice("old", "ber1-edge", "2026-09-01T00:00:00Z", true, "100.64.0.7")}

	h.reconcile(t, edgeUUID)
	h.servable(t, edgeUUID)
	got := h.reconcile(t, edgeUUID)
	if len(h.runner.runs) != 1 || got.Status.Install == nil || got.Status.Install.TriggeredAt == nil {
		t.Fatalf("runs %d install %+v, want the edge rebooted into its netboot", len(h.runner.runs), got.Status.Install)
	}

	serving := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge-b"}, serving); err != nil {
		t.Fatal(err)
	}
	serving.Status.Tailnet.Connected = false
	if err := h.c.Status().Update(context.Background(), serving); err != nil {
		t.Fatal(err)
	}

	h.now = h.now.Add(time.Minute)
	got = h.reconcile(t, edgeUUID)
	if got.Status.Install == nil {
		t.Fatal("withdrew the install the edge was already rebooted into")
	}
	if _, ok := h.boot(t)[svcMACPath+".ipxe"]; !ok {
		t.Error("the install's iPXE script is no longer published")
	}
	if len(h.runner.runs) != 1 {
		t.Fatalf("rebooted the edge %d times", len(h.runner.runs))
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "Reinstalling" {
		t.Fatalf("Installed %+v", c)
	}
}

// A host with no boot MAC declared and none announced waits for its stick.
func TestRackInstallWaitsForTheBootMACOfAHostThatHasNotAnnounced(t *testing.T) {
	host := svcHost()
	host.Spec.BootMAC = ""
	h := newInstallHarness(t, host)
	got := h.reconcile(t, svcUUID)
	if len(h.api.minted) != 0 || got.Status.Install != nil {
		t.Fatalf("minted %v install %+v", h.api.minted, got.Status.Install)
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "NoBootMAC" {
		t.Fatalf("Installed %+v", c)
	}
	if got.Status.Provisioning.State != infrav1.RackLinuxHostRegistering {
		t.Fatalf("provisioning %+v", got.Status.Provisioning)
	}
}

// The boot MAC a machine announced from its stick is the one an install is
// published under when the host declares none, and the host takes its model
// from the announcement too.
func TestRackInstallPublishesUnderTheBootMACTheMachineAnnounced(t *testing.T) {
	host := svcHost()
	host.Spec.BootMAC = ""
	announced := &infrav1.RackLinuxCandidate{
		ObjectMeta: metav1.ObjectMeta{Name: svcUUID, Namespace: rackTestNamespace},
		Status:     infrav1.RackLinuxCandidateStatus{UUID: svcUUID, BootMAC: svcMAC, Product: "Micro Computer (HK) Tech Limited Venus Series", Serial: "MD148LS139QQMQE00070"},
	}
	h := newInstallHarness(t, host, announced)

	got := h.reconcile(t, svcUUID)

	if got.Status.BootMAC != svcMAC || got.Status.Install == nil || got.Status.Install.BootMAC != svcMAC {
		t.Fatalf("bootMAC %q install %+v", got.Status.BootMAC, got.Status.Install)
	}
	if hw := got.Status.Hardware; hw == nil || hw.Product != "Micro Computer (HK) Tech Limited Venus Series" || hw.Serial != "MD148LS139QQMQE00070" {
		t.Fatalf("hardware %+v", got.Status.Hardware)
	}
}

func TestRackInstallKeepsTheConsolePasswordAcrossInstalls(t *testing.T) {
	h := newInstallHarness(t, svcHost(), &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-console", Namespace: rackTestNamespace},
		Data:       map[string][]byte{svcUUID: []byte("kept-password")},
	})
	h.reconcile(t, svcUUID)
	console := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: rackTestFleet + "-console"}, console); err != nil {
		t.Fatal(err)
	}
	if string(console.Data[svcUUID]) != "kept-password" {
		t.Fatalf("console password replaced with %q", console.Data[svcUUID])
	}
}

func TestRackInstallPublishesAgainWhenTheBootSecretLostIt(t *testing.T) {
	stale := publishedBoot("kOLDCNTRL")
	delete(stale.Data, svcMACPath+".ipxe")
	stale.Data[svcMACPath+".grub.cfg"] = []byte("set timeout=0")
	h := newInstallHarness(t, withInstall(svcHost(), "kOLDCNTRL", "", installEpoch.Add(-time.Hour), nil), stale)
	host := h.reconcile(t, svcUUID)
	if len(h.api.minted) != 1 || host.Status.Install.KeyID != "kMINT1CNTRL" {
		t.Fatalf("minted %v, install %+v; an install the boot server no longer has is published again", h.api.minted, host.Status.Install)
	}
	if !strings.Contains(string(h.boot(t)[svcMACPath+".ipxe"]), "BOOTIF=01-"+svcMACPath) {
		t.Fatal("the host's iPXE script is not published")
	}
}

func drainEvents(h *installHarness) []string {
	var out []string
	events := h.r.Recorder.(*record.FakeRecorder).Events
	for {
		select {
		case e := <-events:
			out = append(out, e)
		default:
			return out
		}
	}
}

// The operator reboots a host into its install once the boot server holding
// the site's provisioning address reports it servable, however long that
// takes, and not on another install's report.
func TestRackInstallRebootsAHostOnlyOnceTheBootServerServesItsInstall(t *testing.T) {
	h := newInstallHarness(t, reinstalling())
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	h.reconcile(t, svcUUID)

	h.now = installEpoch.Add(time.Hour)
	h.update(t, svcUUID, func(*infrav1.RackLinuxHost) {})
	stale := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: svcUUID}, stale); err != nil {
		t.Fatal(err)
	}
	at := metav1.NewTime(installEpoch)
	stale.Status.Boot = &infrav1.RackLinuxHostBootStatus{KeyID: "kEARLIERCNTRL", Servers: []infrav1.RackLinuxHostBootServer{{Node: "ber1-edge-b", HoldsAddress: true, At: at}}}
	if err := h.c.Status().Update(context.Background(), stale); err != nil {
		t.Fatal(err)
	}
	got := h.reconcile(t, svcUUID)
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the host before the boot server reported its install servable")
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "WaitingForBootServer" || !strings.Contains(c.Message, "192.168.50.1") {
		t.Fatalf("Installed %+v", c)
	}

	h.reportedBy(t, svcUUID, "ber1-edge-a", false)
	h.reconcile(t, svcUUID)
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the host on the report of a boot server not holding the provisioning address")
	}

	h.servable(t, svcUUID)
	got = h.reconcile(t, svcUUID)
	if len(h.runner.runs) != 1 || got.Status.Install.TriggeredAt == nil {
		t.Fatalf("runs %d install %+v, want the host rebooted into its install", len(h.runner.runs), got.Status.Install)
	}
}

// An edge's own boot server goes down with it, and another edge takes the
// provisioning address over, so the edge is rebooted into its install only
// once every other edge of its site holds it.
func TestRackInstallRebootsAnEdgeOnlyOnceTheOtherEdgesHoldItsInstall(t *testing.T) {
	h := newInstallHarness(t, reinstallingEdge(),
		otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true),
		otherEdge("ber1-edge-c", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{edgeDevice("old", "ber1-edge", "2026-09-01T00:00:00Z", true, "100.64.0.7")}
	h.reconcile(t, edgeUUID)

	h.reportedBy(t, edgeUUID, "ber1-edge", true)
	got := h.reconcile(t, edgeUUID)
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the edge on its own boot server's report")
	}
	c := conditions.Get(got, InstalledCondition)
	if c == nil || c.Reason != "WaitingForBootServer" || !strings.Contains(c.Message, "ber1-edge-b, ber1-edge-c") {
		t.Fatalf("Installed %+v", c)
	}

	h.reportedBy(t, edgeUUID, "ber1-edge-b", false)
	got = h.reconcile(t, edgeUUID)
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the edge before ber1-edge-c, which may take the address over, held its install")
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || strings.Contains(c.Message, "ber1-edge-b") || !strings.Contains(c.Message, "ber1-edge-c") {
		t.Fatalf("Installed %+v", c)
	}

	h.reportedBy(t, edgeUUID, "ber1-edge-c", false)
	got = h.reconcile(t, edgeUUID)
	if len(h.runner.runs) != 1 || got.Status.Install.TriggeredAt == nil {
		t.Fatalf("runs %d install %+v, want the edge rebooted into its install", len(h.runner.runs), got.Status.Install)
	}
}

// A join key lives two hours. One not yet handed out is renewed well before it
// expires; one a host already fetched is kept until it expires, since renewing
// it would not reach that installer.
func TestRackInstallRenewsAJoinKeyOnlyWhileNoHostHasIt(t *testing.T) {
	if rackInstallKeyLifetime != 2*time.Hour {
		t.Fatalf("join keys live %v", rackInstallKeyLifetime)
	}
	offered := installEpoch.Add(-rackInstallKeyLifetime + rackInstallRenewBefore - time.Minute)

	h := newInstallHarness(t, withInstall(svcHost(), "kOLDCNTRL", "", installEpoch.Add(-30*time.Minute), nil), publishedBoot("kOLDCNTRL"))
	if host := h.reconcile(t, svcUUID); len(h.api.minted) != 0 || host.Status.Install.KeyID != "kOLDCNTRL" {
		t.Fatalf("minted %v, install %+v; a fresh offer is kept", h.api.minted, host.Status.Install)
	}

	h = newInstallHarness(t, withInstall(svcHost(), "kOLDCNTRL", "", offered, nil), publishedBoot("kOLDCNTRL"))
	host := h.reconcile(t, svcUUID)
	if len(h.api.minted) != 1 || host.Status.Install.KeyID != "kMINT1CNTRL" {
		t.Fatalf("minted %v, install %+v; a key nobody fetched is renewed before it expires", h.api.minted, host.Status.Install)
	}
	if len(h.api.revoked) != 1 || h.api.revoked[0] != "kOLDCNTRL" {
		t.Fatalf("revoked %v, want the key it replaced", h.api.revoked)
	}

	served := withInstall(svcHost(), "kOLDCNTRL", "", offered, nil)
	at := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	served.Status.Boot = &infrav1.RackLinuxHostBootStatus{KeyID: "kOLDCNTRL", ServedTo: svcMAC, ServedAt: &at}
	h = newInstallHarness(t, served, publishedBoot("kOLDCNTRL"))
	if host := h.reconcile(t, svcUUID); len(h.api.minted) != 0 || host.Status.Install.KeyID != "kOLDCNTRL" {
		t.Fatalf("minted %v, install %+v; a key a host fetched is kept", h.api.minted, host.Status.Install)
	}
	h.now = offered.Add(rackInstallKeyLifetime + time.Minute)
	if host := h.reconcile(t, svcUUID); len(h.api.minted) != 1 || host.Status.Install.KeyID != "kMINT1CNTRL" {
		t.Fatalf("minted %v, install %+v; an expired key is renewed", h.api.minted, host.Status.Install)
	}
}

// The operator trusts the new install by the host key it gave it, rather than
// by whatever answers first on the new device.
func TestRackInstallTrustsTheNewInstallByTheHostKeyItGaveIt(t *testing.T) {
	host := withInstall(svcHost(), "kMINT1CNTRL", "", installEpoch.Add(-30*time.Minute), nil)
	host.Status.Install.HostKeyFingerprint = "SHA256:operatorgenerated"
	h := newInstallHarness(t, host, publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("new", "2026-09-24T07:50:00Z", true)}

	got := h.reconcile(t, svcUUID)
	if got.Status.Install != nil {
		t.Fatalf("install %+v, want it withdrawn", got.Status.Install)
	}
	pin, err := h.r.CredentialsManager.GetMachineBootstrap(context.Background(), rackLinuxPinKey(svcUUID, "new"))
	if err != nil {
		t.Fatal(err)
	}
	if pin == nil || pin.HostFingerprint != "SHA256:operatorgenerated" {
		t.Fatalf("pin %+v, want the install's host key", pin)
	}
	if len(h.api.revoked) != 1 || h.api.revoked[0] != "kMINT1CNTRL" {
		t.Fatalf("revoked %v, want the withdrawn install's key", h.api.revoked)
	}
	if _, ok := h.boot(t)[svcMACPath+".install"]; ok {
		t.Fatal("the withdrawn install's key ID is still published")
	}
}
