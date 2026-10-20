package macos

import (
	"context"
	"errors"
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
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	borrowerFleet = "tuist-staging-rack-fleet"
	borrowedNode  = borrowerFleet + "-mini-01"
)

// pushes records the runtime pushes the borrower makes.
type pushes struct {
	configs []bootstrap.Config
	err     error
}

func (p *pushes) fn(_ context.Context, cfg bootstrap.Config) (string, error) {
	p.configs = append(p.configs, cfg)
	return cfg.KnownHostFingerprint, p.err
}

func offeredLease(mutate ...func(*infrav1.RackHostLease)) *infrav1.RackHostLease {
	l := &infrav1.RackHostLease{
		ObjectMeta: metav1.ObjectMeta{Name: "mini-01", Namespace: testNamespace},
		Spec: infrav1.RackHostLeaseSpec{
			Lender: "production",
			Phase:  infrav1.LeaseOffered,
			Host: infrav1.RackHostLeaseHost{
				Serial:               "C07FC05JQ6NY",
				Address:              "10.10.0.101",
				SSHUser:              "tuist",
				SSHIngressAllowCIDRs: []string{"10.10.0.2/32", "10.10.0.3/32"},
				Site:                 "ber1",
				HostKeyFingerprint:   "SHA256:pinned",
				Machine:              infrav1.RackHostMachine{HostCPU: 16, HostMemoryMB: 49152, GuestCapacity: 2, MaxPods: 5, RunnerCacheVolumeGiB: ptr.To(400)},
			},
			PreviousNodeName: "tuist-tuist-rack-fleet-mini-01",
		},
	}
	for _, m := range mutate {
		m(l)
	}
	return l
}

// tokenSecret is what the service-account-token controller fills in for the
// node identity the borrower mints.
func tokenSecret(node string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-" + node + "-token", Namespace: testNamespace},
		Data:       map[string][]byte{"token": []byte("node-token"), "ca.crt": []byte("ca")},
	}
}

func tailscaleSecret() *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "tailscale", Namespace: testNamespace},
		Data:       map[string][]byte{"auth-key": []byte("tskey-client-staging")},
	}
}

func newLeaseReconciler(t *testing.T, objs ...runtime.Object) (*RackHostLeaseReconciler, *pushes) {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, infrav1.AddToScheme, rbacv1.AddToScheme, clusterv1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackHostLease{}).
		Build()
	p := &pushes{}
	return &RackHostLeaseReconciler{
		Client:   c,
		Recorder: fakeRecorder(),
		CredentialsManager: &credentials.Manager{
			Client: c, Namespace: testNamespace,
			NodeIdentityClusterRole: "tuist-tart-kubelet", TailscaleAuthKeySecretName: "tailscale",
		},
		Kubeconfig: &kubeconfig.Builder{APIServerURL: "https://kube-staging.example"},
		Env:        "staging",
		FleetName:  borrowerFleet,
		Hosts:      []string{"mini-01"},
		FleetConfig: bootstrap.Config{
			TailscaleTags:  []string{"tag:tuist-macmini-staging"},
			CustomCacheURL: "https://staging.tuist.dev/api/internal/runners/cache-volumes",
			TartVersion:    "2.41.1",
			HostCPU:        8,
		},
		TartKubeletBinarySHA:         "staging-sha",
		TartKubeletMaxUpdateAttempts: 5,
		pushRuntime:                  p.fn,
	}, p
}

func reconcileLease(t *testing.T, r *RackHostLeaseReconciler) *infrav1.RackHostLease {
	t.Helper()
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	lease := &infrav1.RackHostLease{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}, lease); err != nil {
		t.Fatalf("get lease: %v", err)
	}
	return lease
}

// grant does what the lender does once it authorized the borrower's key.
func grant(t *testing.T, r *RackHostLeaseReconciler, lease *infrav1.RackHostLease) {
	t.Helper()
	lease.Spec.Phase = infrav1.LeaseLent
	lease.Spec.GrantedKeyFingerprint = leaseKeyFingerprint(lease.Status.SSHPublicKey)
	if err := r.Update(context.Background(), lease); err != nil {
		t.Fatal(err)
	}
}

