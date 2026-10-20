package macos

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const borrowerNamespace = "tuist-staging"

// staticBorrowers is a BorrowerClients over fake clusters.
type staticBorrowers map[string]client.Client

func (s staticBorrowers) Borrower(_ context.Context, env string) (client.Client, string, error) {
	c, ok := s[env]
	if !ok {
		return nil, "", errors.New("no such borrower")
	}
	return c, borrowerNamespace, nil
}

func newBorrowerCluster(t *testing.T, objs ...runtime.Object) client.Client {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, infrav1.AddToScheme, rbacv1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}
	return fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackHostLease{}).
		Build()
}

// handOver records the runtime handovers a test triggers.
type handOver struct {
	calls []handOverCall
	err   error
}

type handOverCall struct {
	owner, key, ip, fingerprint string
}

func (h *handOver) fn(_ context.Context, cfg bootstrap.Config, owner, key string) (string, error) {
	h.calls = append(h.calls, handOverCall{owner: owner, key: key, ip: cfg.IP, fingerprint: cfg.KnownHostFingerprint})
	return cfg.KnownHostFingerprint, h.err
}

func leaseKey(t *testing.T) string {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub)))
}

func lendingHost(mutate ...func(*infrav1.RackHost)) *infrav1.RackHost {
	return rackHost("mini-01", append([]func(*infrav1.RackHost){func(h *infrav1.RackHost) {
		h.Spec.LendTo = "staging"
		h.Spec.SSHIngressAllowCIDRs = []string{"10.10.0.2/32", "10.10.0.3/32"}
		h.Spec.Machine = infrav1.RackHostMachine{HostCPU: 16, HostMemoryMB: 49152, GuestCapacity: 2}
	}}, mutate...)...)
}

func bootstrappedMachine(name string) *infrav1.RackAppleSiliconMachine {
	return rackMachine(name, func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.Conditions = clusterv1.Conditions{{
			Type:               BootstrappedCondition,
			Status:             corev1.ConditionTrue,
			LastTransitionTime: metav1.NewTime(time.Now().Add(-time.Hour)),
		}}
	})
}

func newLendingReconciler(t *testing.T, borrower client.Client, objs ...runtime.Object) (*RackAppleSiliconMachineReconciler, *handOver) {
	t.Helper()
	r := newRackReconciler(t, objs...)
	r.Env = "production"
	r.Borrowers = staticBorrowers{"staging": borrower}
	h := &handOver{}
	r.handOverRuntime = h.fn
	return r, h
}

func getLease(t *testing.T, c client.Client, name string) *infrav1.RackHostLease {
	t.Helper()
	lease := &infrav1.RackHostLease{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: borrowerNamespace, Name: name}, lease); err != nil {
		t.Fatalf("get lease %s: %v", name, err)
	}
	return lease
}

func setLeaseStatus(t *testing.T, c client.Client, name string, mutate func(*infrav1.RackHostLeaseStatus)) {
	t.Helper()
	lease := getLease(t, c, name)
	mutate(&lease.Status)
	if err := c.Status().Update(context.Background(), lease); err != nil {
		t.Fatal(err)
	}
}

func lend(t *testing.T, r *RackAppleSiliconMachineReconciler, machine *infrav1.RackAppleSiliconMachine) lendingGate {
	t.Helper()
	host := getHost(t, r, machine.Spec.Host)
	gate, err := r.reconcileLending(context.Background(), &osUpdateContext{
		machine: machine, host: host, sshKey: []byte("PRIVATE KEY"), sudoPassword: "hunter2", knownFingerprint: "SHA256:pinned",
	})
	if err != nil {
		t.Fatalf("reconcileLending: %v", err)
	}
	return gate
}

func runnerPodOn(name, node string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"},
		Spec:       corev1.PodSpec{NodeName: node},
		Status:     corev1.PodStatus{Phase: corev1.PodRunning},
	}
}

