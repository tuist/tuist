package linux

import (
	"context"
	"testing"

	"github.com/go-logr/logr"
	ovhapi "github.com/ovh/go-ovh/ovh"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

const (
	prepPrefix = "tuist-kura-ovh-production-us-east"
	prepFleet  = "tuist-tuist-ovh-fleet-us-east"
	prepKey    = "ssh-ed25519 AAAAfleet"
)

// fakePrepOVH is an OVH account: boxes with a display name and a task list.
// A rename while a task is pending is dropped, as OVH does.
type fakePrepOVH struct {
	servers  map[string]*ovh.Server
	names    map[string]string
	tasks    map[string][]ovh.Task
	nextTask int64
	installs []ovh.InstallParams
	// installErr fails the next StartInstall.
	installErr error
}

func (f *fakePrepOVH) ListServers(context.Context) ([]string, error) {
	var out []string
	for n := range f.servers {
		out = append(out, n)
	}
	return out, nil
}

func (f *fakePrepOVH) GetServer(_ context.Context, n string) (*ovh.Server, error) {
	return f.servers[n], nil
}

func (f *fakePrepOVH) ServerDisplayName(_ context.Context, n string) (string, error) {
	return f.names[n], nil
}

func (f *fakePrepOVH) SetServerDisplayName(_ context.Context, n, dn string) error {
	if !pendingOVHTask(f.tasks[n]) {
		f.names[n] = dn
	}
	return nil
}

func (f *fakePrepOVH) Tasks(_ context.Context, n string) ([]ovh.Task, error) {
	return f.tasks[n], nil
}

func (f *fakePrepOVH) ResolveTemplate(context.Context, string, string) (string, error) {
	return "ubuntu2404-server_64", nil
}

func (f *fakePrepOVH) StartInstall(_ context.Context, n string, p ovh.InstallParams) error {
	if err := f.installErr; err != nil {
		f.installErr = nil
		return err
	}
	f.nextTask++
	f.tasks[n] = append(f.tasks[n], ovh.Task{ID: f.nextTask, Function: "reinstallServer", Status: "todo"})
	f.installs = append(f.installs, p)
	return nil
}

func (f *fakePrepOVH) setTaskStatus(n string, id int64, status string) {
	for i := range f.tasks[n] {
		if f.tasks[n][i].ID == id {
			f.tasks[n][i].Status = status
		}
	}
}

// newPrepFixture is one us-east box, delivered by OVH with its own install
// (task 500, done), named prep-<prefix>.
func newPrepFixture(t *testing.T, objs ...client.Object) (*OVHPoolPrep, *fakePrepOVH) {
	t.Helper()
	template := &infrav1.OVHDedicatedMachineTemplate{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: prepFleet}}
	template.Spec.Template.Spec = infrav1.OVHDedicatedMachineSpec{
		FleetName: prepFleet, AdoptDisplayNamePrefix: prepPrefix, Datacenter: "vin", Offer: "advance", OS: "ubuntu_24.04",
	}
	k8s := fake.NewClientBuilder().WithScheme(claimScheme(t)).WithObjects(append(objs, template)...).Build()
	api := &fakePrepOVH{
		servers:  map[string]*ovh.Server{"new.us": {Name: "new.us", Datacenter: "vin1", CommercialRange: "Advance-1-2024"}},
		names:    map[string]string{"new.us": "prep-" + prepPrefix},
		tasks:    map[string][]ovh.Task{"new.us": {{ID: 500, Function: "reinstallServer", Status: "done"}}},
		nextTask: 900,
	}
	return &OVHPoolPrep{
		Client: k8s, APIReader: k8s, OVH: api,
		FleetKey: func(_ context.Context, fleet string) (string, error) {
			if fleet != prepFleet {
				t.Fatalf("FleetKey(%q), want the template's fleet", fleet)
			}
			return prepKey, nil
		},
		Log: logr.Discard(),
	}, api
}

func runPrep(t *testing.T, p *OVHPoolPrep) {
	t.Helper()
	if err := p.prepOnce(context.Background()); err != nil {
		t.Fatalf("prepOnce: %v", err)
	}
}

