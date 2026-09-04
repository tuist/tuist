package controllers

import (
	"context"
	"errors"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// fakeCF is a scripted RulesetAPI used across reconciler tests. Each
// method records the call and returns whatever the test wired up.
type fakeCF struct {
	ruleset      *cloudflare.Ruleset
	getErr       error
	createRS     *cloudflare.Ruleset
	createErr    error
	addRule      func(rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	updateRule   func(ruleID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	deletedRules []string
	deleteErr    error
	addCalls     int
	updateCalls  int
}

func (f *fakeCF) GetPhaseRuleset(_ context.Context, _, _ string) (*cloudflare.Ruleset, error) {
	return f.ruleset, f.getErr
}

func (f *fakeCF) CreatePhaseRuleset(_ context.Context, _, _ string) (*cloudflare.Ruleset, error) {
	if f.createErr != nil {
		return nil, f.createErr
	}
	f.ruleset = f.createRS
	return f.createRS, nil
}

func (f *fakeCF) AddRule(_ context.Context, _, _ string, rule cloudflare.Rule) (*cloudflare.Ruleset, error) {
	f.addCalls++
	if f.addRule != nil {
		rs, err := f.addRule(rule)
		if rs != nil {
			f.ruleset = rs
		}
		return rs, err
	}
	if f.ruleset == nil {
		f.ruleset = &cloudflare.Ruleset{ID: "rs-default"}
	}
	rule.ID = "rule-" + rule.Ref
	f.ruleset.Rules = append(f.ruleset.Rules, rule)
	return f.ruleset, nil
}

func (f *fakeCF) UpdateRule(_ context.Context, _, _, ruleID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error) {
	f.updateCalls++
	if f.updateRule != nil {
		rs, err := f.updateRule(ruleID, rule)
		if rs != nil {
			f.ruleset = rs
		}
		return rs, err
	}
	for i := range f.ruleset.Rules {
		if f.ruleset.Rules[i].ID == ruleID {
			rule.ID = ruleID
			f.ruleset.Rules[i] = rule
		}
	}
	return f.ruleset, nil
}

func (f *fakeCF) DeleteRule(_ context.Context, _, _, ruleID string) error {
	f.deletedRules = append(f.deletedRules, ruleID)
	if f.deleteErr != nil {
		return f.deleteErr
	}
	if f.ruleset == nil {
		return nil
	}
	out := f.ruleset.Rules[:0]
	for _, r := range f.ruleset.Rules {
		if r.ID != ruleID {
			out = append(out, r)
		}
	}
	f.ruleset.Rules = out
	return nil
}

func newTestScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	s := runtime.NewScheme()
	if err := cfv1alpha1.AddToScheme(s); err != nil {
		t.Fatalf("register scheme: %v", err)
	}
	return s
}

func sampleCR(uid string) *cfv1alpha1.CloudflareRateLimit {
	enabled := true
	return &cfv1alpha1.CloudflareRateLimit{
		ObjectMeta: metaWithUID("public-pages", uid),
		Spec: cfv1alpha1.CloudflareRateLimitSpec{
			ZoneID:      "zone-abc",
			Description: "Public pages anti-bombardment",
			Expression:  `(http.request.method eq "GET")`,
			Action:      "managed_challenge",
			Enabled:     &enabled,
			RateLimit: cfv1alpha1.CloudflareRateLimitParameters{
				Characteristics:          []string{"ip.src"},
				RequestsPerPeriod:        60,
				Period:                   10,
				MitigationTimeoutSeconds: 60,
				CountingExpression:       `(http.response.headers["x-tuist-public"][0] eq "1")`,
			},
		},
	}
}

// TestReconcile_CreatesRuleWhenMissing exercises the happy path: no
// existing rule with the operator's ref, so AddRule is called.
func TestReconcile_CreatesRuleWhenMissing(t *testing.T) {
	cr := sampleCR("uid-1234567890abc")
	// Simulate the finalizer already having been added, so the reconcile
	// proceeds past the finalizer-add early return.
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()

	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: nil}}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	res, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}})
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if res.RequeueAfter <= 0 {
		t.Fatalf("expected requeue after success, got %+v", res)
	}
	if cf.addCalls != 1 {
		t.Fatalf("expected one AddRule call, got %d", cf.addCalls)
	}
	if cf.updateCalls != 0 {
		t.Fatalf("expected zero UpdateRule calls, got %d", cf.updateCalls)
	}

	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get after reconcile: %v", err)
	}
	if got.Status.RulesetID != "rs-1" {
		t.Errorf("status.rulesetID = %q, want rs-1", got.Status.RulesetID)
	}
	if got.Status.RuleID == "" {
		t.Error("status.ruleID must be set after create")
	}
	if got.Status.Message != "created" {
		t.Errorf("status.message = %q, want %q", got.Status.Message, "created")
	}
}

