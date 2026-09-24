package linux

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
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

func (f *fakeTailnet) CreateAuthKey(_ context.Context, tags []string, expiry time.Duration, _ string) (tailnet.AuthKey, error) {
	f.minted = append(f.minted, strings.Join(tags, ","))
	id := fmt.Sprintf("kMINT%dCNTRL", len(f.minted))
	return tailnet.AuthKey{ID: id, Key: "tskey-auth-" + id + "-secret", Expires: installEpoch.Add(expiry).Format(time.RFC3339)}, nil
}

func svcHost() *infrav1.RackLinuxHost {
	return &infrav1.RackLinuxHost{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-svc", Namespace: rackTestNamespace},
		Spec: infrav1.RackLinuxHostSpec{
			Pool:     "ber1-staging-services",
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

func withInstall(host *infrav1.RackLinuxHost, keyID, previous string, offered time.Time, triggered *time.Time) *infrav1.RackLinuxHost {
	host.Status.Install = &infrav1.RackLinuxHostInstallStatus{
		KeyID:            keyID,
		BootMAC:          host.Spec.BootMAC,
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

func publishedBoot(keyID string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-boot", Namespace: rackTestNamespace},
		Data: map[string][]byte{
			svcMACPath + ".user-data":     []byte("#cloud-config " + keyID),
			svcMACPath + ".meta-data":     []byte("instance-id: x"),
			svcMACPath + ".ipxe":          []byte("#!ipxe"),
			"aa-bb-cc-dd-ee-ff.ipxe":      []byte("another host"),
			"aa-bb-cc-dd-ee-ff.user-data": []byte("another host"),
			"aa-bb-cc-dd-ee-ff.meta-data": []byte("another host"),
		},
	}
}

func TestRackInstallPublishesAnInstallForAHostNotOnTheTailnet(t *testing.T) {
	h := newInstallHarness(t, svcHost())
	host := h.reconcile(t, "ber1-svc")

	if len(h.api.minted) != 1 || h.api.minted[0] != "tag:tuist-rack-node" {
		t.Fatalf("minted %v, want one key tagged with the host's tags", h.api.minted)
	}
	inst := host.Status.Install
	if inst == nil || inst.KeyID != "kMINT1CNTRL" || inst.BootMAC != svcMAC || inst.PreviousDeviceID != "" || inst.TriggeredAt != nil {
		t.Fatalf("install status %+v", inst)
	}
	if !inst.ExpiresAt.Time.Equal(installEpoch.Add(rackInstallKeyLifetime)) {
		t.Fatalf("expires %v", inst.ExpiresAt)
	}
	c := conditions.Get(host, InstalledCondition)
	if c == nil || c.Status != corev1.ConditionFalse || c.Reason != "WaitingForNetboot" {
		t.Fatalf("Installed condition %+v", c)
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

	console := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: rackTestFleet + "-console"}, console); err != nil {
		t.Fatal(err)
	}
	if len(console.Data["ber1-svc"]) != rackConsolePasswordChars {
		t.Fatalf("console password %q", console.Data["ber1-svc"])
	}
	if strings.Contains(userData, string(console.Data["ber1-svc"])) {
		t.Fatal("the console password is in the seed in the clear")
	}
}

func TestRackInstallKeepsAPublishedInstallUntilItNeedsRenewing(t *testing.T) {
	h := newInstallHarness(t, withInstall(svcHost(), "kOLDCNTRL", "", installEpoch.Add(-time.Hour), nil), publishedBoot("kOLDCNTRL"))
	host := h.reconcile(t, "ber1-svc")
	if len(h.api.minted) != 0 || host.Status.Install.KeyID != "kOLDCNTRL" {
		t.Fatalf("minted %v, install %+v; a fresh offer is kept", h.api.minted, host.Status.Install)
	}

	triggered := installEpoch.Add(-20 * time.Hour)
	reinstalling := svcHost()
	reinstalling.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	h = newInstallHarness(t, withInstall(reinstalling, "kOLDCNTRL", "old", installEpoch.Add(-20*time.Hour), &triggered), publishedBoot("kOLDCNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false)}
	host = h.reconcile(t, "ber1-svc")
	inst := host.Status.Install
	if len(h.api.minted) != 1 || inst.KeyID != "kMINT1CNTRL" || inst.PreviousDeviceID != "old" || inst.TriggeredAt == nil {
		t.Fatalf("minted %v, install %+v; a renewal keeps what the install replaces and that it was started", h.api.minted, inst)
	}
	if !strings.Contains(string(h.boot(t)[svcMACPath+".user-data"]), "kMINT1CNTRL") {
		t.Fatal("the renewed key is not published")
	}
}

func TestRackInstallWithdrawsTheInstallOnceTheHostJoins(t *testing.T) {
	h := newInstallHarness(t, withInstall(svcHost(), "kMINT1CNTRL", "", installEpoch.Add(-30*time.Minute), nil), publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("new", "2026-09-24T07:50:00Z", true)}
	host := h.reconcile(t, "ber1-svc")

	if host.Status.Install != nil {
		t.Fatalf("install %+v, want it withdrawn", host.Status.Install)
	}
	if !conditions.IsTrue(host, InstalledCondition) {
		t.Fatal("Installed is not True")
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

func TestRackInstallReinstallsARunningHost(t *testing.T) {
	host := svcHost()
	host.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	h := newInstallHarness(t, host)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}

	got := h.reconcile(t, "ber1-svc")
	if got.Status.Install == nil || got.Status.Install.PreviousDeviceID != "old" || got.Status.Install.TriggeredAt != nil {
		t.Fatalf("install %+v", got.Status.Install)
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the host before the boot server could serve its install")
	}

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got = h.reconcile(t, "ber1-svc")
	if len(h.runner.runs) != 1 {
		t.Fatalf("runs %d, want the netboot-once script", len(h.runner.runs))
	}
	run := h.runner.runs[0]
	if run.host != "rack-linux-ber1-svc.tailscale-operator.svc.cluster.local" || !strings.Contains(run.script, "mac=380525"+"38b5b5") {
		t.Fatalf("run %+v", run)
	}
	if got.Status.Install.TriggeredAt == nil || len(h.api.minted) != 1 {
		t.Fatalf("install %+v minted %v", got.Status.Install, h.api.minted)
	}

	h.now = h.now.Add(time.Minute)
	got = h.reconcile(t, "ber1-svc")
	if len(h.runner.runs) != 1 {
		t.Fatal("rebooted the host a second time")
	}

	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false), svcDevice("new", "2026-09-24T08:20:00Z", true)}
	got = h.reconcile(t, "ber1-svc")
	if got.Status.Install != nil || got.Annotations[RackReinstallAnnotation] != "" {
		t.Fatalf("install %+v annotations %v, want the reinstall finished", got.Status.Install, got.Annotations)
	}
	if !conditions.IsTrue(got, InstalledCondition) {
		t.Fatal("Installed is not True")
	}
}

func TestRackInstallReportsAReinstallThatDidNotNetboot(t *testing.T) {
	host := svcHost()
	host.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	triggered := installEpoch.Add(-rackReinstallBootTimeout - time.Minute)
	h := newInstallHarness(t, withInstall(host, "kMINT1CNTRL", "old", triggered.Add(-time.Minute), &triggered), publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	got := h.reconcile(t, "ber1-svc")
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "ReinstallDidNotBoot" {
		t.Fatalf("Installed %+v", c)
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the host again")
	}
}

func TestRackInstallWithdrawsWhenTheReinstallIsCancelled(t *testing.T) {
	h := newInstallHarness(t, withInstall(svcHost(), "kMINT1CNTRL", "old", installEpoch.Add(-time.Minute), nil), publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	got := h.reconcile(t, "ber1-svc")
	if got.Status.Install != nil || h.boot(t)[svcMACPath+".user-data"] != nil || len(h.runner.runs) != 0 {
		t.Fatalf("install %+v runs %d, want it withdrawn untouched", got.Status.Install, len(h.runner.runs))
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
	host.Spec.Role = role
	host.Spec.Location.Site = site
	host.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: name + "-device", Name: name + ".example.ts.net", Address: "100.64.0.20", Connected: connected}
	return host
}

func TestRackInstallPublishesForAnEdgeAnotherEdgeOfItsSiteServes(t *testing.T) {
	h := newInstallHarness(t, installableEdge(), otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true))
	got := h.reconcile(t, "ber1-edge")

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
	} {
		t.Run(name, func(t *testing.T) {
			h := newInstallHarness(t, append([]runtime.Object{installableEdge()}, others...)...)
			got := h.reconcile(t, "ber1-edge")
			if len(h.api.minted) != 0 || got.Status.Install != nil || h.boot(t) != nil {
				t.Fatalf("minted %v install %+v", h.api.minted, got.Status.Install)
			}
			c := conditions.Get(got, InstalledCondition)
			if c == nil || c.Reason != "ServesTheNetboot" || !strings.Contains(c.Message, "no other edge of site ber1") || !strings.Contains(c.Message, "rack:write-install-usb") {
				t.Fatalf("Installed %+v", c)
			}
		})
	}
}

func TestRackInstallWithdrawsAnEdgeInstallWhoseServingEdgeWentAway(t *testing.T) {
	host := installableEdge()
	host.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	h := newInstallHarness(t, host, otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{edgeDevice("old", "ber1-edge", "2026-09-01T00:00:00Z", true, "100.64.0.7")}

	got := h.reconcile(t, "ber1-edge")
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

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got = h.reconcile(t, "ber1-edge")
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
	host := installableEdge()
	host.Annotations = map[string]string{RackReinstallAnnotation: "true"}
	h := newInstallHarness(t, host, otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true))
	h.api.devices = []tailnet.Device{edgeDevice("old", "ber1-edge", "2026-09-01T00:00:00Z", true, "100.64.0.7")}

	h.reconcile(t, "ber1-edge")
	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got := h.reconcile(t, "ber1-edge")
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
	got = h.reconcile(t, "ber1-edge")
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

func TestRackInstallLeavesAHostWithoutABootMACAlone(t *testing.T) {
	host := svcHost()
	host.Spec.BootMAC = ""
	h := newInstallHarness(t, host)
	got := h.reconcile(t, "ber1-svc")
	if len(h.api.minted) != 0 || got.Status.Install != nil || conditions.Get(got, InstalledCondition) != nil {
		t.Fatalf("minted %v install %+v", h.api.minted, got.Status.Install)
	}
}

func TestRackInstallKeepsTheConsolePasswordAcrossInstalls(t *testing.T) {
	h := newInstallHarness(t, svcHost(), &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-console", Namespace: rackTestNamespace},
		Data:       map[string][]byte{"ber1-svc": []byte("kept-password")},
	})
	h.reconcile(t, "ber1-svc")
	console := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: rackTestFleet + "-console"}, console); err != nil {
		t.Fatal(err)
	}
	if string(console.Data["ber1-svc"]) != "kept-password" {
		t.Fatalf("console password replaced with %q", console.Data["ber1-svc"])
	}
}

func poolDeployment(name, pool string, replicas int32) *clusterv1.MachineDeployment {
	return &clusterv1.MachineDeployment{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: rackTestNamespace, Labels: map[string]string{RackPoolLabel: pool}},
		Spec:       clusterv1.MachineDeploymentSpec{ClusterName: "tuist-capi", Replicas: ptr.To(replicas)},
	}
}

func TestRackPoolScalesUpAsHostsJoin(t *testing.T) {
	other := edgeHost()
	h := newInstallHarness(t, svcHost(), other,
		poolDeployment("svc", "ber1-staging-services", 0),
		poolDeployment("edge", "ber1-staging-edge", 1))
	h.api.devices = []tailnet.Device{svcDevice("new", "2026-09-24T07:50:00Z", true)}
	h.reconcile(t, "ber1-svc")

	for name, want := range map[string]int32{"svc": 1, "edge": 1} {
		md := &clusterv1.MachineDeployment{}
		if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, md); err != nil {
			t.Fatal(err)
		}
		if *md.Spec.Replicas != want {
			t.Errorf("%s replicas %d, want %d", name, *md.Spec.Replicas, want)
		}
	}
}