// Lending starts with an offer. Until the borrower accepts, the host keeps
// serving this env, and nothing is pushed to it: a host lent by hand before
// lendTo existed runs the borrower's runtime, which a drift push would pull
// back mid-job.
func TestLendOffersTheHostAndKeepsItUntilAccepted(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine,
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-0"}})

	gate := lend(t, r, machine)
	if gate.stop || !gate.skipDrift {
		t.Fatalf("gate = %+v, want the host to keep serving without drift pushes", gate)
	}
	if len(h.calls) != 0 {
		t.Fatalf("handed the runtime over before the borrower accepted: %+v", h.calls)
	}

	lease := getLease(t, borrower, "mini-01")
	if lease.Spec.Lender != "production" || lease.Spec.Phase != infrav1.LeaseOffered {
		t.Fatalf("lease spec = %+v, want an offer from production", lease.Spec)
	}
	got := lease.Spec.Host
	if got.Address != "192.168.0.41" || got.Serial != "C07FC05JQ6NY" || got.Site != "ber1" || got.SSHUser != "tuist" ||
		got.HostKeyFingerprint != "SHA256:pinned" || len(got.SSHIngressAllowCIDRs) != 2 {
		t.Fatalf("lease host = %+v", got)
	}
	if got.Machine.HostCPU != 16 || got.Machine.HostMemoryMB != 49152 || got.Machine.GuestCapacity != 2 {
		t.Fatalf("lease sizing = %+v, want the host's", got.Machine)
	}
	if lease.Spec.PreviousNodeName != "ber1-0" {
		t.Fatalf("previousNodeName = %q, want this env's name for the host", lease.Spec.PreviousNodeName)
	}
	if rec := getHost(t, r, "mini-01").Status.Lease; rec == nil || rec.Borrower != "staging" || rec.State != infrav1.LendingOffered {
		t.Fatalf("host lease record = %+v, want Offered to staging", rec)
	}
	node := &corev1.Node{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "ber1-0"}, node); err != nil || node.Spec.Unschedulable {
		t.Fatalf("the local Node was cordoned before the borrower accepted (err %v)", err)
	}
}

// A job running on the host finishes here before the runtime changes hands.
func TestLendDrainsTheLocalNodeBeforeHandingOver(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine,
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-0"}}, runnerPodOn("job-1", "ber1-0"))
	lend(t, r, machine)
	key := leaseKey(t)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseAccepted
		s.SSHPublicKey = key
	})

	gate := lend(t, r, machine)
	if !gate.stop {
		t.Fatalf("gate = %+v, want the reconcile to stop while draining", gate)
	}
	if len(h.calls) != 0 {
		t.Fatalf("handed over with a job still running: %+v", h.calls)
	}
	node := &corev1.Node{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "ber1-0"}, node); err != nil {
		t.Fatal(err)
	}
	if !node.Spec.Unschedulable || node.Annotations[LeaseCordonAnnotation] == "" {
		t.Fatalf("local Node not cordoned for the lease: %+v", node)
	}
	if rec := getHost(t, r, "mini-01").Status.Lease; rec.State != infrav1.LendingDraining {
		t.Fatalf("state = %s, want Draining", rec.State)
	}
}

// Once drained, the host's identity here is revoked and its Node deleted
// before the borrower's key is authorized, so it never runs both envs'
// runtimes; then the lease says Lent with the key it granted.
func TestLendHandsTheRuntimeOverOnceDrained(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine,
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-0"}},
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-ber1-0", Namespace: testNamespace}},
		&rbacv1.ClusterRoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-ber1-0"}})
	r = withEgress(r)
	lend(t, r, machine)
	key := leaseKey(t)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseAccepted
		s.SSHPublicKey = key
	})

	gate := lend(t, r, machine)
	if !gate.stop {
		t.Fatalf("gate = %+v, want a lent host left alone", gate)
	}
	if len(h.calls) != 1 || h.calls[0].owner != "staging" || h.calls[0].key != key {
		t.Fatalf("handovers = %+v, want one to staging with its key", h.calls)
	}
	if h.calls[0].ip != "rack-mini-01.tailscale-operator.svc.cluster.local" || h.calls[0].fingerprint != "SHA256:pinned" {
		t.Fatalf("handover dialled %+v, want the host's egress Service with its pinned key", h.calls[0])
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "ber1-0"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the local Node survived the handover (err %v)", err)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "tart-kubelet-ber1-0"}, &rbacv1.ClusterRoleBinding{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the local identity survived the handover (err %v)", err)
	}
	lease := getLease(t, borrower, "mini-01")
	if lease.Spec.Phase != infrav1.LeaseLent || lease.Spec.GrantedKeyFingerprint != leaseKeyFingerprint(key) {
		t.Fatalf("lease spec = %+v, want Lent with the granted key", lease.Spec)
	}
	rec := getHost(t, r, "mini-01").Status.Lease
	if rec.State != infrav1.LendingLent || rec.KeyFingerprint != leaseKeyFingerprint(key) {
		t.Fatalf("host lease record = %+v", rec)
	}

	// Lent: nothing more is pushed, and the next reconcile hands nothing over.
	if gate := lend(t, r, machine); !gate.stop {
		t.Fatalf("gate = %+v on a lent host", gate)
	}
	if len(h.calls) != 1 {
		t.Fatalf("handed over again with nothing changed: %+v", h.calls)
	}
}

