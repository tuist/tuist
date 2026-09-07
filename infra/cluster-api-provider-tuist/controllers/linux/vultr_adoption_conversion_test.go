package linux

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/vultr"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

func vultrScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatalf("add infrav1 to scheme: %v", err)
	}
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add corev1 to scheme: %v", err)
	}
	// The release path deletes the node identity, which is RBAC objects.
	if err := rbacv1.AddToScheme(scheme); err != nil {
		t.Fatalf("add rbacv1 to scheme: %v", err)
	}
	return scheme
}

func vultrMachine(ns, name, instanceID string) *infrav1.VultrMachine {
	m := &infrav1.VultrMachine{
		ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: name, UID: types.UID(name)},
	}
	m.Status.InstanceID = instanceID
	return m
}

// Same double-claim hazard as the OVH kind: a claim is only durable once its
// status patch lands, and the informer cache lags that write, so a sibling
// reading through the cache sees a claimed box as free and adopts it too.
func TestVultrClaimedInstanceIDsReadsUncached(t *testing.T) {
	const ns = "tuist"
	scheme := vultrScheme(t)
	self := vultrMachine(ns, "adopter", "")
	sibling := vultrMachine(ns, "sibling", "c65882db-b264-48ec-af5e-b5b44b584c54")

	cached := fake.NewClientBuilder().WithScheme(scheme).WithObjects(self).Build()
	live := fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, sibling).Build()

	r := &VultrMachineReconciler{Client: cached, APIReader: live}
	claimed, err := r.claimedInstanceIDs(context.Background(), self)
	if err != nil {
		t.Fatalf("claimedInstanceIDs: %v", err)
	}
	if !claimed["c65882db-b264-48ec-af5e-b5b44b584c54"] {
		t.Fatalf("claimed = %v, want the sibling's claim; a cached read double-claims the box", claimed)
	}
}

func TestVultrClaimedInstanceIDsFallsBackToClient(t *testing.T) {
	const ns = "tuist"
	scheme := vultrScheme(t)
	self := vultrMachine(ns, "adopter", "")
	sibling := vultrMachine(ns, "sibling", "abc")
	cl := fake.NewClientBuilder().WithScheme(scheme).WithObjects(self, sibling).Build()

	r := &VultrMachineReconciler{Client: cl}
	claimed, err := r.claimedInstanceIDs(context.Background(), self)
	if err != nil {
		t.Fatalf("claimedInstanceIDs: %v", err)
	}
	if !claimed["abc"] {
		t.Fatalf("claimed = %v, want the sibling's claim", claimed)
	}
}

func conversionReconciler(t *testing.T, run func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error)) *VultrMachineReconciler {
	t.Helper()
	cl := fake.NewClientBuilder().WithScheme(vultrScheme(t)).Build()
	return &VultrMachineReconciler{
		Client:             cl,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: "tuist"},
		runScript:          run,
	}
}

// A converted box must not be re-converted on every reconcile: the conversion
// destroys and reformats a disk, so re-running it against a live cache node
// would wipe it.
func TestVultrConversionShortCircuitsWhenAlreadyConverted(t *testing.T) {
	called := false
	r := conversionReconciler(t, func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error) {
		called = true
		return "", nil
	})
	m := vultrMachine("tuist", "m", "box-1")
	m.Status.Converted = &infrav1.ConversionStatus{InstanceID: "box-1", QuotaEnforced: true}

	done, _, err := r.reconcileConversion(context.Background(), m, &vultr.Server{ID: "box-1", MainIP: "1.2.3.4"}, nil)
	if err != nil || !done {
		t.Fatalf("done=%v err=%v, want done with no error", done, err)
	}
	if called {
		t.Fatal("re-ran the conversion against an already-converted box; that reformats a live cache disk")
	}
}

// A record from a previous box must never satisfy the current one. Release
// reinstalls the box and the layout does not survive, so crediting a
// predecessor's conversion would join a node whose /data bounds nothing.
func TestVultrConversionIgnoresAnotherBoxesRecord(t *testing.T) {
	called := false
	r := conversionReconciler(t, func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error) {
		called = true
		return "prep-vultr: RESULT device=/dev/nvme0n1p2 fstype=xfs quota=true size=894G", nil
	})
	m := vultrMachine("tuist", "m", "box-2")
	m.Status.Converted = &infrav1.ConversionStatus{InstanceID: "box-1", QuotaEnforced: true}

	done, _, err := r.reconcileConversion(context.Background(), m, &vultr.Server{ID: "box-2", MainIP: "1.2.3.4"}, nil)
	if err != nil {
		t.Fatalf("reconcileConversion: %v", err)
	}
	if !called {
		t.Fatal("trusted a record keyed to another box; the layout does not survive a reinstall")
	}
	if !done || m.Status.Converted.InstanceID != "box-2" {
		t.Fatalf("done=%v converted=%+v, want a fresh record for box-2", done, m.Status.Converted)
	}
}