// The box reaches the pool only after the controller's own install finishes.
// OVH's delivery install (task 500, already done) must not count: naming the
// box into the pool on it would hand the fleet a box without its key.
func TestOVHPoolPrepInstallsWithTheFleetKeyThenNamesTheBoxIntoThePool(t *testing.T) {
	p, api := newPrepFixture(t)

	runPrep(t, p)
	if got := api.names["new.us"]; got != "prepping-500-"+prepPrefix {
		t.Fatalf("after the first pass the box is %q, want it claimed as prepping-500-%s", got, prepPrefix)
	}
	if len(api.installs) != 1 || api.installs[0].SSHKey != prepKey || api.installs[0].Hostname != prepFleet {
		t.Fatalf("installs = %+v, want one with the fleet key and the fleet as hostname", api.installs)
	}

	api.setTaskStatus("new.us", 901, "doing")
	runPrep(t, p)
	if got := api.names["new.us"]; got != "prepping-500-"+prepPrefix || len(api.installs) != 1 {
		t.Fatalf("mid-install the box is %q with %d installs; it must wait", got, len(api.installs))
	}

	api.setTaskStatus("new.us", 901, "done")
	runPrep(t, p)
	if got := api.names["new.us"]; got != prepPrefix {
		t.Fatalf("after the install the box is %q, want %q", got, prepPrefix)
	}
	if len(api.installs) != 1 {
		t.Fatalf("installs = %d, want exactly one", len(api.installs))
	}
}

// A controller that stopped between the claim and the install request finds a
// prepping box whose newest install is OVH's. It installs, never names it in.
func TestOVHPoolPrepInstallsAClaimedBoxThatNeverStartedItsInstall(t *testing.T) {
	p, api := newPrepFixture(t)
	api.names["new.us"] = "prepping-500-" + prepPrefix

	runPrep(t, p)
	if got := api.names["new.us"]; got != "prepping-500-"+prepPrefix {
		t.Fatalf("box is %q; it was named into the pool on OVH's delivery install", got)
	}
	if len(api.installs) != 1 {
		t.Fatalf("installs = %d, want the missing install started", len(api.installs))
	}
}

// A failed install request leaves the box claimed, and the next pass retries it.
func TestOVHPoolPrepRetriesAFailedInstallRequest(t *testing.T) {
	p, api := newPrepFixture(t)
	api.installErr = &ovhapi.APIError{Code: 500, Message: "boom"}

	runPrep(t, p)
	if got := api.names["new.us"]; got != "prepping-500-"+prepPrefix || len(api.installs) != 0 {
		t.Fatalf("box %q with %d installs, want it claimed with none", got, len(api.installs))
	}
	runPrep(t, p)
	if len(api.installs) != 1 {
		t.Fatalf("installs = %d, want the retry", len(api.installs))
	}
}

func TestOVHPoolPrepMarksAFailedInstallAndStops(t *testing.T) {
	p, api := newPrepFixture(t)
	runPrep(t, p)
	api.setTaskStatus("new.us", 901, "ovhError")

	runPrep(t, p)
	runPrep(t, p)
	if got := api.names["new.us"]; got != "prep-failed-"+prepPrefix {
		t.Fatalf("box is %q, want prep-failed-%s", got, prepPrefix)
	}
	if len(api.installs) != 1 {
		t.Fatalf("installs = %d; a failed install must not be retried on its own", len(api.installs))
	}
}

// The controller wipes nothing it was not clearly asked to: a box still being
// delivered, a box outside the fleet's datacenter, a box a Machine holds, and a
// box asking for a prefix no fleet has.
func TestOVHPoolPrepLeavesBoxesAlone(t *testing.T) {
	cases := map[string]struct {
		setup func(*fakePrepOVH)
		objs  []client.Object
	}{
		"delivery still running": {setup: func(f *fakePrepOVH) {
			f.tasks["new.us"] = []ovh.Task{{ID: 500, Function: "reinstallServer", Status: "doing"}}
		}},
		"wrong datacenter": {setup: func(f *fakePrepOVH) { f.servers["new.us"].Datacenter = "hil1" }},
		"claimed by a Machine": {
			setup: func(*fakePrepOVH) {},
			objs:  []client.Object{claimingMachine("tuist", "live", "new.us")},
		},
		"unknown prefix": {setup: func(f *fakePrepOVH) { f.names["new.us"] = "prep-tuist-kura-ovh-staging-us-east" }},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			p, api := newPrepFixture(t, tc.objs...)
			tc.setup(api)
			before := api.names["new.us"]
			runPrep(t, p)
			if api.names["new.us"] != before || len(api.installs) != 0 {
				t.Fatalf("box renamed to %q with %d installs; want it untouched", api.names["new.us"], len(api.installs))
			}
		})
	}
}