func TestRackPoolNeverScalesDown(t *testing.T) {
	h := newInstallHarness(t, svcHost(), poolDeployment("svc", "ber1-staging-services", 3))
	h.api.devices = []tailnet.Device{svcDevice("new", "2026-09-24T07:50:00Z", true)}
	h.reconcile(t, "ber1-svc")
	md := &clusterv1.MachineDeployment{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "svc"}, md); err != nil {
		t.Fatal(err)
	}
	if *md.Spec.Replicas != 3 {
		t.Fatalf("replicas %d", *md.Spec.Replicas)
	}
}

func TestNetbootOnceScriptSetsBootNextToTheBootNIC(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	bin := t.TempDir()
	calls := filepath.Join(bin, "calls")
	fakes := map[string]string{
		"efibootmgr": `if [ "${1:-}" = -v ]; then cat <<'OUT'
BootCurrent: 0004
BootOrder: 0004,0001,0002,0003
Boot0001* UEFI PXEv4 (MAC:5847CA7A1B2C)	PciRoot(0x0)/Pci(0x1c,0x0)/Pci(0x0,0x0)/MAC(5847ca7a1b2c,0)/IPv4(0.0.0.0,0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
Boot0002* UEFI HTTPv4 (MAC:38052538B5B5)	PciRoot(0x0)/Pci(0x1c,0x4)/Pci(0x0,0x0)/MAC(38052538b5b5,0)/IPv4(0.0.0.0,0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)/Uri()
Boot0003* UEFI PXEv4 (MAC:38052538B5B5)	PciRoot(0x0)/Pci(0x1c,0x4)/Pci(0x0,0x0)/MAC(38052538b5b5,0)/IPv4(0.0.0.0,0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
Boot0004* Ubuntu	HD(1,GPT,5c1d6e2a-0000-0000-0000-000000000000,0x800,0x219800)/File(\EFI\ubuntu\shimx64.efi)
OUT
else echo "efibootmgr $*" >>"` + calls + `"; fi`,
		"systemctl": `echo "systemctl $*" >>"` + calls + `"`,
		"sleep":     `:`,
	}
	for name, body := range fakes {
		if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	run := func(mac string) (string, error) {
		cmd := exec.Command(bash, "-s")
		cmd.Stdin = strings.NewReader(renderNetbootOnceScript(mac))
		cmd.Env = append(os.Environ(), "PATH="+bin+":"+os.Getenv("PATH"))
		out, err := cmd.CombinedOutput()
		return string(out), err
	}

	out, err := run(svcMAC)
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		recorded, _ := os.ReadFile(calls)
		if strings.Contains(string(recorded), "systemctl reboot") {
			if !strings.Contains(string(recorded), "efibootmgr -q -n 0003") {
				t.Fatalf("calls %q, want BootNext set to the PXEv4 entry of the boot NIC", recorded)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("no reboot; calls %q output %q", recorded, out)
		}
		time.Sleep(50 * time.Millisecond)
	}

	if out, err := run("aa:bb:cc:dd:ee:ff"); err == nil || !strings.Contains(out, "no IPv4 network boot entry for aa:bb:cc:dd:ee:ff") {
		t.Fatalf("a MAC without an entry: err %v output %q", err, out)
	}
}

func TestRackInstallPublishesAgainWhenTheBootSecretLostIt(t *testing.T) {
	stale := publishedBoot("kOLDCNTRL")
	delete(stale.Data, svcMACPath+".ipxe")
	stale.Data[svcMACPath+".grub.cfg"] = []byte("set timeout=0")
	h := newInstallHarness(t, withInstall(svcHost(), "kOLDCNTRL", "", installEpoch.Add(-time.Hour), nil), stale)
	host := h.reconcile(t, "ber1-svc")
	if len(h.api.minted) != 1 || host.Status.Install.KeyID != "kMINT1CNTRL" {
		t.Fatalf("minted %v, install %+v; an install the boot server no longer has is published again", h.api.minted, host.Status.Install)
	}
	if !strings.Contains(string(h.boot(t)[svcMACPath+".ipxe"]), "BOOTIF=01-"+svcMACPath) {
		t.Fatal("the host's iPXE script is not published")
	}
}

// renamedBox is a box running as ber1-svc and declared again as ber1-svc-b.
func renamedBox(connected bool) (running, renamed *infrav1.RackLinuxHost) {
	running = svcHost()
	running.CreationTimestamp = metav1.NewTime(time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC))
	running.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: "old", Name: "ber1-svc.example.ts.net", Address: "100.64.0.9", Connected: connected}
	renamed = svcHost()
	renamed.Name = "ber1-svc-b"
	renamed.CreationTimestamp = metav1.NewTime(installEpoch.Add(-time.Hour))
	return running, renamed
}