// A key the borrower rotated is authorized before the borrower uses it.
func TestLentHostGetsTheBorrowersRotatedKey(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine)
	lend(t, r, machine)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseAccepted
		s.SSHPublicKey = leaseKey(t)
	})
	lend(t, r, machine)

	rotated := leaseKey(t)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseActive
		s.SSHPublicKey = rotated
	})
	lend(t, r, machine)

	if len(h.calls) != 2 || h.calls[1].owner != "staging" || h.calls[1].key != rotated {
		t.Fatalf("handovers = %+v, want the rotated key granted to staging", h.calls)
	}
	if got := getLease(t, borrower, "mini-01").Spec.GrantedKeyFingerprint; got != leaseKeyFingerprint(rotated) {
		t.Fatalf("granted fingerprint = %s, want the rotated key's", got)
	}
}

// Clearing lendTo asks the borrower to drain and release the host, and
// nothing changes on the host until it has.
func TestReturnWaitsForTheBorrowerToRelease(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine)
	lend(t, r, machine)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseAccepted
		s.SSHPublicKey = leaseKey(t)
	})
	lend(t, r, machine)
	returnHost(t, r, "mini-01")

	gate := lend(t, r, machine)
	if !gate.stop {
		t.Fatalf("gate = %+v, want the host left alone while the borrower drains it", gate)
	}
	if got := getLease(t, borrower, "mini-01").Spec.Phase; got != infrav1.LeaseReturning {
		t.Fatalf("lease phase = %s, want Returning", got)
	}
	if rec := getHost(t, r, "mini-01").Status.Lease; rec.State != infrav1.LendingReturning {
		t.Fatalf("state = %s, want Returning", rec.State)
	}
	if len(h.calls) != 1 {
		t.Fatalf("took the runtime back before the borrower released it: %+v", h.calls)
	}
}

// Once released, the runtime is taken back: the lease key goes, this env
// owns the runtime again, and bootstrap pushes it with a fresh tailnet login.
func TestReturnReclaimsTheRuntimeOnceReleased(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine)
	lend(t, r, machine)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseAccepted
		s.SSHPublicKey = leaseKey(t)
	})
	lend(t, r, machine)
	returnHost(t, r, "mini-01")
	lend(t, r, machine)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) { s.State = infrav1.LeaseReleased })

	gate := lend(t, r, machine)
	if gate.stop || !gate.forceReauth {
		t.Fatalf("gate = %+v, want bootstrap to run with a fresh tailnet login", gate)
	}
	if len(h.calls) != 2 || h.calls[1].owner != "production" || h.calls[1].key != "" {
		t.Fatalf("handovers = %+v, want the runtime back to production with no lease key", h.calls)
	}
	if conditions.IsTrue(machine, BootstrappedCondition) {
		t.Fatal("the reclaimed host is not bootstrapped again")
	}
	if rec := getHost(t, r, "mini-01").Status.Lease; rec == nil || rec.State != infrav1.LendingReclaimed {
		t.Fatalf("host lease record = %+v, want Reclaimed until bootstrap succeeds", rec)
	}
	if err := borrower.Get(context.Background(), types.NamespacedName{Namespace: borrowerNamespace, Name: "mini-01"}, &infrav1.RackHostLease{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the lease survived the return (err %v)", err)
	}

	r.finishReclaim(context.Background(), getHost(t, r, "mini-01"))
	if rec := getHost(t, r, "mini-01").Status.Lease; rec != nil {
		t.Fatalf("host lease record = %+v after the bootstrap, want none", rec)
	}
}

