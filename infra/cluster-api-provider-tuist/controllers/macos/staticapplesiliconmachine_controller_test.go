package macos

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/utils/ptr"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	testNamespace = "ns"
	testPool      = "ber1-staging"
	testFleet     = "tuist-tuist-ber1-fleet"
)

// --- fixtures ---------------------------------------------------------------

func rackHost(name string, mutate ...func(*infrav1.RackHost)) *infrav1.RackHost {
	h := &infrav1.RackHost{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace},
		Spec: infrav1.RackHostSpec{
			Pool:     testPool,
			Serial:   "C07FC05JQ6NY",
			Address:  "192.168.0.41",
			SSHUser:  "tuist",
			Location: infrav1.RackHostLocation{Site: "ber1", Rack: "r1", Shelf: "s3", PositionU: 12},
			Power: &infrav1.PowerOutletRef{
				Driver: power.DriverShelly,
				Host:   "192.168.0.50",
				Outlet: "0",
			},
		},
	}
	for _, m := range mutate {
		m(h)
	}
	return h
}

func staticMachine(name string, mutate ...func(*infrav1.StaticAppleSiliconMachine)) *infrav1.StaticAppleSiliconMachine {
	m := &infrav1.StaticAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace},
		Spec: infrav1.StaticAppleSiliconMachineSpec{
			AdoptPool: testPool,
			FleetName: testFleet,
		},
	}
	for _, mut := range mutate {
		mut(m)
	}
	return m
}

// fleetSecret is what ESO syncs from the BER1_FLEET_SSH 1Password item.
func fleetSecret(mutate ...func(*corev1.Secret)) *corev1.Secret {
	s := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: testFleet + "-ssh", Namespace: testNamespace},
		Data: map[string][]byte{
			"id_ed25519":    []byte("PRIVATE KEY"),
			"sudo-password": []byte("hunter2"),
		},
	}
	for _, m := range mutate {
		m(s)
	}
	return s
}

func newStaticReconciler(t *testing.T, objs ...runtime.Object) *StaticAppleSiliconMachineReconciler {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{
		corev1.AddToScheme, infrav1.AddToScheme, clusterv1.AddToScheme, rbacv1.AddToScheme,
	} {
		if err := add(scheme); err != nil {
			t.Fatalf("scheme: %v", err)
		}
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.StaticAppleSiliconMachine{}, &infrav1.RackHost{}).
		Build()
	return &StaticAppleSiliconMachineReconciler{
		Client:                  c,
		Recorder:                fakeRecorder(),
		CredentialsManager:      &credentials.Manager{Client: c, Namespace: testNamespace},
		SecretsNamespace:        testNamespace,
		BootstrapRebootAfter:    3,
		BootstrapMaxAttempts:    8,
		MaxConcurrentReconciles: 1,
		PowerCycleSettle:        time.Millisecond,
	}
}

func getHost(t *testing.T, r *StaticAppleSiliconMachineReconciler, name string) *infrav1.RackHost {
	t.Helper()
	h := &infrav1.RackHost{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: name}, h); err != nil {
		t.Fatalf("get rack host %s: %v", name, err)
	}
	return h
}

// --- claim ------------------------------------------------------------------

func TestClaimBindsAFreeHostAndComposesTheProviderID(t *testing.T) {
	machine := staticMachine("ber1-0")
	r := newStaticReconciler(t, rackHost("mini-01"), machine)

	host, result, err := r.claimRackHost(context.Background(), machine)
	if err != nil {
		t.Fatalf("claimRackHost: %v", err)
	}
	if host == nil {
		t.Fatalf("no host claimed; result = %+v", result)
	}

	if machine.Status.RackHost != "mini-01" {
		t.Fatalf("machine.Status.RackHost = %q, want mini-01", machine.Status.RackHost)
	}
	if claimed := getHost(t, r, "mini-01"); claimed.Status.ClaimedBy != "ber1-0" {
		t.Fatalf("host.Status.ClaimedBy = %q, want ber1-0", claimed.Status.ClaimedBy)
	}
	// The providerID is composed from the two DURABLE physical facts, not the
	// address: re-cabling a box onto a new IP must not change its identity to
	// CAPI, or the Node binding breaks on a network change.
	if want := "static-applesilicon://ber1/C07FC05JQ6NY"; ptr.Deref(machine.Spec.ProviderID, "") != want {
		t.Fatalf("providerID = %q, want %q", ptr.Deref(machine.Spec.ProviderID, ""), want)
	}
	if !conditions.IsTrue(machine, shared.ProvisionedCondition) {
		t.Fatal("Provisioned condition not set after a successful claim")
	}
}

