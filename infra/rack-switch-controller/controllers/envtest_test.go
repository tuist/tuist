// envtest coverage for what the fake client cannot check: the generated CRD
// admitting the committed objects with managedBy defaulted, and the
// reconciler's status patches against a real API server.
//
// Requires the envtest binaries. CI installs them with setup-envtest and sets
// KUBEBUILDER_ASSETS; without them the tests skip, so `go test ./...` passes
// on a fresh checkout.

package controllers

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	"sigs.k8s.io/yaml"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

func envtestClient(t *testing.T) client.Client {
	t.Helper()
	if os.Getenv("KUBEBUILDER_ASSETS") == "" {
		t.Skip("envtest binaries not present (set KUBEBUILDER_ASSETS to run)")
	}
	scheme := runtime.NewScheme()
	if err := v1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	env := &envtest.Environment{
		CRDInstallOptions: envtest.CRDInstallOptions{
			Paths:              []string{filepath.Join("..", "..", "helm", "tuist", "crds", "tuist.dev_rackswitches.yaml")},
			ErrorIfPathMissing: true,
		},
	}
	cfg, err := env.Start()
	if err != nil {
		t.Fatalf("envtest start: %v", err)
	}
	t.Cleanup(func() { _ = env.Stop() })
	c, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		t.Fatal(err)
	}
	ns := &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: namespace}}
	if err := c.Create(context.Background(), ns); err != nil {
		t.Fatal(err)
	}
	return c
}

func TestEnvtestTheCommittedObjectsAreAdmittedAsWritten(t *testing.T) {
	c := envtestClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	paths, err := filepath.Glob(filepath.Join("..", "..", "rack-switch-fleet", "k8s", "ber1", "*.yaml"))
	if err != nil || len(paths) == 0 {
		t.Fatal("no committed objects")
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var rs v1alpha1.RackSwitch
		if err := yaml.Unmarshal(raw, &rs); err != nil {
			t.Fatal(err)
		}
		rs.Namespace = namespace
		if err := c.Create(ctx, &rs); err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		var stored v1alpha1.RackSwitch
		if err := c.Get(ctx, client.ObjectKeyFromObject(&rs), &stored); err != nil {
			t.Fatal(err)
		}
		if stored.Spec.ManagedBy != rs.Spec.ManagedBy {
			t.Fatalf("%s: managedBy stored as %q, written as %q", path, stored.Spec.ManagedBy, rs.Spec.ManagedBy)
		}

		// Without managedBy, an object is standalone.
		bare := rs.DeepCopy()
		bare.ResourceVersion = ""
		bare.Name = rs.Name + "-bare"
		bare.Spec.ManagedBy = ""
		if err := c.Create(ctx, bare); err != nil {
			t.Fatalf("%s without managedBy: %v", path, err)
		}
		if err := c.Get(ctx, client.ObjectKeyFromObject(bare), &stored); err != nil {
			t.Fatal(err)
		}
		if stored.Spec.ManagedBy != v1alpha1.ManagedByStandalone {
			t.Fatalf("%s without managedBy: defaulted to %q", path, stored.Spec.ManagedBy)
		}
	}
}

func TestEnvtestTheReconcilersStatusIsAdmitted(t *testing.T) {
	c := envtestClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	fakeOmada := omadatest.New()
	defer fakeOmada.Close()
	ports := omadatest.Ports(8)
	ports[7].Name = "isl"
	fakeOmada.AddSwitch(omadatest.Switch{MAC: torBMAC, State: omadatest.Connected, Hostname: "D4-D6-DF-03-D8-B2", Ports: ports})

	if err := c.Create(ctx, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController)); err != nil {
		t.Fatal(err)
	}
	r := &RackSwitchReconciler{
		Client:   c,
		Recorder: record.NewFakeRecorder(100),
		Engine: &converge.Engine{
			Omada:             omada.New(fakeOmada.URL, func() (string, string, error) { return creds.ClientID, creds.ClientSecret, nil }, fakeOmada.RootCAs()),
			Site:              omadatest.SiteName,
			ControllerAddress: controllerAddress,
		},
		Credentials:    func() (converge.Credentials, error) { return creds, nil },
		ResyncInterval: resync,
	}
	key := types.NamespacedName{Namespace: namespace, Name: "ber1-tor-b"}
	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: key}); err != nil {
		t.Fatal(err)
	}
	var stored v1alpha1.RackSwitch
	if err := c.Get(ctx, key, &stored); err != nil {
		t.Fatal(err)
	}
	if !meta.IsStatusConditionTrue(stored.Status.Conditions, v1alpha1.ConditionReady) || stored.Status.ObservedRevision != "rev-1" {
		t.Fatalf("status = %+v", stored.Status)
	}
	if stored.Spec.Config.Hostname != "ber1-tor-b" {
		t.Fatal("the status patch changed the spec")
	}
}