// A host this env did not ask for is refused, and nothing is minted for it.
func TestBorrowerRefusesAHostItDidNotDeclare(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease())
	r.Hosts = []string{"mini-02"}

	lease := reconcileLease(t, r)
	if lease.Status.State != infrav1.LeaseRefused || lease.Status.SSHPublicKey != "" {
		t.Fatalf("status = %+v, want Refused with no key", lease.Status)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: leaseKeySecretName("mini-01")}, &corev1.Secret{}); !apierrors.IsNotFound(err) {
		t.Fatalf("minted a key for a refused host (err %v)", err)
	}
	if len(p.configs) != 0 {
		t.Fatal("pushed to a refused host")
	}
}

// An offer is answered with the key this env will dial with. The private half
// stays in this cluster; the lender only ever sees the public one.
func TestBorrowerAcceptsAnOfferWithItsKey(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease())

	lease := reconcileLease(t, r)
	if lease.Status.State != infrav1.LeaseAccepted {
		t.Fatalf("state = %s, want Accepted", lease.Status.State)
	}
	if leaseKeyFingerprint(lease.Status.SSHPublicKey) == "" {
		t.Fatalf("published key %q is not an authorized_keys line", lease.Status.SSHPublicKey)
	}
	secret := &corev1.Secret{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: leaseKeySecretName("mini-01")}, secret); err != nil {
		t.Fatalf("key Secret: %v", err)
	}
	if len(secret.Data["id_ed25519"]) == 0 {
		t.Fatal("the key Secret has no private key")
	}
	if lease.Status.Node != borrowedNode {
		t.Fatalf("node = %q, want %q", lease.Status.Node, borrowedNode)
	}
	if len(p.configs) != 0 {
		t.Fatal("pushed to a host only offered")
	}

	again := reconcileLease(t, r)
	if again.Status.SSHPublicKey != lease.Status.SSHPublicKey {
		t.Fatal("the key changed between reconciles")
	}
}

// Lent with a key the lender has not authorized yet (a rotation in flight):
// the borrower waits rather than dialling with a key the host refuses.
func TestBorrowerWaitsForItsKeyToBeGranted(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease())
	lease := reconcileLease(t, r)
	lease.Spec.Phase = infrav1.LeaseLent
	lease.Spec.GrantedKeyFingerprint = "SHA256:someone-elses"
	if err := r.Update(context.Background(), lease); err != nil {
		t.Fatal(err)
	}

	lease = reconcileLease(t, r)
	if len(p.configs) != 0 {
		t.Fatal("pushed with a key the host does not accept")
	}
	if lease.Status.State != infrav1.LeaseAccepted {
		t.Fatalf("state = %s, want Accepted while the grant is pending", lease.Status.State)
	}
}