// The address is per-host state and must never end up in the Machine's spec:
// the spec is what a MachineTemplate clones, so an address there would be
// copied onto every replica.
func TestClaimKeepsTheAddressOutOfTheSpec(t *testing.T) {
	machine := staticMachine("ber1-0")
	r := newStaticReconciler(t, rackHost("mini-01"), machine)

	if _, _, err := r.claimRackHost(context.Background(), machine); err != nil {
		t.Fatalf("claimRackHost: %v", err)
	}
	if len(machine.Status.Addresses) != 1 || machine.Status.Addresses[0].Address != "192.168.0.41" {
		t.Fatalf("addresses = %+v, want the host address in status", machine.Status.Addresses)
	}
}

func TestClaimIsIdempotentForTheHostAlreadyHeld(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	r := newStaticReconciler(t, host, machine)

	got, _, err := r.claimRackHost(context.Background(), machine)
	if err != nil {
		t.Fatalf("claimRackHost: %v", err)
	}
	if got == nil || got.Name != "mini-01" {
		t.Fatalf("re-claim returned %v, want the held host", got)
	}
}

// A claim we no longer hold, because the inventory record was deleted or
// someone released it out of band, must be dropped rather than bootstrapped. Pushing
// config to a host another Machine now holds would have two Machines fighting
// over one Node.
func TestClaimDropsAStolenOrVanishedHost(t *testing.T) {
	for _, tc := range []struct {
		name  string
		objs  []runtime.Object
		wants string
	}{
		{
			name:  "host deleted from inventory",
			objs:  []runtime.Object{rackHost("mini-02")},
			wants: "mini-02",
		},
		{
			name: "claim taken by another machine",
			objs: []runtime.Object{
				rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "someone-else" }),
				rackHost("mini-02"),
			},
			wants: "mini-02",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
				m.Status.RackHost = "mini-01"
				m.Status.Ready = true
			})
			r := newStaticReconciler(t, append(tc.objs, machine)...)

			host, _, err := r.claimRackHost(context.Background(), machine)
			if err != nil {
				t.Fatalf("claimRackHost: %v", err)
			}
			if host == nil || host.Name != tc.wants {
				t.Fatalf("claimed %v, want %s", host, tc.wants)
			}
			if machine.Status.Ready {
				t.Fatal("machine still reports Ready after losing its host")
			}
		})
	}
}

// Two machines racing for the last free host. The claim is an Update carrying
// the resourceVersion the host was read at, so the apiserver rejects whichever
// write is second. A merge patch would let both "succeed", both bootstrap the
// same box, and the second would take over the first's Node.
//
// The race has to be injected, not simulated by calling the two claims in
// order: sequential calls never collide, because the second one's List already
// shows the host claimed and the filter drops it before any write. What has to
// be exercised is a claim whose candidate list was read BEFORE a competing
// claim landed: the only window in which the concurrency check does any work.
func TestClaimRaceIsResolvedByOptimisticConcurrency(t *testing.T) {
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{
		corev1.AddToScheme, infrav1.AddToScheme, clusterv1.AddToScheme, rbacv1.AddToScheme,
	} {
		if err := add(scheme); err != nil {
			t.Fatalf("scheme: %v", err)
		}
	}

	var (
		inner    client.Client
		raceOnce sync.Once
	)
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(rackHost("mini-01"), staticMachine("ber1-0")).
		WithStatusSubresource(&infrav1.StaticAppleSiliconMachine{}, &infrav1.RackHost{}).
		WithInterceptorFuncs(interceptor.Funcs{
			List: func(ctx context.Context, cl client.WithWatch, list client.ObjectList, opts ...client.ListOption) error {
				if err := cl.List(ctx, list, opts...); err != nil {
					return err
				}
				// The instant our candidate list is in hand, a competing
				// machine claims the host. Everything the caller does from
				// here on is against a view that is already one write stale.
				if _, ok := list.(*infrav1.RackHostList); ok {
					raceOnce.Do(func() {
						stolen := &infrav1.RackHost{}
						if err := inner.Get(ctx, types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}, stolen); err != nil {
							t.Fatalf("competing read: %v", err)
						}
						stolen.Status.ClaimedBy = "ber1-9"
						if err := inner.Status().Update(ctx, stolen); err != nil {
							t.Fatalf("competing claim: %v", err)
						}
					})
				}
				return nil
			},
		}).
		Build()
	inner = c

	r := &StaticAppleSiliconMachineReconciler{
		Client:             c,
		Recorder:           fakeRecorder(),
		CredentialsManager: &credentials.Manager{Client: c, Namespace: testNamespace},
		SecretsNamespace:   testNamespace,
	}
	machine := staticMachine("ber1-0")

	host, result, err := r.claimRackHost(context.Background(), machine)
	if err != nil {
		t.Fatalf("claimRackHost: %v", err)
	}
	if host != nil {
		t.Fatalf("claimed %s on a stale read; the competing claim was silently overwritten", host.Name)
	}
	if !result.Requeue && result.RequeueAfter == 0 {
		t.Fatal("lost the race without requeueing; the machine would sit idle until the next resync")
	}
	if machine.Status.RackHost != "" {
		t.Fatalf("machine bound itself to %q despite losing the race", machine.Status.RackHost)
	}

	final := &infrav1.RackHost{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}, final); err != nil {
		t.Fatalf("get host: %v", err)
	}
	if final.Status.ClaimedBy != "ber1-9" {
		t.Fatalf("host is claimed by %q; the winner's claim was clobbered", final.Status.ClaimedBy)
	}
}