func renamedDevice(id, created string, connected bool) tailnet.Device {
	d := svcDevice(id, created, connected)
	d.Name, d.Hostname, d.Addresses = "ber1-svc-b.example.ts.net", "ber1-svc-b", []string{"100.64.0.10"}
	return d
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

func TestRackInstallTakesOverTheBoxOfARenamedHost(t *testing.T) {
	running, renamed := renamedBox(true)
	h := newInstallHarness(t, running, renamed)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}

	got := h.reconcile(t, "ber1-svc-b")
	if got.Status.Install == nil || len(h.api.minted) != 1 || got.Status.Install.TriggeredAt != nil {
		t.Fatalf("install %+v minted %v, want one published for the new name", got.Status.Install, h.api.minted)
	}
	if !strings.Contains(string(h.boot(t)[svcMACPath+".user-data"]), "hostname: ber1-svc-b") {
		t.Fatal("the published seed is not the new name's")
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the box before the boot server could serve its install")
	}

	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got = h.reconcile(t, "ber1-svc-b")
	if len(h.runner.runs) != 1 {
		t.Fatalf("runs %d, want the box rebooted into the new name's install", len(h.runner.runs))
	}
	if run := h.runner.runs[0]; run.host != "rack-linux-ber1-svc.tailscale-operator.svc.cluster.local" || !strings.Contains(run.script, "mac=38052538b5b5") {
		t.Fatalf("run %+v, want the netboot-once script through the running system", run)
	}
	if got.Status.Install.TriggeredAt == nil {
		t.Fatal("the takeover is not recorded")
	}

	h.now = h.now.Add(time.Minute)
	h.reconcile(t, "ber1-svc-b")
	if len(h.runner.runs) != 1 {
		t.Fatal("rebooted the box a second time")
	}

	old := h.reconcile(t, "ber1-svc")
	if old.Status.Install != nil || len(h.api.minted) != 1 {
		t.Fatalf("install %+v minted %v; the old name publishes nothing for the box", old.Status.Install, h.api.minted)
	}
	if c := conditions.Get(old, InstalledCondition); c == nil || c.Reason != "Replaced" {
		t.Fatalf("Installed %+v", c)
	}

	h.api.devices = nil
	old = h.reconcile(t, "ber1-svc")
	if old.Status.Tailnet != nil || old.Status.Install != nil || len(h.api.minted) != 1 {
		t.Fatalf("tailnet %+v install %+v minted %v; the old name never publishes for the box once its device is gone", old.Status.Tailnet, old.Status.Install, h.api.minted)
	}
	if !strings.Contains(string(h.boot(t)[svcMACPath+".user-data"]), "hostname: ber1-svc-b") {
		t.Fatal("the new name's install is no longer served")
	}

	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false), renamedDevice("new", "2026-09-24T08:20:00Z", true)}
	h.reconcile(t, "ber1-svc")
	drainEvents(h)
	got = h.reconcile(t, "ber1-svc-b")
	if got.Status.Install != nil || !conditions.IsTrue(got, InstalledCondition) {
		t.Fatalf("install %+v, want it withdrawn once the new name joined", got.Status.Install)
	}
	old = &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-svc"}, old); err != nil || old.DeletionTimestamp.IsZero() {
		t.Fatalf("the old name is not being deleted: %v", err)
	}
	named := false
	for _, e := range drainEvents(h) {
		named = named || (strings.Contains(e, "Deleted RackLinuxHost ber1-svc:") && strings.Contains(e, "ber1-svc-b"))
	}
	if !named {
		t.Error("no event names both hosts")
	}

	if gone, _ := h.reconcileOrGone(t, "ber1-svc"); gone != nil {
		t.Fatalf("the old name is still there with finalizers %v", gone.Finalizers)
	}
	if strings.Join(h.api.deleted, ",") != "old" {
		t.Fatalf("deleted %v, want the old name's device", h.api.deleted)
	}
}

