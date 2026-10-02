package macos

import (
	"context"
	"errors"
	"fmt"
	"slices"
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
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	testNamespace = "ns"
	testFleet     = "tuist-tuist-ber1-fleet"
)

// --- fixtures ---------------------------------------------------------------

func rackHost(name string, mutate ...func(*infrav1.RackHost)) *infrav1.RackHost {
	h := &infrav1.RackHost{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace},
		Spec: infrav1.RackHostSpec{
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
		Status: infrav1.RackHostStatus{Machine: "ber1-0"},
	}
	for _, m := range mutate {
		m(h)
	}
	return h
}

func rackMachine(name string, mutate ...func(*infrav1.RackAppleSiliconMachine)) *infrav1.RackAppleSiliconMachine {
	m := &infrav1.RackAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace},
		Spec: infrav1.RackAppleSiliconMachineSpec{
			Host:      "mini-01",
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

func newRackReconciler(t *testing.T, objs ...runtime.Object) *RackAppleSiliconMachineReconciler {
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
		WithStatusSubresource(&infrav1.RackAppleSiliconMachine{}, &infrav1.RackHost{}).
		Build()
	return &RackAppleSiliconMachineReconciler{
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

func getHost(t *testing.T, r *RackAppleSiliconMachineReconciler, name string) *infrav1.RackHost {
	t.Helper()
	h := &infrav1.RackHost{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: name}, h); err != nil {
		t.Fatalf("get rack host %s: %v", name, err)
	}
	return h
}

// --- host -------------------------------------------------------------------

func TestHostOfResolvesItsHostAndComposesTheProviderID(t *testing.T) {
	machine := rackMachine("ber1-0")
	r := newRackReconciler(t, rackHost("mini-01"), machine)

	host, _, err := r.hostOf(context.Background(), machine)
	if err != nil {
		t.Fatalf("hostOf: %v", err)
	}
	if host == nil || host.Name != "mini-01" {
		t.Fatalf("resolved %v, want mini-01", host)
	}
	// The providerID is composed from the two DURABLE physical facts, not the
	// address: re-cabling a box onto a new IP must not change its identity to
	// CAPI, or the Node binding breaks on a network change.
	if want := "rack-applesilicon://ber1/C07FC05JQ6NY"; ptr.Deref(machine.Spec.ProviderID, "") != want {
		t.Fatalf("providerID = %q, want %q", ptr.Deref(machine.Spec.ProviderID, ""), want)
	}
	if len(machine.Status.Addresses) != 1 || machine.Status.Addresses[0].Address != "192.168.0.41" {
		t.Fatalf("addresses = %+v, want the host address", machine.Status.Addresses)
	}
	if !conditions.IsTrue(machine, shared.ProvisionedCondition) {
		t.Fatal("Provisioned not set once the host resolved")
	}
}

// A machine that is not its host's may not dial the box: two machines pushing
// config to one host would fight over its Node.
func TestHostOfRefusesAHostThatIsNotItsOwn(t *testing.T) {
	for _, tc := range []struct {
		name    string
		machine *infrav1.RackAppleSiliconMachine
		objs    []runtime.Object
		reason  string
	}{
		{
			name:    "no host named",
			machine: rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.Host = "" }),
			reason:  "NoHost",
		},
		{name: "host gone", machine: rackMachine("ber1-0"), reason: "HostNotFound"},
		{
			name:    "host keeps another machine",
			machine: rackMachine("ber1-0"),
			objs:    []runtime.Object{rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.Machine = "ber1-7" })},
			reason:  "NotTheHostsMachine",
		},
		{
			name:    "host with no address",
			machine: rackMachine("ber1-0"),
			objs:    []runtime.Object{rackHost("mini-01", func(h *infrav1.RackHost) { h.Spec.Address = "" })},
			reason:  "IncompleteHost",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := newRackReconciler(t, append(tc.objs, tc.machine)...)

			host, _, err := r.hostOf(context.Background(), tc.machine)
			if err != nil {
				t.Fatalf("hostOf: %v", err)
			}
			if host != nil {
				t.Fatalf("resolved %s; this machine would dial a box that is not its own", host.Name)
			}
			if cond := conditions.Get(tc.machine, shared.ProvisionedCondition); cond == nil || cond.Reason != tc.reason {
				t.Fatalf("Provisioned = %+v, want reason %s", cond, tc.reason)
			}
			if tc.machine.Spec.ProviderID != nil {
				t.Fatal("a providerID was composed for a machine with no host of its own")
			}
		})
	}
}