// The filter is the other half: once a competing claim IS visible, the host
// must be passed over before any write is attempted.
func TestClaimSkipsAHostAlreadyVisiblyClaimed(t *testing.T) {
	first := staticMachine("ber1-0")
	second := staticMachine("ber1-1")
	r := newStaticReconciler(t, rackHost("mini-01"), first, second)
	ctx := context.Background()

	if _, _, err := r.claimRackHost(ctx, first); err != nil {
		t.Fatalf("first claim: %v", err)
	}
	host, result, err := r.claimRackHost(ctx, second)
	if err != nil {
		t.Fatalf("second claim: %v", err)
	}
	if host != nil {
		t.Fatalf("second machine also claimed %s; the pool has one host", host.Name)
	}
	if result.RequeueAfter == 0 && !result.Requeue {
		t.Fatal("second machine neither claimed nor requeued; it would sit idle")
	}
	if claimed := getHost(t, r, "mini-01"); claimed.Status.ClaimedBy != "ber1-0" {
		t.Fatalf("host claimed by %q, want the first machine to keep it", claimed.Status.ClaimedBy)
	}
}

func TestClaimRefusesAnUnscopedScan(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) { m.Spec.AdoptPool = "" })
	r := newStaticReconciler(t, rackHost("mini-01"), machine)

	host, result, err := r.claimRackHost(context.Background(), machine)
	if err != nil {
		t.Fatalf("claimRackHost: %v", err)
	}
	if host != nil {
		t.Fatal("claimed a host with no adoptPool; an unscoped scan can take another environment's box")
	}
	if result.RequeueAfter == 0 {
		t.Fatal("expected a requeue: an operator fixes this on the template, the CR need not be recreated")
	}
	cond := conditions.Get(machine, shared.ProvisionedCondition)
	if cond == nil || cond.Reason != "NoAdoptPool" {
		t.Fatalf("condition = %+v, want NoAdoptPool", cond)
	}
	if claimed := getHost(t, r, "mini-01"); claimed.Status.ClaimedBy != "" {
		t.Fatalf("host was claimed anyway by %q", claimed.Status.ClaimedBy)
	}
}