func TestRackInstallWaitsForTheRenamedBoxToComeOnline(t *testing.T) {
	running, renamed := renamedBox(false)
	h := newInstallHarness(t, running, renamed)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", false)}
	h.reconcile(t, "ber1-svc-b")
	h.now = installEpoch.Add(rackBootPropagation + time.Second)
	got := h.reconcile(t, "ber1-svc-b")
	if len(h.runner.runs) != 0 || got.Status.Install == nil || got.Status.Install.TriggeredAt != nil {
		t.Fatalf("runs %d install %+v; an offline box cannot be rebooted", len(h.runner.runs), got.Status.Install)
	}
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "WaitingForNetboot" {
		t.Fatalf("Installed %+v", c)
	}
	if old := h.reconcile(t, "ber1-svc"); old.DeletionTimestamp != nil {
		t.Fatal("the running name was deleted before the new one joined")
	}
}

func TestRackInstallReportsATakeoverThatDidNotNetboot(t *testing.T) {
	running, renamed := renamedBox(true)
	triggered := installEpoch.Add(-rackReinstallBootTimeout - time.Minute)
	withInstall(renamed, "kMINT1CNTRL", "", triggered.Add(-time.Minute), &triggered)
	h := newInstallHarness(t, running, renamed, publishedBoot("kMINT1CNTRL"))
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	got := h.reconcile(t, "ber1-svc-b")
	if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "ReinstallDidNotBoot" || !strings.Contains(c.Message, "ber1-svc") {
		t.Fatalf("Installed %+v", c)
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("rebooted the box again")
	}
}