// A quarantined host is left alone until the quarantine expires: bootstrapping
// it on every reconcile is exactly what the quarantine holds off.
func TestQuarantinedHostIsNotBootstrapped(t *testing.T) {
	machine := rackMachine("ber1-0")
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Quarantined = true
		h.Status.QuarantinedAt = ptr.To(metav1.Now())
	})
	// No fleet Secret: reaching the bootstrap would fail on the credentials.
	r := newRackReconciler(t, host, machine)

	result, err := r.reconcileNormal(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileNormal: %v", err)
	}
	if machine.Status.Phase != "Quarantined" || result.RequeueAfter == 0 {
		t.Fatalf("phase %q, result %+v; want a Quarantined machine waiting", machine.Status.Phase, result)
	}
	if cond := conditions.Get(machine, BootstrappedCondition); cond != nil {
		t.Fatalf("Bootstrapped = %+v; a quarantined host was bootstrapped", cond)
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
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		// One short of the threshold, so this failure crosses it.
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
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
}

func TestBootstrapFailureCyclesTheOutletOnlyOnce(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 4
		m.Status.BootstrapRebootIssued = true
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
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
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 2
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
	r.Power = registryWithShelly(&stubPowerDriver{on: true, err: errors.New("plug unreachable")})

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("ssh wedged"))

	if machine.Status.BootstrapRebootIssued {
		t.Fatal("BootstrapRebootIssued set despite a failed cycle; the host would never get its reboot")
	}
}

// Giving up on a host quarantines it rather than retrying it on every
// reconcile, and the machine stays the host's: there is no other box for it.
func TestBootstrapExhaustionQuarantinesTheHost(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 7
		m.Status.BootstrapRebootIssued = true
		m.Status.Ready = true
		m.Spec.ProviderID = ptr.To("rack-applesilicon://ber1/C07FC05JQ6NY")
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
	r.Power = registryWithShelly(&stubPowerDriver{on: true})

	r.handleBootstrapFailure(context.Background(), machine, host, errors.New("unrecoverable"))

	quarantined := getHost(t, r, "mini-01")
	if !quarantined.Status.Quarantined || quarantined.Status.QuarantinedAt == nil {
		t.Fatalf("host not quarantined: %+v", quarantined.Status)
	}
	if !strings.Contains(quarantined.Status.QuarantineReason, "unrecoverable") {
		t.Fatalf("quarantine reason %q does not carry the cause", quarantined.Status.QuarantineReason)
	}
	if quarantined.Status.Machine != "ber1-0" || machine.Spec.Host != "mini-01" {
		t.Fatal("exhaustion unbound the machine from its host")
	}
	if ptr.Deref(machine.Spec.ProviderID, "") != "rack-applesilicon://ber1/C07FC05JQ6NY" {
		t.Fatal("the providerID is the box's identity and must survive a quarantine")
	}
	if machine.Status.Ready || machine.Status.Phase != "Quarantined" {
		t.Fatalf("machine reads Ready=%t phase %q, want not ready and Quarantined", machine.Status.Ready, machine.Status.Phase)
	}
	if machine.Status.BootstrapAttempts != 0 || machine.Status.BootstrapRebootIssued {
		t.Fatal("failure counters must start over when the quarantine expires")
	}
}