// Taking the host over is a push of this env's runtime: its tart-kubelet,
// node identity, fleet label, cache-volume server and tailnet tags, with a
// fresh tailnet login, under this env's runtime ownership, to the host key
// the lender pinned.
func TestBorrowerTakesTheHostOverWithItsOwnRuntime(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))

	lease := reconcileLease(t, r)
	if len(p.configs) != 1 {
		t.Fatalf("pushes = %d, want 1", len(p.configs))
	}
	cfg := p.configs[0]
	if cfg.RuntimeOwner != "staging" || !cfg.TailscaleForceReauth {
		t.Fatalf("owner = %q, forceReauth = %v; want staging with a fresh tailnet login", cfg.RuntimeOwner, cfg.TailscaleForceReauth)
	}
	if cfg.NodeName != borrowedNode || cfg.NodeLabels["tuist.dev/fleet"] != borrowerFleet {
		t.Fatalf("node %q labels %v, want this env's", cfg.NodeName, cfg.NodeLabels)
	}
	if cfg.KnownHostFingerprint != "SHA256:pinned" || cfg.SSHUser != "tuist" || cfg.IP != "10.10.0.101" {
		t.Fatalf("dial = %s@%s pinned %q", cfg.SSHUser, cfg.IP, cfg.KnownHostFingerprint)
	}
	if cfg.CustomCacheURL != "https://staging.tuist.dev/api/internal/runners/cache-volumes" || cfg.TartVersion != "2.41.1" {
		t.Fatalf("runtime = cache %q tart %q, want this env's", cfg.CustomCacheURL, cfg.TartVersion)
	}
	if cfg.HostCPU != 16 || cfg.HostMemoryMB != 49152 || cfg.MaxPods != 5 || cfg.RunnerCacheVolumeGiB != 400 || cfg.VNCRelayPortCount != 2 {
		t.Fatalf("sizing = cpu %d mem %d pods %d cache %d guests %d, want the lease's", cfg.HostCPU, cfg.HostMemoryMB, cfg.MaxPods, cfg.RunnerCacheVolumeGiB, cfg.VNCRelayPortCount)
	}
	if !cfg.TailscalePersistentDevice || len(cfg.SSHIngressAllowCIDRs) != 2 {
		t.Fatalf("rack overlay missing: persistent %v ingress %v", cfg.TailscalePersistentDevice, cfg.SSHIngressAllowCIDRs)
	}
	if cfg.TailscaleAuthKey != "tskey-client-staging" || cfg.Kubeconfig == "" || cfg.ProviderID != "rack-applesilicon://ber1/C07FC05JQ6NY" {
		t.Fatalf("identity = key %q kubeconfig %d bytes providerID %q", cfg.TailscaleAuthKey, len(cfg.Kubeconfig), cfg.ProviderID)
	}
	if lease.Status.State != infrav1.LeaseActive || !conditions.IsTrue(lease, BootstrappedCondition) {
		t.Fatalf("status = %+v, want Active and Bootstrapped", lease.Status)
	}
	if lease.Status.HostConfigHash == "" || lease.Status.TartKubeletBinarySHA != "staging-sha" {
		t.Fatalf("drift bookkeeping = %+v", lease.Status.HostAgentStatus)
	}

	// Converged: nothing more is pushed.
	reconcileLease(t, r)
	if len(p.configs) != 1 {
		t.Fatalf("pushed again with nothing changed: %d", len(p.configs))
	}
}

// A change to this env's runtime (its deploy) reaches the borrowed host
// through the drift loop, without logging it into the tailnet again.
func TestBorrowerRollsItsDeployToTheHost(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))
	before := reconcileLease(t, r).Status.HostConfigHash

	r.FleetConfig.TartVersion = "2.42.0"
	lease := reconcileLease(t, r)
	if len(p.configs) != 2 {
		t.Fatalf("pushes = %d, want the deploy rolled", len(p.configs))
	}
	if cfg := p.configs[1]; cfg.TailscaleForceReauth || cfg.TartVersion != "2.42.0" || cfg.RuntimeOwner != "staging" {
		t.Fatalf("drift push = reauth %v tart %q owner %q", cfg.TailscaleForceReauth, cfg.TartVersion, cfg.RuntimeOwner)
	}
	if lease.Status.HostConfigHash == before {
		t.Fatal("the stamped hash did not move with the deploy")
	}
}

// A push the fence refuses means the lender has not handed the runtime over;
// it counts as a failed attempt and does not take the host.
func TestBorrowerRetriesAPushTheFenceRefused(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))
	p.err = &bootstrap.RuntimeOwnerError{Expected: "staging", Owner: "production"}

	lease := reconcileLease(t, r)
	if conditions.IsTrue(lease, BootstrappedCondition) || lease.Status.State == infrav1.LeaseActive {
		t.Fatalf("status = %+v after a refused push", lease.Status)
	}
	if got := conditions.GetReason(lease, BootstrappedCondition); got != "RuntimeOwnedElsewhere" {
		t.Fatalf("reason = %q, want RuntimeOwnedElsewhere", got)
	}
}

