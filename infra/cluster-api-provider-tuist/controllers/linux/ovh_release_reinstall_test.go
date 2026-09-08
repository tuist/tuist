package linux

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"encoding/pem"
	"strings"
	"testing"

	goovh "github.com/ovh/go-ovh/ovh"
	"golang.org/x/crypto/ssh"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

const (
	releaseService = "ns3048220.ip-51-255-75.eu"
	releaseFleet   = "tuist-kura-ovh"
)

// fakeOVHReinstallAPI stands in for go-ovh's *ovh.Client: GETs are served from a canned
// URL map and the reinstall POST returns whatever the test wired.
type fakeOVHReinstallAPI struct {
	get       map[string]any
	postErr   map[string]error
	postPaths []string
}

func (f *fakeOVHReinstallAPI) GetWithContext(_ context.Context, url string, res any) error {
	v, ok := f.get[url]
	if !ok {
		return &goovh.APIError{Code: 404, Message: "not found: " + url}
	}
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, res)
}

func (f *fakeOVHReinstallAPI) PostWithContext(_ context.Context, url string, _, _ any) error {
	f.postPaths = append(f.postPaths, url)
	return f.postErr[url]
}

func (f *fakeOVHReinstallAPI) PutWithContext(_ context.Context, _ string, _, _ any) error { return nil }
func (f *fakeOVHReinstallAPI) DeleteWithContext(_ context.Context, _ string, _ any) error { return nil }

// installableServer is the GET surface StartInstall needs before it POSTs: the
// compatible templates and the disk groups the storage layout is planned from.
func installableServer() map[string]any {
	return map[string]any{
		"/dedicated/server/" + releaseService + "/install/compatibleTemplates": map[string][]string{
			"ovh":      {"ubuntu2404-server_64"},
			"personal": {},
		},
		"/dedicated/server/" + releaseService + "/specifications/hardware": map[string]any{
			"diskGroups": []map[string]any{{
				"diskGroupId":   1,
				"numberOfDisks": 2,
				"diskSize":      map[string]any{"unit": "Go", "value": 960},
				"diskType":      "SSD",
			}},
		},
	}
}

// taskAlreadyExists is the 400 OVH returns for a second reinstall on a server
// that already has one queued, verbatim from the 2026-09-03 production wedge.
func taskAlreadyExists() error {
	return &goovh.APIError{
		Code:  400,
		Class: "Client::BadRequest::TaskAlreadyExists",
		Message: "Task 563254948 of type reinstallServer with status todo is already running on server " +
			releaseService,
	}
}

func releaseScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, rbacv1.AddToScheme, infrav1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}
	return scheme
}

// fleetSSHKeySecret pre-seeds the fleet key EnsureFleetSSHKey reads, so the
// release path never reaches the Scaleway registration generateSSHKey does.
func fleetSSHKeySecret(t *testing.T, namespace, fleet string) *corev1.Secret {
	t.Helper()
	pubKey, privKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(privKey, "test")
	if err != nil {
		t.Fatal(err)
	}
	sshPub, err := ssh.NewPublicKey(pubKey)
	if err != nil {
		t.Fatal(err)
	}
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:   namespace,
			Name:        fleet + "-ssh",
			Annotations: map[string]string{"scaleway.tuist.dev/ssh-key-id": "key-1"},
		},
		Data: map[string][]byte{
			"id_ed25519":     pem.EncodeToMemory(block),
			"id_ed25519.pub": ssh.MarshalAuthorizedKey(sshPub),
		},
	}
}

func releasingMachine() *infrav1.OVHDedicatedMachine {
	machine := &infrav1.OVHDedicatedMachine{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:  "tuist",
			Name:       "tuist-kura-ovh-abc12-xyz34",
			Finalizers: []string{OVHDedicatedMachineFinalizer},
		},
	}
	machine.Spec.FleetName = releaseFleet
	machine.Status.ServiceName = releaseService
	return machine
}

func newReleaseReconciler(t *testing.T, api *fakeOVHReinstallAPI) (*OVHDedicatedMachineReconciler, *infrav1.OVHDedicatedMachine, *record.FakeRecorder) {
	t.Helper()
	scheme := releaseScheme(t)
	machine := releasingMachine()
	cl := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(machine, fleetSSHKeySecret(t, machine.Namespace, releaseFleet)).
		Build()
	recorder := record.NewFakeRecorder(10)
	return &OVHDedicatedMachineReconciler{
		Client:             cl,
		Scheme:             scheme,
		OVHClient:          &ovh.Client{API: api},
		Recorder:           recorder,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: machine.Namespace},
	}, machine, recorder
}