// A borrower that is gone cannot release the host, so a person can take it
// back without it: the annotation is the decision to end its jobs.
func TestForceReclaimSkipsTheBorrower(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, lendingHost(), machine)
	lend(t, r, machine)
	setLeaseStatus(t, borrower, "mini-01", func(s *infrav1.RackHostLeaseStatus) {
		s.State = infrav1.LeaseAccepted
		s.SSHPublicKey = leaseKey(t)
	})
	lend(t, r, machine)
	returnHost(t, r, "mini-01", func(h *infrav1.RackHost) {
		h.Annotations = map[string]string{ReclaimRuntimeAnnotation: "true"}
	})
	r.Borrowers = staticBorrowers{}

	lend(t, r, machine)
	gate := lend(t, r, machine)
	if gate.stop {
		t.Fatalf("gate = %+v, want the host reclaimed without the borrower", gate)
	}
	if len(h.calls) != 2 || h.calls[1].owner != "production" {
		t.Fatalf("handovers = %+v, want the runtime taken back", h.calls)
	}
}

// The lend survives a Machine made again (a parked and unparked host, a
// deleted Machine): the record is on the host, so the new Machine does not
// bootstrap this env's runtime over the borrower's.
func TestLendSurvivesANewMachine(t *testing.T) {
	borrower := newBorrowerCluster(t)
	host := lendingHost(func(h *infrav1.RackHost) {
		h.Status.Lease = &infrav1.RackHostLending{Borrower: "staging", State: infrav1.LendingLent}
	})
	machine := rackMachine("ber1-0")
	r, h := newLendingReconciler(t, borrower, host, machine)

	if gate := lend(t, r, machine); !gate.stop {
		t.Fatalf("gate = %+v, want a fresh Machine of a lent host to leave it alone", gate)
	}
	if len(h.calls) != 0 {
		t.Fatalf("handovers = %+v", h.calls)
	}
	if !machine.Status.Ready || machine.Status.Phase != "Lent" {
		t.Fatalf("machine status = %+v, want Ready and Lent", machine.Status)
	}
}

// A borrower this operator cannot reach yet changes nothing: the host keeps
// serving here.
func TestUnreachableBorrowerLeavesTheHostServing(t *testing.T) {
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, nil, lendingHost(), machine)
	r.Borrowers = staticBorrowers{}

	gate := lend(t, r, machine)
	if gate.stop {
		t.Fatalf("gate = %+v, want the host to keep serving", gate)
	}
	if len(h.calls) != 0 || getHost(t, r, "mini-01").Status.Lease != nil {
		t.Fatal("an unreachable borrower started a lend")
	}
}

// The manual lend and lendTo are exclusive; a host with both is left on the
// manual one.
func TestManualLendWinsOverLendTo(t *testing.T) {
	borrower := newBorrowerCluster(t)
	machine := bootstrappedMachine("ber1-0")
	machine.Spec.NodeCluster = &infrav1.RackHostNodeCluster{KubeconfigSecret: "x"}
	r, _ := newLendingReconciler(t, borrower, lendingHost(), machine)

	if gate := lend(t, r, machine); gate.stop || gate.skipDrift {
		t.Fatalf("gate = %+v, want the manual lend left as it is", gate)
	}
	if err := borrower.Get(context.Background(), types.NamespacedName{Namespace: borrowerNamespace, Name: "mini-01"}, &infrav1.RackHostLease{}); !apierrors.IsNotFound(err) {
		t.Fatalf("offered a manually lent host (err %v)", err)
	}
}

// The fleet's MachineHealthCheck stays off the Machine for as long as the
// host's Node is in another cluster.
func TestLendToKeepsTheMachineOffRemediation(t *testing.T) {
	meta := &metav1.ObjectMeta{}
	keepLentMachineOffRemediation(meta, lendingHost())
	if _, set := meta.Annotations[clusterv1.MachineSkipRemediationAnnotation]; !set {
		t.Fatal("a host with lendTo is remediated by this cluster's health check")
	}
	returning := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Status.Lease = &infrav1.RackHostLending{Borrower: "staging", State: infrav1.LendingReturning}
	})
	keepLentMachineOffRemediation(meta, returning)
	if _, set := meta.Annotations[clusterv1.MachineSkipRemediationAnnotation]; !set {
		t.Fatal("a host on its way back is remediated before its Node is here")
	}
	keepLentMachineOffRemediation(meta, rackHost("mini-01"))
	if _, set := meta.Annotations[clusterv1.MachineSkipRemediationAnnotation]; set {
		t.Fatal("a returned host stays off remediation")
	}
}