// TestReconcile_UpdatesWhenSpecChanges verifies the reconciler PATCHes
// the live rule when a spec field differs.
func TestReconcile_UpdatesWhenSpecChanges(t *testing.T) {
	cr := sampleCR("uid-9876543210xyz")
	cr.Finalizers = []string{finalizer}
	ref := ruleRef(cr)

	// Live rule already exists but has a different requests-per-period.
	live := renderRule(cr, ref)
	live.ID = "existing-id"
	live.RateLimit.RequestsPerPeriod = 30

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{live}}}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 1 {
		t.Fatalf("expected one UpdateRule call, got %d", cf.updateCalls)
	}
	if cf.addCalls != 0 {
		t.Fatalf("expected zero AddRule calls, got %d", cf.addCalls)
	}
}

// TestReconcile_NoOpWhenInSync makes sure a subsequent reconcile after
// a successful sync does not re-issue a PATCH.
func TestReconcile_NoOpWhenInSync(t *testing.T) {
	cr := sampleCR("uid-in-sync-abc")
	cr.Finalizers = []string{finalizer}
	ref := ruleRef(cr)

	live := renderRule(cr, ref)
	live.ID = "existing-id"

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{live}}}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 0 || cf.updateCalls != 0 {
		t.Fatalf("expected no writes when in sync, got add=%d update=%d", cf.addCalls, cf.updateCalls)
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Status.Message != "in sync" {
		t.Errorf("status.message = %q, want %q", got.Status.Message, "in sync")
	}
}

// TestReconcile_CreatesRulesetWhenMissing tests the lazy-bootstrap path
// where a zone has no http_ratelimit ruleset yet.
func TestReconcile_CreatesRulesetWhenMissing(t *testing.T) {
	cr := sampleCR("uid-boot-abc")
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{
		ruleset:  nil,
		createRS: &cloudflare.Ruleset{ID: "rs-new"},
	}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 1 {
		t.Fatalf("expected one AddRule call after lazy ruleset create, got %d", cf.addCalls)
	}
}

// TestReconcile_AddsFinalizer confirms the first reconcile of a CR
// without the finalizer sets it and requeues without touching the API.
func TestReconcile_AddsFinalizer(t *testing.T) {
	cr := sampleCR("uid-finalizer-abc")

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 0 {
		t.Fatalf("expected no API calls before finalizer is set, got %d", cf.addCalls)
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if !containsFinalizer(got.Finalizers, finalizer) {
		t.Errorf("expected finalizer %q on CR, got %v", finalizer, got.Finalizers)
	}
}

// TestReconcile_DeleteRemovesLiveRule verifies the CR-delete path
// removes the Cloudflare rule and then drops the finalizer.
func TestReconcile_DeleteRemovesLiveRule(t *testing.T) {
	cr := sampleCR("uid-delete-abc")
	cr.Finalizers = []string{finalizer}
	now := metaNow()
	cr.DeletionTimestamp = &now

	ref := ruleRef(cr)
	live := renderRule(cr, ref)
	live.ID = "existing-id"

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{live}}}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if len(cf.deletedRules) != 1 || cf.deletedRules[0] != "existing-id" {
		t.Errorf("expected DeleteRule for existing-id, got %v", cf.deletedRules)
	}
}

// TestReconcile_APIErrorSurfacesInStatus proves that a Cloudflare API
// failure is surfaced in the CR status so the operator user sees why.
func TestReconcile_APIErrorSurfacesInStatus(t *testing.T) {
	cr := sampleCR("uid-error-abc")
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{
		ruleset: &cloudflare.Ruleset{ID: "rs-1"},
		addRule: func(cloudflare.Rule) (*cloudflare.Ruleset, error) {
			return nil, errors.New("boom")
		},
	}

	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err == nil {
		t.Fatal("expected reconcile to return the API error")
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Status.Message == "" {
		t.Error("expected status.message to carry the API error")
	}
}

func TestRulesetRuleDiffers(t *testing.T) {
	a := renderRule(sampleCR("uid-diff-abc"), "cfop_x")
	b := renderRule(sampleCR("uid-diff-abc"), "cfop_x")
	if rulesetRuleDiffers(&a, &b) {
		t.Error("identical rules should not differ")
	}
	b.RateLimit.RequestsPerPeriod++
	if !rulesetRuleDiffers(&a, &b) {
		t.Error("changed requestsPerPeriod should count as differ")
	}
	c := renderRule(sampleCR("uid-diff-abc"), "cfop_x")
	c.Action = "block"
	if !rulesetRuleDiffers(&a, &c) {
		t.Error("changed action should count as differ")
	}
}

// helpers ---------------------------------------------------------------

func metaWithUID(name, uid string) metav1.ObjectMeta {
	return metav1.ObjectMeta{Name: name, UID: types.UID(uid)}
}

func containsFinalizer(list []string, f string) bool {
	for _, e := range list {
		if e == f {
			return true
		}
	}
	return false
}

func metaNow() metav1.Time {
	return metav1.NewTime(time.Now().UTC())
}