// selectClaimableHosts decides what a machine may take, and its skip tally is
// what turns "no host" into an actionable message. Getting the filter wrong is
// how a quarantined box gets handed straight back to the machine that
// quarantined it.
func TestSelectClaimableHostsFiltersAndExplains(t *testing.T) {
	hosts := []infrav1.RackHost{
		*rackHost("free-b"),
		*rackHost("free-a"),
		*rackHost("mine", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" }),
		*rackHost("theirs", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-9" }),
		*rackHost("bad", func(h *infrav1.RackHost) { h.Status.Quarantined = true }),
		*rackHost("bench", func(h *infrav1.RackHost) { h.Spec.Unclaimable = true }),
		*rackHost("no-address", func(h *infrav1.RackHost) { h.Spec.Address = "" }),
		*rackHost("no-site", func(h *infrav1.RackHost) { h.Spec.Location.Site = "" }),
		*rackHost("other-pool", func(h *infrav1.RackHost) { h.Spec.Pool = "production" }),
	}

	candidates, skipped := selectClaimableHosts(hosts, testPool, "ber1-0")

	// Sorted by name, and the machine's own host counts as claimable so a
	// crash between the two status writes converges rather than double-claims.
	var names []string
	for _, c := range candidates {
		names = append(names, c.Name)
	}
	if got, want := strings.Join(names, ","), "free-a,free-b,mine"; got != want {
		t.Fatalf("candidates = %s, want %s", got, want)
	}
	if skipped != (skippedHosts{claimed: 1, quarantined: 1, unclaimable: 1, incomplete: 2}) {
		t.Fatalf("skip tally = %+v", skipped)
	}

	msg := skipped.describe()
	for _, want := range []string{"1 already claimed", "1 quarantined", "1 marked unclaimable", "2 missing an address"} {
		if !strings.Contains(msg, want) {
			t.Errorf("message %q does not mention %q; an operator cannot tell which of four problems this is", msg, want)
		}
	}
}

func TestNoAvailableHostSaysThePoolIsEmpty(t *testing.T) {
	machine := staticMachine("ber1-0")
	r := newStaticReconciler(t, machine)

	host, result, err := r.claimRackHost(context.Background(), machine)
	if err != nil || host != nil {
		t.Fatalf("claimRackHost = %v, %v; want no host and no error", host, err)
	}
	if result.RequeueAfter == 0 {
		t.Fatal("expected a requeue while waiting for inventory")
	}
	cond := conditions.Get(machine, shared.ProvisionedCondition)
	if cond == nil || cond.Reason != "NoAvailableHost" {
		t.Fatalf("condition = %+v, want NoAvailableHost", cond)
	}
	if !strings.Contains(cond.Message, "no hosts at all") {
		t.Fatalf("message %q should say the pool is empty rather than implying contention", cond.Message)
	}
}

// --- bootstrap failure ladder -----------------------------------------------

// stubPowerDriver records what the recovery path asked the outlet to do.
type stubPowerDriver struct {
	mu    sync.Mutex
	calls []string
	on    bool
	err   error
}

func (d *stubPowerDriver) State(context.Context, power.Outlet) (power.State, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.on {
		return power.StateOn, nil
	}
	return power.StateOff, nil
}

func (d *stubPowerDriver) Set(_ context.Context, _ power.Outlet, on bool) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.err != nil {
		return d.err
	}
	d.calls = append(d.calls, fmt.Sprintf("set=%t", on))
	d.on = on
	return nil
}

func (d *stubPowerDriver) recorded() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return append([]string(nil), d.calls...)
}

// registryWithShelly substitutes the stub for the shelly driver the fixtures'
// outlets name, so the recovery ladder is exercised without a plug on the
// bench.
func registryWithShelly(d power.Driver) *power.Registry {
	return power.NewRegistryWith(map[string]power.Driver{power.DriverShelly: d})
}

func TestBootstrapFailureCyclesTheOutletAtTheRebootThreshold(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		// One short of the threshold, so this failure crosses it.
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	r := newStaticReconciler(t, host, machine)
	driver := &stubPowerDriver{on: true}
	r.Power = registryWithShelly(driver)

	res := r.handleBootstrapFailure(context.Background(), machine, host, errors.New("ssh wedged"))

	if res.RequeueAfter == 0 {
		t.Fatal("expected a requeue after a bootstrap failure")
	}
	if got := driver.recorded(); len(got) != 2 || got[0] != "set=false" || got[1] != "set=true" {
		t.Fatalf("outlet calls = %v, want an off then an on", got)
	}
	if !machine.Status.BootstrapRebootIssued {
		t.Fatal("BootstrapRebootIssued not set; the next attempt would power-cycle the box again")
	}
	if machine.Status.RackHost != "mini-01" {
		t.Fatal("a reboot must not release the host")
	}
}

func TestBootstrapFailureCyclesTheOutletOnlyOnce(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		m.Status.BootstrapAttempts = 4
		m.Status.BootstrapRebootIssued = true
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	r := newStaticReconciler(t, host, machine)
	driver := &stubPowerDriver{on: true}
	r.Power = registryWithShelly(driver)

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("still wedged"))

	if got := driver.recorded(); len(got) != 0 {
		t.Fatalf("outlet was cycled again (%v); a long retry tail would reboot the box every minute", got)
	}
}

// A failed cycle must leave the flag clear so the next attempt retries it:
// otherwise a transient PDU error costs the host its only recovery.
func TestFailedPowerCycleIsRetriedOnTheNextAttempt(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	r := newStaticReconciler(t, host, machine)
	r.Power = registryWithShelly(&stubPowerDriver{on: true, err: errors.New("plug unreachable")})

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("ssh wedged"))

	if machine.Status.BootstrapRebootIssued {
		t.Fatal("BootstrapRebootIssued set despite a failed cycle; the host would never get its reboot")
	}
	if machine.Status.RackHost != "mini-01" {
		t.Fatal("a failed reboot must not release the host")
	}
}