// A host lent by hand registered under the lender's name. Its jobs finish
// before this env takes the host over, and that Node goes once it has.
func TestBorrowerDrainsThePreviousNodeFirst(t *testing.T) {
	previous := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "tuist-tuist-rack-fleet-mini-01"}}
	job := runnerPodOn("job-1", "tuist-tuist-rack-fleet-mini-01")
	r, p := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret(), previous, job)
	grant(t, r, reconcileLease(t, r))

	reconcileLease(t, r)
	if len(p.configs) != 0 {
		t.Fatal("took the host over with a job still running on its previous Node")
	}
	node := &corev1.Node{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: previous.Name}, node); err != nil || !node.Spec.Unschedulable {
		t.Fatalf("previous Node not cordoned (err %v)", err)
	}

	if err := r.Delete(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	reconcileLease(t, r)
	if len(p.configs) != 1 {
		t.Fatalf("pushes = %d after the job finished, want 1", len(p.configs))
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: previous.Name}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the previous Node survived the takeover (err %v)", err)
	}
}

// Returning the host: this env's jobs finish, then its Node, identity and
// pushes go, and the lender may take the runtime back.
func TestBorrowerReleasesTheHostOnReturn(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))
	lease := reconcileLease(t, r)
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: borrowedNode}}
	job := runnerPodOn("job-1", borrowedNode)
	for _, obj := range []client.Object{node, job} {
		if err := r.Create(context.Background(), obj); err != nil {
			t.Fatal(err)
		}
	}
	lease.Spec.Phase = infrav1.LeaseReturning
	if err := r.Update(context.Background(), lease); err != nil {
		t.Fatal(err)
	}

	lease = reconcileLease(t, r)
	if lease.Status.State != infrav1.LeaseDraining {
		t.Fatalf("state = %s with a job running, want Draining", lease.Status.State)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: borrowedNode}, node); err != nil || !node.Spec.Unschedulable {
		t.Fatalf("Node not cordoned on return (err %v)", err)
	}

	if err := r.Delete(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	lease = reconcileLease(t, r)
	if lease.Status.State != infrav1.LeaseReleased {
		t.Fatalf("state = %s, want Released", lease.Status.State)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: borrowedNode}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the Node survived the release (err %v)", err)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "tart-kubelet-" + borrowedNode}, &rbacv1.ClusterRoleBinding{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the node identity survived the release (err %v)", err)
	}
	if conditions.IsTrue(lease, BootstrappedCondition) {
		t.Fatal("a released host still reads as bootstrapped; lending it again would skip the takeover")
	}
	if len(p.configs) != 1 {
		t.Fatalf("pushed during the return: %d", len(p.configs))
	}
}

// Deleting the lease (the lender's return, or a forced reclaim) leaves nothing
// of this env's behind: the key, the identity and the Node.
func TestBorrowerCleansUpADeletedLease(t *testing.T) {
	r, _ := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))
	reconcileLease(t, r)
	if err := r.Create(context.Background(), &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: borrowedNode}}); err != nil {
		t.Fatal(err)
	}

	lease := &infrav1.RackHostLease{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}, lease); err != nil {
		t.Fatal(err)
	}
	if err := r.Delete(context.Background(), lease); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	for name, obj := range map[string]client.Object{
		"lease":    &infrav1.RackHostLease{ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: "mini-01"}},
		"key":      &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: testNamespace, Name: leaseKeySecretName("mini-01")}},
		"node":     &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: borrowedNode}},
		"identity": &rbacv1.ClusterRoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-" + borrowedNode}},
	} {
		err := r.Get(context.Background(), types.NamespacedName{Namespace: obj.GetNamespace(), Name: obj.GetName()}, obj)
		if !apierrors.IsNotFound(err) {
			t.Errorf("the %s survived the lease (err %v)", name, err)
		}
	}
}