// The TOFU pin is dropped with the rest of the identity: a host re-imaged under
// a new host key would fail every bootstrap on the old pin.
func TestBootstrapExhaustionDropsTheHostFingerprint(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 7
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
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

func TestDeleteDropsTheIdentityAndLeavesTheHostAlone(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Finalizers = []string{RackMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-0"}}
	sa := &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-ber1-0", Namespace: testNamespace}}
	r := newRackReconciler(t, rackHost("mini-01"), machine, node, sa)
	ctx := context.Background()

	if _, err := r.reconcileDelete(ctx, machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}

	if err := r.Get(ctx, types.NamespacedName{Name: "ber1-0"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Error("the Node survived its machine")
	}
	if err := r.Get(ctx, types.NamespacedName{Namespace: testNamespace, Name: "tart-kubelet-ber1-0"}, &corev1.ServiceAccount{}); !apierrors.IsNotFound(err) {
		t.Error("the node identity survived its machine")
	}
	// An ordinary delete is not a verdict on the hardware.
	if getHost(t, r, "mini-01").Status.Quarantined {
		t.Fatal("an ordinary delete quarantined the host")
	}
	if len(machine.Finalizers) != 0 {
		t.Fatalf("finalizer not removed: %v", machine.Finalizers)
	}
}

func TestDeleteOfAHostlessMachineCompletes(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Finalizers = []string{RackMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	r := newRackReconciler(t, machine)

	if _, err := r.reconcileDelete(context.Background(), machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if len(machine.Finalizers) != 0 {
		t.Fatal("a machine with no host must still be able to finish deleting")
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
			machine := rackMachine("ber1-0")
			objs := []runtime.Object{rackHost("mini-01"), machine}
			if tc.secret != nil {
				objs = append(objs, tc.secret)
			}
			r := newRackReconciler(t, objs...)

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
		machine *infrav1.RackAppleSiliconMachine
	}{
		{"fleet defaults", rackMachine("m")},
		{"overridden sizing", rackMachine("m", func(m *infrav1.RackAppleSiliconMachine) {
			m.Spec.HostCPU = 18
			m.Spec.HostMemoryMB = 61440
			m.Spec.MaxPods = 5
			m.Spec.GuestCapacity = 2
		})},
		{"cache volumes disabled", rackMachine("m", func(m *infrav1.RackAppleSiliconMachine) {
			m.Spec.RunnerCacheVolumeGiB = ptr.To(0)
		})},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := &RackAppleSiliconMachineReconciler{FleetConfig: fleet, DefaultGuestCapacity: 1}
			host := rackHost("mini-01", func(h *infrav1.RackHost) {
				h.Spec.SSHIngressAllowCIDRs = []string{"192.168.0.223/32"}
			})
			pushed := r.hostConfig(tc.machine, host, bootstrap.PerHost{
				IP: "192.168.0.41", NodeName: "m", Kubeconfig: "kubeconfig",
			})
			if want, have := r.desiredHostConfigHash(tc.machine, host), bootstrap.HostConfigHash(pushed); want != have {
				t.Fatalf("stamped hash %s != hash of what was pushed %s", want, have)
			}
		})
	}
}

// The prototype M1 has a 256 GB disk that cannot hold the fleet's normal cache
// quota, so an explicit 0 has to mean "off" rather than collapsing into unset
// and silently inheriting a quota whose diskutil call would fail.
func TestRunnerCacheVolumeResolvesOnPresence(t *testing.T) {
	r := &RackAppleSiliconMachineReconciler{
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
			m := rackMachine("m", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.RunnerCacheVolumeGiB = tc.spec })
			if got := r.hostSizing(m).RunnerCacheVolumeGiB; got != tc.want {
				t.Fatalf("RunnerCacheVolumeGiB = %d, want %d", got, tc.want)
			}
		})
	}

	unset := rackMachine("m")
	disabled := rackMachine("m", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.RunnerCacheVolumeGiB = ptr.To(0) })
	host := rackHost("mini-01")
	if r.desiredHostConfigHash(unset, host) == r.desiredHostConfigHash(disabled, host) {
		t.Fatal("disabling cache volumes does not drift the host; the change would never reach it")
	}
}

// --- reachable without the host's own tailnet identity ----------------------

