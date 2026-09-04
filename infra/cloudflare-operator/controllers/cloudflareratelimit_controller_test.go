package controllers

import (
	"context"
	"encoding/json"
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
	createCalls  int
	getCalls     int
}

func (f *fakeCF) GetPhaseRuleset(_ context.Context, _, _ string) (*cloudflare.Ruleset, error) {
	f.getCalls++
	return f.ruleset, f.getErr
}

func (f *fakeCF) CreatePhaseRuleset(_ context.Context, _, _ string) (*cloudflare.Ruleset, error) {
	f.createCalls++
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

// sampleActiveCR is a CR wired for the active create path: an operator
// user opted in explicitly, so createNewRule is true and mode is
// active. cf.colo.id is present in characteristics to satisfy the
// CRD-level CEL requirement (tests exercise reconciler logic, not the
// admission validator, but keeping samples valid guards against
// accidentally shipping an invalid renderer).
func sampleActiveCR(uid string) *cfv1alpha1.CloudflareRateLimit {
	enabled := true
	return &cfv1alpha1.CloudflareRateLimit{
		ObjectMeta: metaWithUID("public-pages", uid),
		Spec: cfv1alpha1.CloudflareRateLimitSpec{
			ZoneID:         "zone-abc",
			Description:    "Public pages anti-bombardment",
			Expression:     `(http.request.method eq "GET")`,
			Action:         "managed_challenge",
			Enabled:        &enabled,
			Mode:           cfv1alpha1.ReconcileModeActive,
			CreateNewRule:  true,
			RetainOnDelete: false,
			RateLimit: cfv1alpha1.CloudflareRateLimitParameters{
				Characteristics:          []string{"cf.colo.id", "ip.src"},
				RequestsPerPeriod:        60,
				Period:                   10,
				MitigationTimeoutSeconds: 60,
				CountingExpression:       `(http.response.headers["x-tuist-public"][0] eq "1")`,
			},
		},
	}
}

// TestReconcile_ReadOnly_ProposesCreateWithoutWriting proves the safe
// default: a fresh CR whose spec would create a rule reports a
// "would create" plan to status.proposedChanges but issues no Add.
func TestReconcile_ReadOnly_ProposesCreateWithoutWriting(t *testing.T) {
	cr := sampleActiveCR("uid-ro-abc")
	cr.Spec.Mode = cfv1alpha1.ReconcileModeReadOnly
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1"}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 0 || cf.updateCalls != 0 || cf.createCalls != 0 {
		t.Fatalf("read_only must not write: add=%d update=%d createRS=%d", cf.addCalls, cf.updateCalls, cf.createCalls)
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Status.Mode != cfv1alpha1.ReconcileModeReadOnly {
		t.Errorf("status.mode = %q, want read_only", got.Status.Mode)
	}
	if got.Status.ProposedChanges == "" {
		t.Error("expected status.proposedChanges to be populated in read_only mode")
	}
}

// TestReconcile_Paused_SkipsEntirely confirms Paused halts the loop
// without any Cloudflare calls at all — not even a GET.
func TestReconcile_Paused_SkipsEntirely(t *testing.T) {
	cr := sampleActiveCR("uid-paused-abc")
	cr.Spec.Paused = true
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1"}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.getCalls != 0 || cf.addCalls != 0 || cf.updateCalls != 0 {
		t.Fatalf("paused must not call CF: get=%d add=%d update=%d", cf.getCalls, cf.addCalls, cf.updateCalls)
	}
}

// TestReconcile_RefuseCreateWithoutFlag guards the double-negative
// gate: adopt=nil + createNewRule=false must refuse to create,
// preventing an accidental `kubectl apply` from spawning duplicates
// alongside a dashboard-managed rule.
func TestReconcile_RefuseCreateWithoutFlag(t *testing.T) {
	cr := sampleActiveCR("uid-refuse-abc")
	cr.Spec.CreateNewRule = false
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1"}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	_, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}})
	if err == nil {
		t.Fatal("expected reconcile to refuse")
	}
	if cf.addCalls != 0 {
		t.Fatalf("must not add rule when refusing: %d", cf.addCalls)
	}
}