// This is the load-bearing divergence from the Scaleway kind. Releasing the
// host without quarantining it hands the same broken box straight back on the
// next reconcile, and the Machine loops on it forever.
func TestBootstrapExhaustionQuarantinesTheHostRatherThanReleasingIt(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		m.Status.BootstrapAttempts = 7
		m.Status.Ready = true
		m.Spec.ProviderID = ptr.To("static-applesilicon://ber1/C07FC05JQ6NY")
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	spare := rackHost("mini-02")
	r := newStaticReconciler(t, host, spare, machine)
	r.Power = registryWithShelly(&stubPowerDriver{on: true})

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("unrecoverable"))

	quarantined := getHost(t, r, "mini-01")
	if !quarantined.Status.Quarantined {
		t.Fatal("host not quarantined; the machine would re-claim the box it just gave up on")
	}
	if quarantined.Status.ClaimedBy != "" {
		t.Fatalf("host still claimed by %q after exhaustion", quarantined.Status.ClaimedBy)
	}
	if !strings.Contains(quarantined.Status.QuarantineReason, "unrecoverable") {
		t.Fatalf("quarantine reason %q does not carry the cause", quarantined.Status.QuarantineReason)
	}

	// The machine must look hostless, not like a Ready machine pointing at a
	// box it no longer holds.
	if machine.Status.RackHost != "" || machine.Status.Ready || machine.Spec.ProviderID != nil || machine.Status.Addresses != nil {
		t.Fatalf("machine still bound to the quarantined host: %+v / %v", machine.Status, machine.Spec.ProviderID)
	}
	if machine.Status.BootstrapAttempts != 0 || machine.Status.BootstrapRebootIssued {
		t.Fatal("failure counters describe the discarded host and must reset with it")
	}

	// And the next claim must land on the spare rather than the quarantined box.
	next, _, err := r.claimRackHost(context.Background(), machine)
	if err != nil {
		t.Fatalf("re-claim: %v", err)
	}
	if next == nil || next.Name != "mini-02" {
		t.Fatalf("re-claimed %v, want the spare mini-02", next)
	}
}

// The TOFU pin belongs to the host that was given up on. Carrying it to the
// replacement makes every bootstrap fail on a fingerprint mismatch.
func TestBootstrapExhaustionDropsTheHostFingerprint(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		m.Status.BootstrapAttempts = 7
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-0" })
	r := newStaticReconciler(t, host, machine)
	r.Power = registryWithShelly(&stubPowerDriver{on: true})

	ctx := context.Background()
	if err := r.CredentialsManager.SetMachineCredentials(ctx, machine.Name, "pw", "tuist"); err != nil {
		t.Fatalf("seed credentials: %v", err)
	}
	if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, "SHA256:oldhost"); err != nil {
		t.Fatalf("seed fingerprint: %v", err)
	}

	r.handleBootstrapFailure(ctx, machine, host, errors.New("unrecoverable"))

	creds, err := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
	if err != nil {
		t.Fatalf("read bootstrap secret: %v", err)
	}
	if creds != nil && creds.HostFingerprint != "" {
		t.Fatalf("fingerprint %q survived the host it was pinned to", creds.HostFingerprint)
	}
}

// --- delete -----------------------------------------------------------------

func TestDeleteReleasesTheHostWithoutQuarantiningOrWipingIt(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		m.Finalizers = []string{StaticMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.ClaimedBy = "ber1-0"
		h.Status.ClaimedAt = ptr.To(metav1.Now())
	})
	r := newStaticReconciler(t, host, machine)

	if _, err := r.reconcileDelete(context.Background(), machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}

	released := getHost(t, r, "mini-01")
	if released.Status.ClaimedBy != "" || released.Status.ClaimedAt != nil {
		t.Fatalf("claim not released: %+v", released.Status)
	}
	// An ordinary delete is not a verdict on the hardware. Quarantining here
	// would take a healthy box out of the pool on every scale-down.
	if released.Status.Quarantined {
		t.Fatal("an ordinary delete quarantined the host")
	}
	if len(machine.Finalizers) != 0 {
		t.Fatalf("finalizer not removed: %v", machine.Finalizers)
	}
}