// On 2026-09-18 the BER1 prototype came back from a few days unpowered with its
// tailnet device gone, and its SSH ingress guard dropped the operator's LAN
// dial: through the subnet router that dial arrives from the router's own
// address, which the guard had only ever admitted as a session source, since
// overwritten. A rented mini would still have been reachable on its
// allow-listed public address; a rack mini has no such path, so the router has
// to be in its allow list for good.
func TestRackHostConfigAdmitsItsSubnetRouters(t *testing.T) {
	// Spare capacity, so an overlay that appended to the shared slice in place
	// would write the first host's router where the second host reads.
	fleetAllow := make([]string, 1, 4)
	fleetAllow[0] = "78.47.186.71/32"
	r := &RackAppleSiliconMachineReconciler{
		FleetConfig:          bootstrap.Config{SSHIngressAllowCIDRs: fleetAllow},
		DefaultGuestCapacity: 1,
	}
	machine := rackMachine("m")
	first := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.SSHIngressAllowCIDRs = []string{"192.168.0.223/32"}
	})
	second := rackHost("mini-02", func(h *infrav1.RackHost) {
		h.Spec.SSHIngressAllowCIDRs = []string{"192.168.0.224/32", "192.168.0.225/32"}
	})

	firstCfg := r.hostConfig(machine, first, bootstrap.PerHost{})
	secondCfg := r.hostConfig(machine, second, bootstrap.PerHost{})

	if want := []string{"78.47.186.71/32", "192.168.0.223/32"}; !slices.Equal(firstCfg.SSHIngressAllowCIDRs, want) {
		t.Fatalf("first host allow list = %v, want %v", firstCfg.SSHIngressAllowCIDRs, want)
	}
	if want := []string{"78.47.186.71/32", "192.168.0.224/32", "192.168.0.225/32"}; !slices.Equal(secondCfg.SSHIngressAllowCIDRs, want) {
		t.Fatalf("second host allow list = %v, want %v", secondCfg.SSHIngressAllowCIDRs, want)
	}
	if want := []string{"78.47.186.71/32"}; !slices.Equal(r.FleetConfig.SSHIngressAllowCIDRs, want) {
		t.Fatalf("the shared fleet allow list became %v; the rented fleet reads the same value", r.FleetConfig.SSHIngressAllowCIDRs)
	}
}

// A router address that changes (a new DHCP lease, a second router for
// failover) has to reach a host that is already Ready, which only happens if it
// moves the hash the drift loop compares.
func TestSubnetRouterChangeDriftsTheHost(t *testing.T) {
	r := &RackAppleSiliconMachineReconciler{DefaultGuestCapacity: 1}
	machine := rackMachine("m")
	before := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.SSHIngressAllowCIDRs = []string{"192.168.0.223/32"}
	})
	after := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.SSHIngressAllowCIDRs = []string{"192.168.0.223/32", "192.168.0.224/32"}
	})
	if r.desiredHostConfigHash(machine, before) == r.desiredHostConfigHash(machine, after) {
		t.Fatal("adding a subnet router does not drift the host; the guard would keep dropping the new router")
	}
}

// Tailscale deletes an ephemeral device 30 to 60 minutes after it was last
// seen, however long it had been online, and a key minted from an OAuth client
// is ephemeral unless told otherwise. A rack mini powered off for longer than
// that comes back with no tailnet identity. The rented fleet shares the same
// FleetConfig value and must keep joining ephemeral, so the overlay must not
// leak into it.
func TestRackHostJoinsTheTailnetAsAStandardDevice(t *testing.T) {
	r := &RackAppleSiliconMachineReconciler{DefaultGuestCapacity: 1}
	pushed := r.hostConfig(rackMachine("m"), rackHost("mini-01"), bootstrap.PerHost{})
	if !pushed.TailscalePersistentDevice {
		t.Fatal("a rack host is pushed an ephemeral tailnet join; powering it off for an hour deletes its device")
	}
	if r.FleetConfig.TailscalePersistentDevice {
		t.Fatal("the rack overlay changed the shared fleet config; rented minis would stop joining ephemeral")
	}
}