func returnHost(t *testing.T, r *RackAppleSiliconMachineReconciler, name string, mutate ...func(*infrav1.RackHost)) {
	t.Helper()
	host := getHost(t, r, name)
	host.Spec.LendTo = ""
	for _, m := range mutate {
		m(host)
	}
	if err := r.Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
}

// A bootstrap the fence refused means another env runs the host, maybe with
// jobs on it: that is never a host to power-cycle or quarantine.
func TestBootstrapRefusedByTheFenceIsNotEscalated(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 7
	})
	host := rackHost("mini-01")
	r := newRackReconciler(t, host, machine)
	driver := &stubPowerDriver{on: true}
	r.Power = registryWithShelly(driver)

	r.handleBootstrapFailure(context.Background(), machine, host, &bootstrap.RuntimeOwnerError{Expected: "production", Owner: "staging"})

	if got := driver.recorded(); len(got) != 0 {
		t.Fatalf("outlet calls = %v for a host another env runs", got)
	}
	if getHost(t, r, "mini-01").Status.Quarantined {
		t.Fatal("quarantined a host another env runs")
	}
	if got := conditions.GetReason(machine, BootstrappedCondition); got != "RuntimeOwnedElsewhere" {
		t.Fatalf("reason = %q, want RuntimeOwnedElsewhere", got)
	}
}

// A host another env still owns, with no lend on record here (its RackHost was
// made again), is taken back only on the reclaim annotation.
func TestReclaimAnnotationTakesBackAHostOwnedElsewhere(t *testing.T) {
	machine := rackMachine("ber1-0")
	conditions.MarkFalse(machine, BootstrappedCondition, "RuntimeOwnedElsewhere", clusterv1.ConditionSeverityWarning, "staging")
	r, h := newLendingReconciler(t, newBorrowerCluster(t), rackHost("mini-01"), machine)

	if gate := lend(t, r, machine); gate.forceReauth || len(h.calls) != 0 {
		t.Fatalf("gate = %+v, handovers = %+v without the annotation", gate, h.calls)
	}

	host := getHost(t, r, "mini-01")
	host.Annotations = map[string]string{ReclaimRuntimeAnnotation: "true"}
	if err := r.Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
	gate := lend(t, r, machine)
	if !gate.forceReauth || len(h.calls) != 1 || h.calls[0].owner != "production" || h.calls[0].key != "" {
		t.Fatalf("gate = %+v, handovers = %+v, want the runtime taken back", gate, h.calls)
	}
}

// lentHost is a host lent to staging, with the lease it was lent under.
func lentHost(t *testing.T) (*RackAppleSiliconMachineReconciler, client.Client, *infrav1.RackAppleSiliconMachine) {
	t.Helper()
	borrower := newBorrowerCluster(t)
	host := lendingHost(func(h *infrav1.RackHost) {
		h.Status.Lease = &infrav1.RackHostLending{Borrower: "staging", State: infrav1.LendingLent}
	})
	machine := bootstrappedMachine("ber1-0")
	r, _ := newLendingReconciler(t, borrower, host, machine)
	lend(t, r, machine)
	return r, borrower, machine
}

func askSite(t *testing.T, c client.Client, req infrav1.RackHostLeaseSiteRequest) {
	t.Helper()
	setLeaseStatus(t, c, "mini-01", func(s *infrav1.RackHostLeaseStatus) { s.SiteRequest = &req })
}

func siteResult(t *testing.T, c client.Client) *infrav1.RackHostLeaseSiteResult {
	t.Helper()
	return getLease(t, c, "mini-01").Spec.SiteRequestResult
}

// The borrower cannot reach the PDU; the lender cycles the outlet for it,
// once per request.
func TestLentHostIsPowerCycledOnTheBorrowersRequest(t *testing.T) {
	r, borrower, machine := lentHost(t)
	driver := &stubPowerDriver{on: true}
	r.Power = registryWithShelly(driver)
	askSite(t, borrower, infrav1.RackHostLeaseSiteRequest{ID: "r1", Action: infrav1.SiteRequestPowerCycle})

	lend(t, r, machine)
	if got := driver.recorded(); len(got) != 2 || got[0] != "set=false" || got[1] != "set=true" {
		t.Fatalf("outlet calls = %v, want an off then an on", got)
	}
	res := siteResult(t, borrower)
	if res == nil || res.ID != "r1" || res.Phase != infrav1.SiteRequestSucceeded || !res.ReturnToService {
		t.Fatalf("result = %+v, want r1 Succeeded", res)
	}

	lend(t, r, machine)
	if got := driver.recorded(); len(got) != 2 {
		t.Fatalf("cycled again for an answered request: %v", got)
	}
}