// A delete must never steal a claim that has already moved on: a retried
// delete, or one racing a re-claim, would otherwise release a host another
// Machine is actively bootstrapping.
func TestDeleteLeavesAClaimHeldBySomeoneElseAlone(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Status.RackHost = "mini-01"
		m.Finalizers = []string{StaticMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = "ber1-7" })
	r := newStaticReconciler(t, host, machine)

	if _, err := r.reconcileDelete(context.Background(), machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if got := getHost(t, r, "mini-01"); got.Status.ClaimedBy != "ber1-7" {
		t.Fatalf("claim held by %q was released by another machine's delete", got.Status.ClaimedBy)
	}
}

func TestDeleteOfAHostlessMachineCompletes(t *testing.T) {
	machine := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) {
		m.Finalizers = []string{StaticMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	r := newStaticReconciler(t, machine)

	if _, err := r.reconcileDelete(context.Background(), machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if len(machine.Finalizers) != 0 {
		t.Fatal("a machine that never claimed a host must still be able to finish deleting")
	}
}

// --- credentials ------------------------------------------------------------

// The rack fleet's key and sudo password come from 1Password via ESO. Minting
// either in-cluster produces a credential no host has ever heard of: a
// generated SSH key fails every dial forever, and a generated sudo password is
// XOR'd into /etc/kcpassword, which breaks auto-login so no console session
// exists and every `tart run` then fails for the life of the host.
func TestReconcileRefusesToMintFleetCredentials(t *testing.T) {
	for _, tc := range []struct {
		name    string
		secret  *corev1.Secret
		mention string
	}{
		{name: "no secret at all", secret: nil, mention: "not found"},
		{
			name:    "ESO mid-sync, key present but no password",
			secret:  fleetSecret(func(s *corev1.Secret) { delete(s.Data, "sudo-password") }),
			mention: "sudo-password",
		},
		{
			name:    "ESO mid-sync, password present but no key",
			secret:  fleetSecret(func(s *corev1.Secret) { delete(s.Data, "id_ed25519") }),
			mention: "id_ed25519",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			machine := staticMachine("ber1-0")
			objs := []runtime.Object{rackHost("mini-01"), machine}
			if tc.secret != nil {
				objs = append(objs, tc.secret)
			}
			r := newStaticReconciler(t, objs...)

			result, err := r.reconcileNormal(context.Background(), machine)
			if err != nil {
				t.Fatalf("reconcileNormal: %v", err)
			}
			if result.RequeueAfter == 0 {
				t.Fatal("expected a requeue while ESO syncs")
			}
			cond := conditions.Get(machine, BootstrappedCondition)
			if cond == nil || cond.Reason != "FleetCredentialsUnavailable" {
				t.Fatalf("condition = %+v, want FleetCredentialsUnavailable", cond)
			}
			if !strings.Contains(cond.Message, tc.mention) {
				t.Errorf("message %q does not say what is missing (%q)", cond.Message, tc.mention)
			}
			// Nothing may have been claimed: a claim taken before the
			// credentials exist holds a box hostage through the ESO outage.
			if got := getHost(t, r, "mini-01"); got.Status.ClaimedBy != "" {
				t.Fatalf("claimed %s before the fleet credential was readable", got.Name)
			}
			// And nothing may have been minted into the Secret.
			minted := &corev1.Secret{}
			err = r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: testFleet + "-ssh"}, minted)
			if tc.secret == nil {
				if !apierrors.IsNotFound(err) {
					t.Fatal("a fleet Secret was created; the generated key is one no MDM-provisioned host will accept")
				}
				return
			}
			if err != nil {
				t.Fatalf("get fleet secret: %v", err)
			}
			if len(minted.Data) != len(tc.secret.Data) {
				t.Fatalf("fleet Secret gained fields: %v", minted.Data)
			}
		})
	}
}

// --- sizing -----------------------------------------------------------------