// --- egress + node binding --------------------------------------------------

// Both macOS kinds must produce an identically-shaped egress Service: alloy
// discovers minis by the `tuist.dev/macmini-egress` label, so a rack mini that
// labelled itself differently would silently never be scraped.
func TestEgressServiceIsShapedLikeTheScalewayKinds(t *testing.T) {
	machine := rackMachine("ber1-0")
	r := newRackReconciler(t, machine)
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
	m := rackMachine("ber1-0")
	if got := rackMachineNodeLabels(m)["tuist.dev/fleet"]; got != testFleet {
		t.Fatalf("fleet label = %q, want %q", got, testFleet)
	}
	if labels := rackMachineNodeLabels(rackMachine("x", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.FleetName = "" })); labels != nil {
		t.Fatalf("labels for a fleetless machine = %v, want nil", labels)
	}
}

// A serial-less inventory record still has to produce a well-formed providerID:
// a missing serial degrades the identity's durability, it does not break the
// Machine, so hostOf deliberately does not require one.
func TestProviderIDFallsBackToTheRecordNameWithoutASerial(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Spec.Serial = "" })
	if want, got := "rack-applesilicon://ber1/mini-01", rackProviderID(host); got != want {
		t.Fatalf("providerID = %q, want %q", got, want)
	}
}