// TestReconcile_Adopt_ZeroChangeIsNoop is the flagship adoption test:
// the CR pins an existing rule id whose live config already matches
// the CR spec (in the fields the CR sets); no update fires.
func TestReconcile_Adopt_ZeroChangeIsNoop(t *testing.T) {
	cr := sampleActiveCR("uid-adopt-noop")
	cr.Spec.Adopt = &cfv1alpha1.AdoptRule{RuleID: "dashboard-rule-1"}
	cr.Spec.CreateNewRule = false
	cr.Finalizers = []string{finalizer}

	// Live rule matches everything the CR would render, plus an
	// extra hypothetical field Cloudflare stores that the operator
	// does not model. mergeAdopted keeps that field verbatim.
	desired := renderRule(cr, ruleRef(cr))
	live := desired
	live.ID = "dashboard-rule-1"
	// Force a hypothetical extra field in RateLimit via a different
	// pointer instance while keeping the values identical.
	rl := *desired.RateLimit
	live.RateLimit = &rl

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{live}}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 0 || cf.updateCalls != 0 {
		t.Fatalf("adoption of matching rule must be a no-op: add=%d update=%d", cf.addCalls, cf.updateCalls)
	}
}

// TestReconcile_Adopt_MissingIDFails proves an adoption pointing at
// an id Cloudflare does not have fails loudly rather than silently
// creating a new rule.
func TestReconcile_Adopt_MissingIDFails(t *testing.T) {
	cr := sampleActiveCR("uid-adopt-miss")
	cr.Spec.Adopt = &cfv1alpha1.AdoptRule{RuleID: "does-not-exist"}
	cr.Spec.CreateNewRule = false
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1"}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err == nil {
		t.Fatal("expected adoption to fail on missing rule id")
	}
	if cf.addCalls != 0 {
		t.Fatalf("must not create when adoption target is missing: %d", cf.addCalls)
	}
}

// TestReconcile_Active_CreatesRuleWhenMissing keeps the active create
// path covered; requires createNewRule=true (already set in
// sampleActiveCR).
func TestReconcile_Active_CreatesRuleWhenMissing(t *testing.T) {
	cr := sampleActiveCR("uid-create-abc")
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1"}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 1 {
		t.Fatalf("expected 1 AddRule, got %d", cf.addCalls)
	}
}

// TestReconcile_RetainOnDelete_LeavesRuleAlone proves the delete
// path honours retainOnDelete=true: finalizer drops, no CF delete.
func TestReconcile_RetainOnDelete_LeavesRuleAlone(t *testing.T) {
	cr := sampleActiveCR("uid-retain-abc")
	cr.Spec.RetainOnDelete = true
	cr.Finalizers = []string{finalizer}
	now := metav1.NewTime(time.Now().UTC())
	cr.DeletionTimestamp = &now

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{{ID: "r1", Ref: ruleRef(cr)}}}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if len(cf.deletedRules) != 0 {
		t.Errorf("retainOnDelete=true must not delete on Cloudflare: %v", cf.deletedRules)
	}
}

// TestReconcile_DeleteUsesManagedZoneID guards the regression Marek
// reproduced: even if spec.zoneId is mutated (before CEL locks it)
// the delete must fire against status.managedZoneId, not spec.zoneId,
// so the rule cannot be orphaned.
func TestReconcile_DeleteUsesManagedZoneID(t *testing.T) {
	cr := sampleActiveCR("uid-zone-orphan")
	cr.Spec.RetainOnDelete = false
	cr.Spec.ZoneID = "new-zone" // pretend zoneId has been mutated
	cr.Status.ManagedZoneID = "original-zone"
	cr.Finalizers = []string{finalizer}
	now := metav1.NewTime(time.Now().UTC())
	cr.DeletionTimestamp = &now

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()

	// Assert that GetPhaseRuleset is called with the ORIGINAL zone,
	// not the mutated one, by having the fake capture the zone.
	var seenZone string
	cf := &fakeCFCapturing{fakeCF: fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{{ID: "r1", Ref: ruleRef(cr)}}}}, seen: &seenZone}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if seenZone != "original-zone" {
		t.Fatalf("delete must use managedZoneId (original-zone), got %q", seenZone)
	}
}