// The overlay and the hash must be computed from the same resolution, or a host
// is stamped with the hash of a config it never received and a later change to
// the overridden field cannot drift it.
func TestDesiredHostConfigHashMatchesWhatIsPushed(t *testing.T) {
	fleet := bootstrap.Config{
		TartKubeletBinary:    []byte("tart-kubelet"),
		HostCPU:              8,
		HostMemoryMB:         14336,
		MaxPods:              3,
		RunnerCacheVolumeGiB: 80,
		VNCRelayPort:         DashboardVNCRelayPort,
	}
	for _, tc := range []struct {
		name    string
		machine *infrav1.StaticAppleSiliconMachine
	}{
		{"fleet defaults", staticMachine("m")},
		{"overridden sizing", staticMachine("m", func(m *infrav1.StaticAppleSiliconMachine) {
			m.Spec.HostCPU = 18
			m.Spec.HostMemoryMB = 61440
			m.Spec.MaxPods = 5
			m.Spec.GuestCapacity = 2
		})},
		{"cache volumes disabled", staticMachine("m", func(m *infrav1.StaticAppleSiliconMachine) {
			m.Spec.RunnerCacheVolumeGiB = ptr.To(0)
		})},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := &StaticAppleSiliconMachineReconciler{FleetConfig: fleet, DefaultGuestCapacity: 1}
			pushed := r.hostConfig(tc.machine, bootstrap.PerHost{
				IP: "192.168.0.41", NodeName: "m", Kubeconfig: "kubeconfig",
			})
			if want, have := r.desiredHostConfigHash(tc.machine), bootstrap.HostConfigHash(pushed); want != have {
				t.Fatalf("stamped hash %s != hash of what was pushed %s", want, have)
			}
		})
	}
}

// The prototype M1 has a 256 GB disk that cannot hold the fleet's normal cache
// quota, so an explicit 0 has to mean "off" rather than collapsing into unset
// and silently inheriting a quota whose diskutil call would fail.
func TestRunnerCacheVolumeResolvesOnPresence(t *testing.T) {
	r := &StaticAppleSiliconMachineReconciler{
		FleetConfig:          bootstrap.Config{RunnerCacheVolumeGiB: 80},
		DefaultGuestCapacity: 1,
	}
	for _, tc := range []struct {
		name string
		spec *int
		want int
	}{
		{"unset inherits the fleet default", nil, 80},
		{"explicit zero disables", ptr.To(0), 0},
		{"explicit value wins", ptr.To(40), 40},
		{"negative is treated as unset", ptr.To(-1), 80},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := staticMachine("m", func(m *infrav1.StaticAppleSiliconMachine) { m.Spec.RunnerCacheVolumeGiB = tc.spec })
			if got := r.hostSizing(m).RunnerCacheVolumeGiB; got != tc.want {
				t.Fatalf("RunnerCacheVolumeGiB = %d, want %d", got, tc.want)
			}
		})
	}

	unset := staticMachine("m")
	disabled := staticMachine("m", func(m *infrav1.StaticAppleSiliconMachine) { m.Spec.RunnerCacheVolumeGiB = ptr.To(0) })
	if r.desiredHostConfigHash(unset) == r.desiredHostConfigHash(disabled) {
		t.Fatal("disabling cache volumes does not drift the host; the change would never reach it")
	}
}

// --- egress + node binding --------------------------------------------------

// Both macOS kinds must produce an identically-shaped egress Service: alloy
// discovers minis by the `tuist.dev/macmini-egress` label, so a rack mini that
// labelled itself differently would silently never be scraped.
func TestEgressServiceIsShapedLikeTheScalewayKinds(t *testing.T) {
	machine := staticMachine("ber1-0")
	r := newStaticReconciler(t, machine)
	r.EgressNamespace = "tailscale"
	r.EgressProxyGroup = "macmini-egress"
	r.EgressMagicDNSSuffix = "tail1234.ts.net"
	r.DefaultGuestCapacity = 1

	if err := r.reconcileTailscaleEgressService(context.Background(), machine); err != nil {
		t.Fatalf("reconcileTailscaleEgressService: %v", err)
	}

	svc := &corev1.Service{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: "tailscale", Name: "ber1-0"}, svc); err != nil {
		t.Fatalf("get egress Service: %v", err)
	}
	if svc.Labels["tuist.dev/macmini-egress"] != "true" {
		t.Fatal("missing the label alloy's Service discovery filters on; this mini would never be scraped")
	}
	if svc.Labels["app.kubernetes.io/managed-by"] != operatorName {
		t.Fatalf("managed-by = %q, want %q: the same operator manages both kinds", svc.Labels["app.kubernetes.io/managed-by"], operatorName)
	}
	if svc.Annotations["tailscale.com/tailnet-fqdn"] != "ber1-0.tail1234.ts.net" {
		t.Fatalf("tailnet-fqdn = %q", svc.Annotations["tailscale.com/tailnet-fqdn"])
	}
	// :22 must be declared or the drift loop has no tailnet fallback.
	var ports []string
	for _, p := range svc.Spec.Ports {
		ports = append(ports, p.Name)
	}
	for _, want := range []string{"node-exporter", "tart-kubelet", "pod-metrics", "vnc-relay", "ssh"} {
		if !containsString(ports, want) {
			t.Errorf("port %q missing from %v", want, ports)
		}
	}
}