func TestNodeDriftDetectionSharedWithTheScalewayKind(t *testing.T) {
	machine := rackMachine("ber1-0")
	conditions.MarkTrue(machine, BootstrappedCondition)
	r := newRackReconciler(t, machine)

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

func TestRackHostEventWakesItsMachine(t *testing.T) {
	requests := rackMachineForRackHost(context.Background(), rackHost("mini-01"))
	if len(requests) != 1 || requests[0].Name != "ber1-0" {
		t.Fatalf("woke %v, want the host's machine ber1-0", requests)
	}
	none := rackHost("mini-02", func(h *infrav1.RackHost) { h.Status.Machine = "" })
	if requests := rackMachineForRackHost(context.Background(), none); len(requests) != 0 {
		t.Fatalf("a host with no machine woke %v", requests)
	}
}

func TestCAPIMachineMappingIgnoresOtherKinds(t *testing.T) {
	for _, tc := range []struct {
		kind string
		want int
	}{
		{"RackAppleSiliconMachine", 1},
		{"ScalewayAppleSiliconMachine", 0},
	} {
		m := &clusterv1.Machine{Spec: clusterv1.MachineSpec{
			InfrastructureRef: corev1.ObjectReference{
				Kind: tc.kind, Name: "ber1-0", Namespace: testNamespace,
			},
		}}
		if got := len(rackMachineForCAPIMachine(context.Background(), m)); got != tc.want {
			t.Errorf("kind %s mapped to %d requests, want %d", tc.kind, got, tc.want)
		}
	}
}

// --- rack egress (the first-dial path) --------------------------------------

func withEgress(r *RackAppleSiliconMachineReconciler) *RackAppleSiliconMachineReconciler {
	r.EgressNamespace = "tailscale-operator"
	r.EgressProxyGroup = "macmini-egress"
	r.EgressMagicDNSSuffix = "taild6d7bb.ts.net"
	return r
}

// The operator has no route to a rack host: it is on a LAN behind a subnet
// router, reachable only through the egress ProxyGroup. So the dial has to go
// to the Service, not the address. Verified against staging on 2026-09-09: a
// pod dialling 192.168.0.41 directly gets nothing but its default route.
func TestRackHostIsDialledThroughItsEgressService(t *testing.T) {
	host := rackHost("mini-01")
	r := withEgress(newRackReconciler(t, host))

	want := "rack-mini-01.tailscale-operator.svc.cluster.local"
	if got := r.dialTarget(host); got != want {
		t.Fatalf("dial target = %q, want the egress Service %q", got, want)
	}
}

// Without a tailnet egress there is nothing to proxy through, so the raw
// address is the only option: the OSS shape, or a cluster sitting on the rack's
// own network.
func TestRackHostFallsBackToItsAddressWithoutEgress(t *testing.T) {
	host := rackHost("mini-01")
	r := newRackReconciler(t, host)

	if got := r.dialTarget(host); got != "192.168.0.41" {
		t.Fatalf("dial target = %q, want the raw address", got)
	}
}

// The Service fronts the host's LAN address with `tailnet-ip`, NOT a MagicDNS
// name: a rack mini has no tailnet identity until bootstrap gives it one, so
// the FQDN annotation the rented fleet uses would point at nothing.
func TestRackEgressServiceFrontsTheAddressNotAnFQDN(t *testing.T) {
	machine := rackMachine("ber1-0")
	host := rackHost("mini-01")
	r := withEgress(newRackReconciler(t, host, machine))

	if err := r.reconcileRackEgress(context.Background(), machine, host); err != nil {
		t.Fatalf("reconcileRackEgress: %v", err)
	}

	svc := &corev1.Service{}
	if err := r.Get(context.Background(), types.NamespacedName{
		Namespace: "tailscale-operator", Name: "rack-mini-01",
	}, svc); err != nil {
		t.Fatalf("get rack egress Service: %v", err)
	}
	if got := svc.Annotations["tailscale.com/tailnet-ip"]; got != "192.168.0.41" {
		t.Fatalf("tailnet-ip = %q, want the host address", got)
	}
	if _, wrong := svc.Annotations["tailscale.com/tailnet-fqdn"]; wrong {
		t.Fatal("annotated with tailnet-fqdn; a rack host has no tailnet identity before bootstrap")
	}
	if svc.Annotations["tailscale.com/proxy-group"] != "macmini-egress" {
		t.Fatalf("proxy-group = %q", svc.Annotations["tailscale.com/proxy-group"])
	}
	// Alloy discovers scrape targets by this label. This Service exposes only
	// SSH, so carrying it would add a target that fails every scrape.
	if _, scraped := svc.Labels["tuist.dev/macmini-egress"]; scraped {
		t.Fatal("labelled for alloy discovery; it exposes only :22 and would fail every scrape")
	}
	if len(svc.Spec.Ports) != 1 || svc.Spec.Ports[0].Port != 22 {
		t.Fatalf("ports = %+v, want only :22", svc.Spec.Ports)
	}
}

// Both Services are named differently and must both be cleaned up: one after
// the Machine, one after the host it held.
func TestDeleteRemovesBothEgressServices(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Finalizers = []string{RackMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	host := rackHost("mini-01")
	r := withEgress(newRackReconciler(t, host, machine))
	ctx := context.Background()

	for _, n := range []string{"ber1-0", "rack-mini-01"} {
		if err := r.Create(ctx, &corev1.Service{ObjectMeta: metav1.ObjectMeta{
			Name: n, Namespace: "tailscale-operator",
		}}); err != nil {
			t.Fatalf("seed Service %s: %v", n, err)
		}
	}

	if _, err := r.reconcileDelete(ctx, machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}

	for _, n := range []string{"ber1-0", "rack-mini-01"} {
		err := r.Get(ctx, types.NamespacedName{Namespace: "tailscale-operator", Name: n}, &corev1.Service{})
		if !apierrors.IsNotFound(err) {
			t.Fatalf("Service %s survived the delete (err=%v); it would strand an egress proxy binding", n, err)
		}
	}
}

// The host-named Service is the host's current machine's first-dial path, so a
// machine that is not the host's leaves it.
func TestDeleteLeavesTheHostServiceOfItsCurrentMachine(t *testing.T) {
	machine := rackMachine("ber1-9", func(m *infrav1.RackAppleSiliconMachine) {
		m.Finalizers = []string{RackMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	r := withEgress(newRackReconciler(t, rackHost("mini-01"), machine))
	ctx := context.Background()
	if err := r.Create(ctx, &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: "rack-mini-01", Namespace: "tailscale-operator"}}); err != nil {
		t.Fatalf("seed Service: %v", err)
	}

	if _, err := r.reconcileDelete(ctx, machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}

	if err := r.Get(ctx, types.NamespacedName{Namespace: "tailscale-operator", Name: "rack-mini-01"}, &corev1.Service{}); err != nil {
		t.Fatalf("deleted the host Service ber1-0 dials the host through (err=%v)", err)
	}
}

// Testing dialTarget() alone proves nothing: what matters is that the value
// bootstrap actually receives is the egress name. An earlier version of this
// suite asserted only the helper, and a mutation swapping `IP:` back to
// host.Spec.Address passed it. The host would then be dialled at an address
// the operator has no route to, and every bootstrap would time out.
//
// The credential machinery is real here rather than stubbed; the token Secret
// is pre-seeded so EnsureNodeIdentity returns without waiting for a controller
// that does not exist in a fake client.
func TestPerHostConfigDialsTheEgressServiceNotTheAddress(t *testing.T) {
	machine := rackMachine("ber1-0")
	host := rackHost("mini-01")
	tokenSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tart-kubelet-ber1-0-token",
			Namespace: testNamespace,
		},
		Data: map[string][]byte{"token": []byte("tok"), "ca.crt": []byte("ca")},
	}
	tailscaleSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "ts", Namespace: testNamespace},
		Data:       map[string][]byte{"auth-key": []byte("tskey-abc")},
	}
	r := withEgress(newRackReconciler(t, host, machine, tokenSecret, tailscaleSecret))
	r.CredentialsManager.NodeIdentityClusterRole = "tart-kubelet"
	r.CredentialsManager.TailscaleAuthKeySecretName = "ts"
	r.Kubeconfig = &kubeconfig.Builder{APIServerURL: "https://api.staging.example:6443"}

	perHost, prepErr := r.perHostConfig(context.Background(), machine, host, []byte("key"), "pw", "")
	if prepErr != nil {
		t.Fatalf("perHostConfig: %v", prepErr.err)
	}

	want := "rack-mini-01.tailscale-operator.svc.cluster.local"
	if perHost.IP != want {
		t.Fatalf("bootstrap would dial %q, want the egress Service %q; the operator has no route to the raw address", perHost.IP, want)
	}
	if perHost.SSHUser != "tuist" {
		t.Fatalf("SSHUser = %q, want the host's service account", perHost.SSHUser)
	}

	// And the dial target must NOT reach the host-config hash, or two hosts
	// with identical config would drift each other.
	withEgressTarget := r.hostConfig(machine, host, perHost)
	if bootstrap.HostConfigHash(withEgressTarget) != r.desiredHostConfigHash(machine, host) {
		t.Fatal("the dial target changed the host-config hash; it is transport, not config")
	}
}