func TestRackInstallKeepsARunningHostWhoseTwinHasNotJoined(t *testing.T) {
	running, renamed := renamedBox(true)
	renamed.Spec.Role = "storage"
	h := newInstallHarness(t, running, renamed)
	h.api.devices = []tailnet.Device{svcDevice("old", "2026-09-01T00:00:00Z", true)}
	h.reconcile(t, "ber1-svc-b")
	old := h.reconcile(t, "ber1-svc")
	if !conditions.IsTrue(old, InstalledCondition) || old.DeletionTimestamp != nil {
		t.Fatalf("Installed %+v; a twin with nothing published does not replace the running host", conditions.Get(old, InstalledCondition))
	}
	renamedNow := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-svc-b"}, renamedNow); err != nil || renamedNow.DeletionTimestamp != nil {
		t.Fatalf("the newer name was deleted: %v", err)
	}
}

func TestRackInstallDoesNotCountTheSameBoxOrADeletingEdgeAsServing(t *testing.T) {
	for name, other := range map[string]func() *infrav1.RackLinuxHost{
		"the connected edge is the same box": func() *infrav1.RackLinuxHost {
			o := otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true)
			o.Spec.BootMAC = svcMAC
			o.CreationTimestamp = metav1.NewTime(installEpoch.Add(-48 * time.Hour))
			return o
		},
		"the connected edge is being deleted": func() *infrav1.RackLinuxHost {
			o := otherEdge("ber1-edge-b", rackTestNamespace, "ber1", "edge", true)
			o.Finalizers = []string{RackLinuxHostFinalizer}
			now := metav1.NewTime(installEpoch)
			o.DeletionTimestamp = &now
			return o
		},
	} {
		t.Run(name, func(t *testing.T) {
			edge := installableEdge()
			edge.CreationTimestamp = metav1.NewTime(installEpoch.Add(-time.Hour))
			h := newInstallHarness(t, edge, other())
			got := h.reconcile(t, "ber1-edge")
			if len(h.api.minted) != 0 || got.Status.Install != nil {
				t.Fatalf("minted %v install %+v", h.api.minted, got.Status.Install)
			}
			if c := conditions.Get(got, InstalledCondition); c == nil || c.Reason != "ServesTheNetboot" {
				t.Fatalf("Installed %+v", c)
			}
		})
	}
}