// A host taken off this env's list while lent is drained and released, which
// tells the lender it can have it back.
func TestBorrowerReleasesAHostItStoppedDeclaring(t *testing.T) {
	r, _ := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))
	reconcileLease(t, r)
	r.Hosts = nil

	if lease := reconcileLease(t, r); lease.Status.State != infrav1.LeaseReleased {
		t.Fatalf("state = %s, want Released", lease.Status.State)
	}
}

func TestBorrowerReportsItsNodesReadiness(t *testing.T) {
	r, _ := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret(), &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: borrowedNode},
		Status:     corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue, LastHeartbeatTime: metav1.NewTime(time.Now())}}},
	})
	grant(t, r, reconcileLease(t, r))
	if lease := reconcileLease(t, r); !lease.Status.NodeReady {
		t.Fatal("nodeReady = false with a Ready Node")
	}
}

var errUnreachable = errors.New("dial tcp: i/o timeout")

// A push that cannot reach the host keeps the lease as it is and retries.
func TestBorrowerRetriesAnUnreachableHost(t *testing.T) {
	r, p := newLeaseReconciler(t, offeredLease(), tokenSecret(borrowedNode), tailscaleSecret())
	grant(t, r, reconcileLease(t, r))
	p.err = errUnreachable

	lease := reconcileLease(t, r)
	if lease.Status.State == infrav1.LeaseActive || lease.Status.BootstrapAttempts != 1 {
		t.Fatalf("status = %+v, want one failed takeover", lease.Status)
	}
	p.err = nil
	if lease := reconcileLease(t, r); lease.Status.State != infrav1.LeaseActive {
		t.Fatalf("state = %s after the host came back, want Active", lease.Status.State)
	}
}

// activeLease is a lease this env took the host over under, with its Node.
func activeLease(t *testing.T, objs ...runtime.Object) (*RackHostLeaseReconciler, *pushes) {
	t.Helper()
	r, p := newLeaseReconciler(t, append([]runtime.Object{
		offeredLease(), tokenSecret(borrowedNode), tailscaleSecret(),
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: borrowedNode}},
	}, objs...)...)
	grant(t, r, reconcileLease(t, r))
	if lease := reconcileLease(t, r); lease.Status.State != infrav1.LeaseActive {
		t.Fatalf("state = %s, want Active", lease.Status.State)
	}
	return r, p
}

func annotateLease(t *testing.T, r *RackHostLeaseReconciler, key, value string) {
	t.Helper()
	lease := &infrav1.RackHostLease{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}, lease); err != nil {
		t.Fatal(err)
	}
	metav1.SetMetaDataAnnotation(&lease.ObjectMeta, key, value)
	if err := r.Update(context.Background(), lease); err != nil {
		t.Fatal(err)
	}
}

// answer does what the lender does when it has served the request.
func answer(t *testing.T, r *RackHostLeaseReconciler, res infrav1.RackHostLeaseSiteResult) {
	t.Helper()
	lease := &infrav1.RackHostLease{}
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "mini-01"}, lease); err != nil {
		t.Fatal(err)
	}
	if res.ID == "" {
		res.ID = lease.Status.SiteRequest.ID
	}
	lease.Spec.SiteRequestResult = &res
	if err := r.Update(context.Background(), lease); err != nil {
		t.Fatal(err)
	}
}

func borrowedNodeCordoned(t *testing.T, r *RackHostLeaseReconciler) bool {
	t.Helper()
	node := &corev1.Node{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: borrowedNode}, node); err != nil {
		t.Fatal(err)
	}
	return node.Spec.Unschedulable
}

