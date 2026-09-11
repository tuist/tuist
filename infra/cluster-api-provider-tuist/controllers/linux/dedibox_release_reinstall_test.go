package linux

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/dedibox"
)

const (
	dediboxReleaseServerID = 75839
	dediboxReleaseZone     = "fr-par-1"
	dediboxReleaseFleet    = "tuist-kura-dedibox"
)

// dediboxAPI serves the Dedibox endpoints the release reinstall walks, with the
// install POST and the install status wired per test. Reached through the
// client's own DEDIBOX_API_URL override rather than an injected transport.
type dediboxAPI struct {
	installStatus string
	installCode   int
	installPosted bool
}

func (d *dediboxAPI) client(t *testing.T) *dedibox.Client {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		write := func(code int, body any) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(code)
			_ = json.NewEncoder(w).Encode(body)
		}
		switch {
		case strings.HasSuffix(req.URL.Path, "/ssh-keys"):
			write(http.StatusOK, map[string]any{"ssh_keys": []map[string]string{{"id": "key-1", "public_key": "any"}}})
		case strings.HasSuffix(req.URL.Path, "/os"):
			write(http.StatusOK, map[string]any{"os": []map[string]any{
				{"id": 42, "name": "Ubuntu", "version": "24.04 LTS", "allow_ssh_keys": true, "requires_user": true},
			}})
		case strings.HasSuffix(req.URL.Path, "/install") && req.Method == http.MethodPost:
			d.installPosted = true
			write(d.installCode, map[string]string{"message": "install already in progress"})
		case strings.HasSuffix(req.URL.Path, "/install"):
			write(http.StatusOK, map[string]any{"status": d.installStatus})
		default:
			write(http.StatusNotFound, map[string]string{"message": "unmapped " + req.URL.Path})
		}
	}))
	t.Cleanup(server.Close)

	t.Setenv("DEDIBOX_SCW_SECRET_KEY", "test")
	t.Setenv("DEDIBOX_SCW_PROJECT_ID", "proj")
	t.Setenv("DEDIBOX_API_URL", server.URL)
	c, err := dedibox.NewClientFromEnv()
	if err != nil {
		t.Fatalf("dedibox client: %v", err)
	}
	return c
}

func releasingDediboxMachine() *infrav1.DediboxMachine {
	machine := &infrav1.DediboxMachine{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:  "tuist",
			Name:       "tuist-kura-dedibox-abc12-xyz34",
			Finalizers: []string{DediboxMachineFinalizer},
		},
	}
	machine.Spec.FleetName = dediboxReleaseFleet
	machine.Status.ServerID = dediboxReleaseServerID
	machine.Status.Zone = dediboxReleaseZone
	return machine
}

func newDediboxReleaseReconciler(t *testing.T, api *dediboxAPI) (*DediboxMachineReconciler, *infrav1.DediboxMachine, *record.FakeRecorder) {
	t.Helper()
	scheme := releaseScheme(t)
	machine := releasingDediboxMachine()
	secret := fleetSSHKeySecret(t, machine.Namespace, dediboxReleaseFleet)
	cl := fake.NewClientBuilder().WithScheme(scheme).WithObjects(machine, secret).Build()
	recorder := record.NewFakeRecorder(10)
	return &DediboxMachineReconciler{
		Client:             cl,
		Scheme:             scheme,
		DediboxClient:      api.client(t),
		Recorder:           recorder,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: machine.Namespace},
	}, machine, recorder
}

// The Dedibox release holds the finalizer until the reinstall completes, so a
// rejected install POST is not a slow release — it is a Machine that never
// leaves Deleting at all. Dedibox reports no error class for "an install is
// already queued", so the box's own install status is the readable signal, and
// an install already running is the state the release is trying to reach.
func TestDediboxReleaseAdoptsAnInstallAlreadyInFlight(t *testing.T) {
	api := &dediboxAPI{installCode: http.StatusBadRequest, installStatus: "installing"}
	r, machine, recorder := newDediboxReleaseReconciler(t, api)

	result, done, err := r.reconcileReleaseReinstall(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileReleaseReinstall: %v", err)
	}
	if done {
		t.Fatal("release reported done while the install is still running")
	}
	if result.RequeueAfter != dediboxInstallPollInterval {
		t.Fatalf("RequeueAfter = %s, want the install poll interval %s", result.RequeueAfter, dediboxInstallPollInterval)
	}
	if machine.Annotations[dediboxReleaseReinstallStartedAnnotation] != "true" {
		t.Fatal("the in-flight install was not adopted, so the release retries the POST forever")
	}
	if machine.Annotations[dediboxReleaseReinstallObservedAnnotation] != "true" {
		t.Fatal("an install seen running is the in-progress observation the completion gate needs")
	}
	if events := drainRecorder(recorder); !strings.Contains(events, "ReleasedToPool") {
		t.Fatalf("events = %q, want a ReleasedToPool event recording the in-flight install", events)
	}
}

// A rejected POST on a box with no install running still has to retry, bounded,
// with the finalizer kept.
func TestDediboxReleaseRetriesBoundedWhenNoInstallIsRunning(t *testing.T) {
	api := &dediboxAPI{installCode: http.StatusInternalServerError, installStatus: "installed"}
	r, machine, recorder := newDediboxReleaseReconciler(t, api)

	result, done, err := r.reconcileReleaseReinstall(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileReleaseReinstall returned %v; an error makes controller-runtime ignore RequeueAfter", err)
	}
	if done {
		t.Fatal("release reported done on a box that was never reinstalled")
	}
	if result.RequeueAfter <= 0 || result.RequeueAfter > dediboxInstallPollInterval {
		t.Fatalf("RequeueAfter = %s, want a bounded retry of at most %s", result.RequeueAfter, dediboxInstallPollInterval)
	}
	if machine.Annotations[dediboxReleaseReinstallStartedAnnotation] == "true" {
		t.Fatal("marked the reinstall started even though no install is running on the box")
	}
	if events := drainRecorder(recorder); !strings.Contains(events, "ReleaseReinstallFailed") {
		t.Fatalf("events = %q, want a ReleaseReinstallFailed event", events)
	}
}