// The result line is what proves the layout, so it has to land in status.
func TestVultrConversionRecordsWhatTheBoxActuallyGot(t *testing.T) {
	r := conversionReconciler(t, func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error) {
		return "prep-vultr: gate ok\nprep-vultr: RESULT device=/dev/nvme0n1p2 fstype=xfs quota=true size=894G\n", nil
	})
	m := vultrMachine("tuist", "m", "box-1")

	done, _, err := r.reconcileConversion(context.Background(), m, &vultr.Server{ID: "box-1", MainIP: "1.2.3.4"}, nil)
	if err != nil || !done {
		t.Fatalf("done=%v err=%v", done, err)
	}
	c := m.Status.Converted
	if c.DataDevice != "/dev/nvme0n1p2" || c.DataFilesystem != "xfs" || !c.QuotaEnforced {
		t.Fatalf("converted = %+v, want the parsed result line", c)
	}
	if c.Attempts != 0 || c.ConvertedAt == nil {
		t.Fatalf("converted = %+v, want attempts reset and a timestamp", c)
	}
}

// A zero exit without a result line is not a converted box. The script exits
// non-zero when its gates fail, so silence means it is not the script we think
// it is, and treating that as success joins an unbounded node.
func TestVultrConversionRejectsSilentSuccess(t *testing.T) {
	r := conversionReconciler(t, func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error) {
		return "some other script ran fine\n", nil
	})
	m := vultrMachine("tuist", "m", "box-1")

	done, res, err := r.reconcileConversion(context.Background(), m, &vultr.Server{ID: "box-1", MainIP: "1.2.3.4"}, nil)
	if err != nil {
		t.Fatalf("reconcileConversion: %v", err)
	}
	if done {
		t.Fatal("accepted a zero exit with no result line as a converted box")
	}
	if res.RequeueAfter == 0 {
		t.Fatal("want a bounded retry rather than an immediate requeue")
	}
	if m.Status.Converted.Attempts != 1 {
		t.Fatalf("attempts = %d, want the failure counted", m.Status.Converted.Attempts)
	}
}

// An endlessly retrying conversion is worse than a loud failure: the box would
// sit mid-adoption forever while an operator sees nothing wrong with it.
func TestVultrConversionFailsLoudlyAfterRepeatedAttempts(t *testing.T) {
	r := conversionReconciler(t, func(context.Context, string, string, []byte, string, *bootstrap.HostKeyState) (string, error) {
		return "", errors.New("mdadm: no such array")
	})
	m := vultrMachine("tuist", "m", "box-1")
	m.Status.Converted = &infrav1.ConversionStatus{InstanceID: "box-1", Attempts: vultrMaxConvertAttempts}

	done, _, err := r.reconcileConversion(context.Background(), m, &vultr.Server{ID: "box-1", MainIP: "1.2.3.4"}, nil)
	if err != nil {
		t.Fatalf("reconcileConversion: %v", err)
	}
	if done {
		t.Fatal("reported a box with no enforceable /data as converted")
	}
	if m.Status.FailureReason == nil || m.Status.Phase != "Failed" {
		t.Fatalf("phase=%q reason=%v, want a terminal failure", m.Status.Phase, m.Status.FailureReason)
	}
}

// Release reinstalls the box, which wipes the layout. Leaving the record behind
// would let a re-adoption skip the conversion and join an unbounded node.
func TestVultrReleaseClearsTheConversionRecord(t *testing.T) {
	scheme := vultrScheme(t)
	m := vultrMachine("tuist", "m", "box-1")
	m.Status.Converted = &infrav1.ConversionStatus{InstanceID: "box-1", QuotaEnforced: true}
	m.Finalizers = []string{VultrMachineFinalizer}
	cl := fake.NewClientBuilder().WithScheme(scheme).WithObjects(m).Build()

	reinstalled := ""
	srv := newFakeVultrAPI(func(id string) { reinstalled = id })
	r := &VultrMachineReconciler{
		Client:             cl,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: "tuist"},
		VultrClient:        srv,
	}

	if _, err := r.reconcileDelete(context.Background(), m); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if reinstalled != "box-1" {
		t.Fatalf("reinstalled %q, want the released box", reinstalled)
	}
	if m.Status.Converted != nil {
		t.Fatalf("converted = %+v, want it cleared; the reinstall wipes the layout", m.Status.Converted)
	}
}

// newFakeVultrAPI builds a real client over a fake transport, so the release
// path is exercised through the same request-building code production uses
// rather than through a hand-written stub of it.
type fakeVultrTransport struct {
	onReinstall func(id string)
}

func (f *fakeVultrTransport) Do(req *http.Request) (*http.Response, error) {
	if req.Method == http.MethodPost && strings.HasSuffix(req.URL.Path, "/reinstall") {
		parts := strings.Split(strings.TrimSuffix(req.URL.Path, "/reinstall"), "/")
		f.onReinstall(parts[len(parts)-1])
	}
	return &http.Response{StatusCode: 202, Body: io.NopCloser(strings.NewReader(`{}`))}, nil
}

func newFakeVultrAPI(onReinstall func(id string)) *vultr.Client {
	return &vultr.Client{
		HTTP:    &fakeVultrTransport{onReinstall: onReinstall},
		BaseURL: "https://api.vultr.com/v2",
		APIKey:  "k",
	}
}