// A wedged host is the lender's to power-cycle: the borrower asks, holds its
// pushes while the lender acts, and closes the request on the answer.
func TestBorrowerAsksTheLenderForAPowerCycle(t *testing.T) {
	r, p := activeLease(t)
	annotateLease(t, r, PowerCycleAnnotation, "wedged")

	lease := reconcileLease(t, r)
	req := lease.Status.SiteRequest
	if req == nil || req.Action != infrav1.SiteRequestPowerCycle || req.ID == "" {
		t.Fatalf("site request = %+v, want a PowerCycle", req)
	}
	r.FleetConfig.TartVersion = "2.42.0"
	reconcileLease(t, r)
	if len(p.configs) != 1 {
		t.Fatal("pushed while the lender was cycling the host")
	}

	answer(t, r, infrav1.RackHostLeaseSiteResult{Phase: infrav1.SiteRequestSucceeded, ReturnToService: true})
	lease = reconcileLease(t, r)
	if lease.Status.SiteRequest != nil {
		t.Fatalf("request %+v outlived its answer", lease.Status.SiteRequest)
	}
	if _, set := lease.Annotations[PowerCycleAnnotation]; set {
		t.Fatal("the annotation outlived the request, which would ask again")
	}
	if len(p.configs) != 2 {
		t.Fatal("the drift held back during the request did not roll after it")
	}
}

// An update drains this env's jobs before the lender may start it, and the
// runtime is pushed again after it, since the installer resets files the host
// config owns.
func TestBorrowerDrainsForAnUpdateAndPushesAfterIt(t *testing.T) {
	job := runnerPodOn("job-1", borrowedNode)
	r, p := activeLease(t, job)
	annotateLease(t, r, OSUpdateAnnotation, "26.7")

	lease := reconcileLease(t, r)
	req := lease.Status.SiteRequest
	if req == nil || req.Action != infrav1.SiteRequestOSUpdate || req.Target != "26.7" || req.Drained {
		t.Fatalf("site request = %+v, want an undrained OSUpdate to 26.7", req)
	}
	if !borrowedNodeCordoned(t, r) {
		t.Fatal("the Node was not cordoned for the update")
	}

	if err := r.Delete(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	if lease := reconcileLease(t, r); !lease.Status.SiteRequest.Drained {
		t.Fatal("not drained with no job left")
	}

	answer(t, r, infrav1.RackHostLeaseSiteResult{Phase: infrav1.SiteRequestSucceeded, ReturnToService: true})
	lease = reconcileLease(t, r)
	if len(p.configs) != 2 {
		t.Fatalf("pushes = %d, want the runtime pushed again after the update", len(p.configs))
	}
	if borrowedNodeCordoned(t, r) || lease.Status.SiteRequest != nil {
		t.Fatalf("after the update: cordoned=%v request=%+v", borrowedNodeCordoned(t, r), lease.Status.SiteRequest)
	}
	if _, set := lease.Annotations[OSUpdateAnnotation]; set {
		t.Fatal("the annotation outlived the update")
	}
}

// An update that failed after it changed the host leaves the Node cordoned,
// as the lender's own update does.
func TestBorrowerKeepsTheNodeCordonedAfterAFailedUpdate(t *testing.T) {
	r, _ := activeLease(t)
	annotateLease(t, r, OSUpdateAnnotation, "26.7")
	reconcileLease(t, r)
	reconcileLease(t, r)

	answer(t, r, infrav1.RackHostLeaseSiteResult{Phase: infrav1.SiteRequestFailed, Message: "VersionMismatch"})
	lease := reconcileLease(t, r)
	if !borrowedNodeCordoned(t, r) {
		t.Fatal("uncordoned a host the failed update changed")
	}
	if lease.Status.SiteRequest != nil {
		t.Fatal("the failed request stayed open")
	}
}

// A reinstall wipes what the lender's handover put on the host; it is the
// lender's, after the host is returned.
func TestBorrowerRefusesToAskForAReinstall(t *testing.T) {
	r, _ := activeLease(t)
	annotateLease(t, r, OSReinstallAnnotation, "27.0")

	lease := reconcileLease(t, r)
	if lease.Status.SiteRequest != nil {
		t.Fatalf("asked for a reinstall: %+v", lease.Status.SiteRequest)
	}
	if _, set := lease.Annotations[OSReinstallAnnotation]; set {
		t.Fatal("the refused annotation was left in place")
	}
}