// TestReconcile_ReadOnly_Delete_DoesNotDelete confirms read_only
// covers the delete path too — no Cloudflare delete even when
// retainOnDelete is false.
func TestReconcile_ReadOnly_Delete_DoesNotDelete(t *testing.T) {
	cr := sampleActiveCR("uid-ro-del-abc")
	cr.Spec.Mode = cfv1alpha1.ReconcileModeReadOnly
	cr.Spec.RetainOnDelete = false
	cr.Finalizers = []string{finalizer}
	now := metav1.NewTime(time.Now().UTC())
	cr.DeletionTimestamp = &now

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-1", Rules: []cloudflare.Rule{{ID: "r1", Ref: ruleRef(cr)}}}}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if len(cf.deletedRules) != 0 {
		t.Errorf("read_only must not delete on CF: %v", cf.deletedRules)
	}
}

// TestReconcile_AddsFinalizer confirms the first reconcile of a CR
// without the finalizer sets it and returns without hitting CF.
func TestReconcile_AddsFinalizer(t *testing.T) {
	cr := sampleActiveCR("uid-finalizer-abc")

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.getCalls != 0 {
		t.Fatalf("must not call CF before finalizer is set, got %d", cf.getCalls)
	}
	got := &cfv1alpha1.CloudflareRateLimit{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if !containsFinalizer(got.Finalizers, finalizer) {
		t.Errorf("expected finalizer %q on CR, got %v", finalizer, got.Finalizers)
	}
}

// TestMergeAdopted_PreservesUnmodeledFields verifies the adoption
// merge keeps anything the operator does not touch (represented here
// as ActionParameters on a rate-limit rule, even though rate-limit
// rules don't typically use it; the field exercises the code path).
func TestMergeAdopted_PreservesUnmodeledFields(t *testing.T) {
	base := cloudflare.Rule{
		ID:               "existing",
		Action:           "log",
		Expression:       "true",
		Description:      "was here",
		Enabled:          true,
		ActionParameters: json.RawMessage(`{"cf_only":"leave-me"}`),
	}
	desired := cloudflare.Rule{
		Ref:         "cfrl_x",
		Action:      "managed_challenge",
		Expression:  `(http.request.method eq "GET")`,
		Description: "op says so",
		Enabled:     true,
	}
	got := mergeAdopted(base, desired)
	if got.Action != desired.Action {
		t.Errorf("action not overridden: %s", got.Action)
	}
	if got.Ref != desired.Ref {
		t.Errorf("ref not set: %s", got.Ref)
	}
	if string(got.ActionParameters) != `{"cf_only":"leave-me"}` {
		t.Errorf("unmodeled action_parameters lost: %s", got.ActionParameters)
	}
}

// TestApplyPlan_ErrPropagates confirms a Cloudflare API error on
// AddRule surfaces up (so status carries the reason on retry).
func TestApplyPlan_ErrPropagates(t *testing.T) {
	cr := sampleActiveCR("uid-err-abc")
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{
		ruleset: &cloudflare.Ruleset{ID: "rs-1"},
		addRule: func(cloudflare.Rule) (*cloudflare.Ruleset, error) { return nil, errors.New("boom") },
	}
	r := &CloudflareRateLimitReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err == nil {
		t.Fatal("expected reconcile to return the API error")
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

// fakeCFCapturing wraps fakeCF and captures the zoneID passed to
// GetPhaseRuleset — used by TestReconcile_DeleteUsesManagedZoneID.
type fakeCFCapturing struct {
	fakeCF
	seen *string
}

func (f *fakeCFCapturing) GetPhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error) {
	if f.seen != nil {
		*f.seen = zoneID
	}
	return f.fakeCF.GetPhaseRuleset(ctx, zoneID, phase)
}
