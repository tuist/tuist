package linux

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	corev1 "k8s.io/api/core/v1"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

const rackTestNamespace = "tuist-staging"

type fakeTailnet struct {
	devices   []tailnet.Device
	deleted   []string
	deleteErr error
	renamed   map[string]string
	minted    []string
}

func (f *fakeTailnet) Devices(context.Context) ([]tailnet.Device, error) {
	return f.devices, nil
}

func (f *fakeTailnet) DeleteDevice(_ context.Context, id string) error {
	if f.deleteErr != nil {
		return f.deleteErr
	}
	f.deleted = append(f.deleted, id)
	return nil
}

func (f *fakeTailnet) RenameDevice(_ context.Context, id, name string) error {
	if f.renamed == nil {
		f.renamed = map[string]string{}
	}
	f.renamed[id] = name
	return nil
}

func rackTestScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, infrav1.AddToScheme, clusterv1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}
	return scheme
}

func edgeHost() *infrav1.RackLinuxHost {
	return &infrav1.RackLinuxHost{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge", Namespace: rackTestNamespace},
		Spec: infrav1.RackLinuxHostSpec{
			Pool:     "ber1-staging-edge",
			Role:     "edge",
			Location: infrav1.RackHostLocation{Site: "ber1"},
			SSHUser:  "tuist",
			Tailnet:  infrav1.RackLinuxHostTailnet{Tags: []string{"tag:tuist-rack-edge"}},
		},
	}
}

func edgeDevice(id, name, created string, connected bool, ip string) tailnet.Device {
	return tailnet.Device{
		NodeID:             id,
		Name:               name + ".example.ts.net",
		Hostname:           "ber1-edge",
		Addresses:          []string{ip},
		Tags:               []string{"tag:tuist-rack-edge"},
		Created:            created,
		ConnectedToControl: connected,
	}
}

func reconcileHost(t *testing.T, api *fakeTailnet, objs ...runtime.Object) *infrav1.RackLinuxHost {
	t.Helper()
	c := fake.NewClientBuilder().WithScheme(rackTestScheme(t)).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackLinuxHost{}).Build()
	r := &RackLinuxHostReconciler{Client: c, Recorder: record.NewFakeRecorder(20), Tailnet: api}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge"}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	host := &infrav1.RackLinuxHost{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge"}, host); err != nil {
		t.Fatal(err)
	}
	return host
}

func TestRackLinuxHostAdoptsAReinstallsDevice(t *testing.T) {
	api := &fakeTailnet{devices: []tailnet.Device{
		edgeDevice("old", "ber1-edge", "2026-09-21T10:00:00Z", false, "100.124.227.31"),
		edgeDevice("new", "ber1-edge-1", "2026-09-23T18:00:00Z", true, "100.64.0.7"),
	}}
	host := reconcileHost(t, api, edgeHost())

	if len(api.deleted) != 1 || api.deleted[0] != "old" {
		t.Fatalf("deleted %v, want the replaced device", api.deleted)
	}
	if api.renamed["new"] != "ber1-edge" {
		t.Fatalf("renamed %v, want the new device named after the host", api.renamed)
	}
	tn := host.Status.Tailnet
	if tn == nil || tn.DeviceID != "new" || tn.Address != "100.64.0.7" || tn.Name != "ber1-edge.example.ts.net" || !tn.Connected {
		t.Fatalf("tailnet status %+v", tn)
	}
	if !conditions.IsTrue(host, TailnetJoinedCondition) {
		t.Fatal("TailnetJoined is not True")
	}
}

func TestRackLinuxHostKeepsAnOlderDeviceThatIsStillConnected(t *testing.T) {
	api := &fakeTailnet{devices: []tailnet.Device{
		edgeDevice("old", "ber1-edge", "2026-09-21T10:00:00Z", true, "100.124.227.31"),
		edgeDevice("new", "ber1-edge-1", "2026-09-23T18:00:00Z", true, "100.64.0.7"),
	}}
	host := reconcileHost(t, api, edgeHost())

	if len(api.deleted) != 0 || len(api.renamed) != 0 {
		t.Fatalf("deleted %v renamed %v; two connected devices are not a reinstall", api.deleted, api.renamed)
	}
	if c := conditions.Get(host, TailnetJoinedCondition); c == nil || c.Reason != "DuplicateDevices" {
		t.Fatalf("condition %+v, want DuplicateDevices", c)
	}
}

func TestRackLinuxHostKeepsTheOldDeviceUntilTheNewOneConnects(t *testing.T) {
	api := &fakeTailnet{devices: []tailnet.Device{
		edgeDevice("old", "ber1-edge", "2026-09-21T10:00:00Z", false, "100.124.227.31"),
		edgeDevice("new", "ber1-edge-1", "2026-09-23T18:00:00Z", false, "100.64.0.7"),
	}}
	reconcileHost(t, api, edgeHost())
	if len(api.deleted) != 0 {
		t.Fatalf("deleted %v while the new device was not connected", api.deleted)
	}
}

func TestRackLinuxHostIgnoresDevicesWithoutItsTags(t *testing.T) {
	impostor := edgeDevice("impostor", "ber1-edge-1", "2026-09-23T18:00:00Z", true, "100.64.0.9")
	impostor.Tags = []string{"tag:tuist-macmini-staging"}
	api := &fakeTailnet{devices: []tailnet.Device{
		edgeDevice("real", "ber1-edge", "2026-09-21T10:00:00Z", true, "100.124.227.31"),
		impostor,
	}}
	host := reconcileHost(t, api, edgeHost())
	if host.Status.Tailnet == nil || host.Status.Tailnet.DeviceID != "real" {
		t.Fatalf("tailnet status %+v", host.Status.Tailnet)
	}
	if len(api.deleted) != 0 {
		t.Fatalf("deleted %v", api.deleted)
	}
}

func TestRackLinuxHostNotOnTailnet(t *testing.T) {
	host := reconcileHost(t, &fakeTailnet{}, edgeHost())
	if c := conditions.Get(host, TailnetJoinedCondition); c == nil || c.Reason != "NotOnTailnet" {
		t.Fatalf("condition %+v", c)
	}
}

func TestRackLinuxHostReleasesAClaimWhoseMachineIsGone(t *testing.T) {
	h := edgeHost()
	h.Status.ClaimedBy = "gone"
	host := reconcileHost(t, &fakeTailnet{}, h)
	if host.Status.ClaimedBy != "" {
		t.Fatalf("claim %q not released", host.Status.ClaimedBy)
	}
}

func TestRackLinuxHostPrefersTheConnectedDevice(t *testing.T) {
	api := &fakeTailnet{devices: []tailnet.Device{
		edgeDevice("live", "ber1-edge", "2026-09-21T10:00:00Z", true, "100.124.227.31"),
		edgeDevice("aborted", "ber1-edge-1", "2026-09-23T18:00:00Z", false, "100.64.0.7"),
	}}
	host := reconcileHost(t, api, edgeHost())
	if host.Status.Tailnet == nil || host.Status.Tailnet.DeviceID != "live" {
		t.Fatalf("tailnet status %+v, want the connected device", host.Status.Tailnet)
	}
	if len(api.deleted) != 1 || api.deleted[0] != "aborted" || len(api.renamed) != 0 {
		t.Fatalf("deleted %v renamed %v", api.deleted, api.renamed)
	}
}