// An update waits for the borrower to drain its Node; then it runs through the
// lender's own update flow, which reports back to the lease, and ends once the
// host restarted on the target with its console session. Converging the
// runtime is the borrower's.
func TestLentHostIsUpdatedOnTheBorrowersRequest(t *testing.T) {
	r, borrower, machine := lentHost(t)
	fake := newFakeOSUpdateHost()
	r.osUpdateDial = func(string, string, []byte, string) (osUpdateHost, error) { return fake, nil }
	askSite(t, borrower, infrav1.RackHostLeaseSiteRequest{ID: "r1", Action: infrav1.SiteRequestOSUpdate, Target: "26.7"})

	lend(t, r, machine)
	if res := siteResult(t, borrower); res == nil || res.Phase != infrav1.SiteRequestRunning || machine.Status.OSUpdate != nil {
		t.Fatalf("result = %+v, update = %+v; want it waiting for the drain", res, machine.Status.OSUpdate)
	}

	askSite(t, borrower, infrav1.RackHostLeaseSiteRequest{ID: "r1", Action: infrav1.SiteRequestOSUpdate, Target: "26.7", Drained: true})
	for range 3 {
		lend(t, r, machine)
	}
	if len(fake.downloads) != 1 {
		t.Fatalf("downloads = %v, want the update downloading", fake.downloads)
	}
	if res := siteResult(t, borrower); res.Phase != infrav1.SiteRequestRunning || res.OSUpdateID == "" || res.OSUpdateID != machine.Status.OSUpdate.ID {
		t.Fatalf("result = %+v, want it tied to the running update", res)
	}

	fake.exit(bootstrap.OSUpdateJobDownload, 0, "")
	for range 3 {
		lend(t, r, machine)
	}
	if len(fake.installs) != 1 {
		t.Fatalf("installs = %v", fake.installs)
	}
	fake.bootTime, fake.version = 200, "26.7"
	lend(t, r, machine)
	res := siteResult(t, borrower)
	if res.Phase != infrav1.SiteRequestSucceeded || !res.ReturnToService {
		t.Fatalf("result = %+v, want Succeeded", res)
	}
	if _, set := machine.Annotations[OSUpdateAnnotation]; set {
		t.Fatal("the update's annotation outlived it")
	}
}

// An update that fails before it changed the host hands the Node back; the
// borrower learns which.
func TestLentHostUpdateNotOfferedReturnsTheNode(t *testing.T) {
	r, borrower, machine := lentHost(t)
	fake := newFakeOSUpdateHost()
	r.osUpdateDial = func(string, string, []byte, string) (osUpdateHost, error) { return fake, nil }
	askSite(t, borrower, infrav1.RackHostLeaseSiteRequest{ID: "r1", Action: infrav1.SiteRequestOSUpdate, Target: "26.9", Drained: true})

	lend(t, r, machine)
	lend(t, r, machine)
	res := siteResult(t, borrower)
	if res.Phase != infrav1.SiteRequestFailed || !res.ReturnToService || !strings.Contains(res.Message, "NotOffered") {
		t.Fatalf("result = %+v, want a NotOffered failure that returns the Node", res)
	}
}

// A borrowing cluster that cannot take a lease yet (not deployed with the
// RackHostLease kind, or its rack-lender identity not bound) leaves the host
// as it is: lending ships with the deploys of every env at once, and each
// takes it up when it can.
func TestLendWaitsForABorrowerThatCannotTakeALease(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	notReady := fake.NewClientBuilder().WithScheme(scheme).Build()
	machine := bootstrappedMachine("ber1-0")
	r, h := newLendingReconciler(t, notReady, lendingHost(), machine)

	gate := lend(t, r, machine)
	if gate.stop || !gate.skipDrift {
		t.Fatalf("gate = %+v, want the host kept as it is", gate)
	}
	if len(h.calls) != 0 {
		t.Fatalf("handovers = %+v", h.calls)
	}
}
