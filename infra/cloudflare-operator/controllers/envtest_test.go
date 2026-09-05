// envtest coverage for the CRD admission rules the reconciler
// depends on. Marek's review flagged that scripted-fake reconciler
// tests do not exercise the API server's CEL validation, so a
// misworded rule or a schema drift would only surface at deploy
// time. These tests boot a real kube-apiserver + etcd via
// controller-runtime's envtest and apply valid / invalid CRs
// against it.
//
// Requires the envtest binaries. In CI the workflow installs them
// with sigs.k8s.io/controller-runtime/tools/setup-envtest and sets
// KUBEBUILDER_ASSETS. Local runs without those binaries skip the
// test rather than fail, so `go test ./...` still passes on a fresh
// checkout.

package controllers

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
)

// envtestClient starts a local kube-apiserver + etcd via envtest,
// installs the CRDs shipped under config/crd/, and returns a
// controller-runtime client bound to that API server. Returns nil,
// nil, nil (with t.Skip called) when envtest binaries are absent.
func envtestClient(t *testing.T) (client.Client, *envtest.Environment, func()) {
	t.Helper()
	if os.Getenv("KUBEBUILDER_ASSETS") == "" {
		t.Skip("envtest binaries not present (set KUBEBUILDER_ASSETS to run)")
	}
	scheme := runtime.NewScheme()
	if err := cfv1alpha1.AddToScheme(scheme); err != nil {
		t.Fatalf("register scheme: %v", err)
	}
	env := &envtest.Environment{
		CRDDirectoryPaths:     []string{filepath.Join("..", "config", "crd")},
		ErrorIfCRDPathMissing: true,
	}
	cfg, err := env.Start()
	if err != nil {
		t.Fatalf("envtest start: %v", err)
	}
	c, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		_ = env.Stop()
		t.Fatalf("build client: %v", err)
	}
	return c, env, func() { _ = env.Stop() }
}

func baseValidCR(name string) *cfv1alpha1.CloudflareRateLimit {
	enabled := true
	return &cfv1alpha1.CloudflareRateLimit{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Spec: cfv1alpha1.CloudflareRateLimitSpec{
			ZoneID:         "zone-abc",
			Description:    "test",
			Expression:     `(http.request.method eq "GET")`,
			Action:         "managed_challenge",
			Enabled:        &enabled,
			Mode:           cfv1alpha1.ReconcileModeReadOnly,
			CreateNewRule:  true,
			RetainOnDelete: true,
			RateLimit: cfv1alpha1.CloudflareRateLimitParameters{
				Characteristics:          []string{"cf.colo.id", "ip.src"},
				RequestsPerPeriod:        60,
				Period:                   10,
				MitigationTimeoutSeconds: 60,
			},
		},
	}
}

// TestEnvtest_CRDAdmission_RejectsMissingCoLoID confirms the CEL rule
// requiring cf.colo.id in characteristics fires at admission time,
// so a misconfigured CR never reaches the reconciler.
func TestEnvtest_CRDAdmission_RejectsMissingCoLoID(t *testing.T) {
	c, _, stop := envtestClient(t)
	defer stop()

	cr := baseValidCR("no-colo")
	cr.Spec.RateLimit.Characteristics = []string{"ip.src"}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	err := c.Create(ctx, cr)
	if err == nil {
		t.Fatal("expected admission to reject CR without cf.colo.id")
	}
	if !strings.Contains(err.Error(), "cf.colo.id") {
		t.Errorf("expected error to mention cf.colo.id, got %v", err)
	}
}

// TestEnvtest_CRDAdmission_RejectsAdoptAndCreateMissing confirms the
// CEL rule requiring either adopt or createNewRule to be set fires.
func TestEnvtest_CRDAdmission_RejectsAdoptAndCreateMissing(t *testing.T) {
	c, _, stop := envtestClient(t)
	defer stop()

	cr := baseValidCR("neither")
	cr.Spec.Adopt = nil
	cr.Spec.CreateNewRule = false

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	err := c.Create(ctx, cr)
	if err == nil {
		t.Fatal("expected admission to reject CR with neither adopt nor createNewRule")
	}
}

// TestEnvtest_CRDAdmission_ZoneIDImmutable is the most important
// admission test: it locks in the invariant the reconciler's delete
// path (using status.managedZoneId) is a belt for. Once set, zoneId
// must not change.
func TestEnvtest_CRDAdmission_ZoneIDImmutable(t *testing.T) {
	c, _, stop := envtestClient(t)
	defer stop()

	cr := baseValidCR("zone-immutable")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := c.Create(ctx, cr); err != nil {
		t.Fatalf("initial create: %v", err)
	}
	// Fetch, mutate zone, expect rejection.
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := c.Get(ctx, types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	got.Spec.ZoneID = "different-zone"
	err := c.Update(ctx, got)
	if err == nil {
		t.Fatal("expected admission to reject zoneId mutation")
	}
	if !strings.Contains(err.Error(), "zoneId is immutable") {
		t.Errorf("expected immutability message, got %v", err)
	}
}

// TestEnvtest_CRDAdmission_AdoptImmutable locks in adopt immutability
// so a CR cannot silently re-point at a different Cloudflare rule.
func TestEnvtest_CRDAdmission_AdoptImmutable(t *testing.T) {
	c, _, stop := envtestClient(t)
	defer stop()

	cr := baseValidCR("adopt-immutable")
	cr.Spec.Adopt = &cfv1alpha1.AdoptRule{RuleID: "rule-1"}
	cr.Spec.CreateNewRule = false
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := c.Create(ctx, cr); err != nil {
		t.Fatalf("initial create: %v", err)
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := c.Get(ctx, types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	got.Spec.Adopt = &cfv1alpha1.AdoptRule{RuleID: "rule-2"}
	err := c.Update(ctx, got)
	if err == nil {
		t.Fatal("expected admission to reject adopt mutation")
	}
}

// TestEnvtest_CRDDefaults confirms the schema defaults land as
// documented (mode=read_only, retainOnDelete=true, paused=false).
func TestEnvtest_CRDDefaults(t *testing.T) {
	c, _, stop := envtestClient(t)
	defer stop()

	// Build a minimal CR: rely on defaults for mode, retainOnDelete,
	// paused. Adopt is set so the CR passes the adopt-or-create CEL.
	enabled := true
	cr := &cfv1alpha1.CloudflareRateLimit{
		ObjectMeta: metav1.ObjectMeta{Name: "defaults"},
		Spec: cfv1alpha1.CloudflareRateLimitSpec{
			ZoneID:      "zone-abc",
			Description: "test",
			Expression:  `(http.request.method eq "GET")`,
			Action:      "managed_challenge",
			Enabled:     &enabled,
			Adopt:       &cfv1alpha1.AdoptRule{RuleID: "rule-x"},
			RateLimit: cfv1alpha1.CloudflareRateLimitParameters{
				Characteristics:          []string{"cf.colo.id"},
				RequestsPerPeriod:        60,
				Period:                   10,
				MitigationTimeoutSeconds: 60,
			},
		},
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := c.Create(ctx, cr); err != nil {
		t.Fatalf("create: %v", err)
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := c.Get(ctx, types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Spec.Mode != cfv1alpha1.ReconcileModeReadOnly {
		t.Errorf("default mode = %q, want read_only", got.Spec.Mode)
	}
	if !got.Spec.RetainOnDelete {
		t.Error("default retainOnDelete should be true")
	}
	if got.Spec.Paused {
		t.Error("default paused should be false")
	}
}