func containsString(haystack []string, needle string) bool {
	for _, h := range haystack {
		if h == needle {
			return true
		}
	}
	return false
}

func TestNodeLabelsMatchTheScalewayKind(t *testing.T) {
	// One workload pins `tuist.dev/fleet`; a rack mini and a rented one in the
	// same fleet must both carry it or the nodeSelector splits the fleet.
	m := staticMachine("ber1-0")
	if got := staticMachineNodeLabels(m)["tuist.dev/fleet"]; got != testFleet {
		t.Fatalf("fleet label = %q, want %q", got, testFleet)
	}
	if labels := staticMachineNodeLabels(staticMachine("x", func(m *infrav1.StaticAppleSiliconMachine) { m.Spec.FleetName = "" })); labels != nil {
		t.Fatalf("labels for a fleetless machine = %v, want nil", labels)
	}
}

// A serial-less inventory record still has to produce a well-formed providerID:
// a missing serial degrades the identity's durability, it does not break the
// Machine, so the claim filter deliberately does not require one.
func TestProviderIDFallsBackToTheRecordNameWithoutASerial(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Spec.Serial = "" })
	if want, got := "static-applesilicon://ber1/mini-01", staticProviderID(host); got != want {
		t.Fatalf("providerID = %q, want %q", got, want)
	}
}

func TestNodeDriftDetectionSharedWithTheScalewayKind(t *testing.T) {
	machine := staticMachine("ber1-0")
	conditions.MarkTrue(machine, BootstrappedCondition)
	r := newStaticReconciler(t, machine)

	// Inside the grace window a missing Node is the first registration still
	// propagating, not drift.
	missing, err := nodeMissingAfterBootstrap(context.Background(), r.Client, machine, machine.Name)
	if err != nil {
		t.Fatalf("nodeMissingAfterBootstrap: %v", err)
	}
	if missing {
		t.Fatal("fired inside the grace window; every fresh bootstrap would immediately re-bootstrap")
	}

	for i, c := range machine.Status.Conditions {
		if c.Type == BootstrappedCondition {
			machine.Status.Conditions[i].LastTransitionTime = metav1.NewTime(time.Now().Add(-5 * time.Minute))
		}
	}
	missing, err = nodeMissingAfterBootstrap(context.Background(), r.Client, machine, machine.Name)
	if err != nil {
		t.Fatalf("nodeMissingAfterBootstrap: %v", err)
	}
	if !missing {
		t.Fatal("a Node missing past the grace window must drive a re-bootstrap")
	}
}

// --- watches ----------------------------------------------------------------

// A host becoming claimable must wake the machines that could take it, or a
// rack bring-up appears stuck for a requeue interval per host.
func TestRackHostEventWakesHolderAndWaitingMachines(t *testing.T) {
	holder := staticMachine("ber1-0", func(m *infrav1.StaticAppleSiliconMachine) { m.Status.RackHost = "mini-01" })
	waiting := staticMachine("ber1-1")
	otherPool := staticMachine("prod-0", func(m *infrav1.StaticAppleSiliconMachine) { m.Spec.AdoptPool = "production" })
	settled := staticMachine("ber1-2", func(m *infrav1.StaticAppleSiliconMachine) { m.Status.RackHost = "mini-09" })
	r := newStaticReconciler(t, holder, waiting, otherPool, settled, rackHost("mini-01"))

	requests := r.staticMachinesForRackHost(context.Background(), rackHost("mini-01"))

	var names []string
	for _, req := range requests {
		names = append(names, req.Name)
	}
	if len(names) != 2 || !containsString(names, "ber1-0") || !containsString(names, "ber1-1") {
		t.Fatalf("woke %v, want the holder and the machine waiting in that pool", names)
	}
}

func TestCAPIMachineMappingIgnoresOtherKinds(t *testing.T) {
	for _, tc := range []struct {
		kind string
		want int
	}{
		{"StaticAppleSiliconMachine", 1},
		{"ScalewayAppleSiliconMachine", 0},
	} {
		m := &clusterv1.Machine{Spec: clusterv1.MachineSpec{
			InfrastructureRef: corev1.ObjectReference{
				Kind: tc.kind, Name: "ber1-0", Namespace: testNamespace,
			},
		}}
		if got := len(staticMachineForCAPIMachine(context.Background(), m)); got != tc.want {
			t.Errorf("kind %s mapped to %d requests, want %d", tc.kind, got, tc.want)
		}
	}
}