func drainRecorder(recorder *record.FakeRecorder) string {
	var events []string
	for {
		select {
		case e := <-recorder.Events:
			events = append(events, e)
		default:
			return strings.Join(events, "\n")
		}
	}
}

// A release that finds OVH already reinstalling the box must drop the finalizer
// rather than retry. reinstallToPool's postcondition is "this box is being
// returned to a clean, claimable state", and an in-flight reinstallServer task
// already meets it — but OVH keeps rejecting the second POST with
// TaskAlreadyExists for the whole ~30 min install, so retrying holds the Machine
// in Deleting. In production (2026-09-03) that pinned a MachineDeployment one
// replica above spec for 13 minutes and timed out a helm --atomic rollback.
func TestOVHReconcileDeleteReleasesWhenReinstallAlreadyInFlight(t *testing.T) {
	get := installableServer()
	get["/dedicated/server/"+releaseService+"/task"] = []int64{563254948}
	get["/dedicated/server/"+releaseService+"/task/563254948"] = map[string]any{
		"function": "reinstallServer",
		"status":   "todo",
	}
	api := &fakeOVHReinstallAPI{
		get:     get,
		postErr: map[string]error{"/dedicated/server/" + releaseService + "/reinstall": taskAlreadyExists()},
	}
	r, machine, recorder := newReleaseReconciler(t, api)

	result, err := r.reconcileDelete(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if result.RequeueAfter != 0 {
		t.Fatalf("reconcileDelete requeued after %s; an in-flight reinstall needs no retry", result.RequeueAfter)
	}
	if controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		t.Fatal("finalizer kept: the Machine wedges in Deleting until the in-flight reinstall finishes")
	}
	if events := drainRecorder(recorder); !strings.Contains(events, "ReleasedToPool") {
		t.Fatalf("events = %q, want a ReleasedToPool event recording the in-flight reinstall", events)
	}
}

// TaskAlreadyExists only stands in for a completed release when the queued task
// is an install. Any other task type (a reboot, a hardware intervention) leaves
// the box in whatever state the Machine left it, so the reinstall still has to
// be issued.
func TestOVHReconcileDeleteRetriesWhenInFlightTaskIsNotAnInstall(t *testing.T) {
	get := installableServer()
	get["/dedicated/server/"+releaseService+"/task"] = []int64{563254948}
	get["/dedicated/server/"+releaseService+"/task/563254948"] = map[string]any{
		"function": "hardReboot",
		"status":   "doing",
	}
	api := &fakeOVHReinstallAPI{
		get:     get,
		postErr: map[string]error{"/dedicated/server/" + releaseService + "/reinstall": taskAlreadyExists()},
	}
	r, machine, _ := newReleaseReconciler(t, api)

	result, err := r.reconcileDelete(context.Background(), machine)
	if err == nil && result.RequeueAfter == 0 {
		t.Fatal("reconcileDelete neither errored nor requeued; a non-install task is no release guarantee")
	}
	if !controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		t.Fatal("finalizer dropped on a box that was never reinstalled")
	}
}

// Every other reinstall failure still retries, and bounded: controller-runtime's
// default backoff had already stretched to ~6 minutes during the production
// wedge and doubles to a 1000s cap, so a Machine idles long after OVH frees the
// server.
func TestOVHReconcileDeleteRetriesBoundedOnReinstallFailure(t *testing.T) {
	api := &fakeOVHReinstallAPI{
		get: installableServer(),
		postErr: map[string]error{
			"/dedicated/server/" + releaseService + "/reinstall": &goovh.APIError{
				Code:    500,
				Class:   "Server::InternalServerError",
				Message: "internal server error",
			},
		},
	}
	r, machine, recorder := newReleaseReconciler(t, api)

	result, err := r.reconcileDelete(context.Background(), machine)
	if !controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		t.Fatal("finalizer dropped on a box that was never reinstalled")
	}
	if err != nil {
		t.Fatalf("reconcileDelete returned %v; an error makes controller-runtime ignore RequeueAfter and fall back to unbounded backoff", err)
	}
	if result.RequeueAfter <= 0 || result.RequeueAfter > ovhReleaseRetryInterval {
		t.Fatalf("RequeueAfter = %s, want a bounded retry of at most %s", result.RequeueAfter, ovhReleaseRetryInterval)
	}
	if events := drainRecorder(recorder); !strings.Contains(events, "ReleaseReinstallFailed") {
		t.Fatalf("events = %q, want a ReleaseReinstallFailed event", events)
	}
}