// --- quarantine retires the identity -----------------------------------------

// Bootstrap starts tart-kubelet (loadTartKubeletLaunchd) BEFORE its last fatal
// step, installLogShipper. So a host can exhaust its attempts while already
// running the kubelet, holding a valid long-lived token and registering a Node
// under this Machine's name. Nothing wipes hardware we own, so the quarantined
// host would keep working credentials through the quarantine.
func TestQuarantineRevokesTheNodeIdentityAndDropsTheStaleNode(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 7
	})
	host := rackHost("mini-01")
	// The host got far enough to register: a Node exists and an identity was minted.
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-0"}}
	sa := &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{
		Name: "tart-kubelet-ber1-0", Namespace: testNamespace,
	}}
	r := newRackReconciler(t, host, machine, node, sa)
	r.Power = registryWithShelly(&stubPowerDriver{on: true})
	ctx := context.Background()

	r.handleBootstrapFailure(ctx, machine, host, errors.New("install log shipper: boom"))

	if err := r.Get(ctx, types.NamespacedName{Name: "ber1-0"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Error("the half-registered Node survived quarantine")
	}
	if err := r.Get(ctx, types.NamespacedName{Namespace: testNamespace, Name: "tart-kubelet-ber1-0"}, &corev1.ServiceAccount{}); !apierrors.IsNotFound(err) {
		t.Error("the node identity survived quarantine; the quarantined host keeps working credentials")
	}
}
