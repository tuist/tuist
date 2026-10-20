package controllers

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

func sampleCustomRule(uid string) *cfv1alpha1.CloudflareCustomRule {
	enabled := true
	return &cfv1alpha1.CloudflareCustomRule{
		ObjectMeta: metaWithUID("bot-protection", uid),
		Spec: cfv1alpha1.CloudflareCustomRuleSpec{
			ZoneID:         "zone-abc",
			Description:    "Bot protection",
			Expression:     `starts_with(http.request.uri.path, "/public") and not cf.client.bot`,
			Action:         "managed_challenge",
			Enabled:        &enabled,
			Mode:           cfv1alpha1.ReconcileModeActive,
			CreateNewRule:  true,
			RetainOnDelete: false,
		},
	}
}

func TestCustomRuleReconcileReadOnlyDoesNotWrite(t *testing.T) {
	cr := sampleCustomRule("uid-read-only")
	cr.Spec.Mode = cfv1alpha1.ReconcileModeReadOnly
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "custom-ruleset"}}
	reconciler := &CloudflareCustomRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := reconciler.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 0 || cf.updateCalls != 0 || cf.createCalls != 0 {
		t.Fatalf("read_only must not write: add=%d update=%d create=%d", cf.addCalls, cf.updateCalls, cf.createCalls)
	}
}

// TestCustomRuleCreateSkipRule_SendsPhases proves the skip action
// support: a create-new CR with action=skip and phases set sends the
// wire payload Cloudflare expects for a Super Bot Fight Mode bypass on
// the matched paths (see
// https://developers.cloudflare.com/waf/custom-rules/skip/). This is
// the mechanism that lets us keep SBFM on for the browser dashboard
// while exempting the CLI and machine-facing APIs.
func TestCustomRuleCreateSkipRule_SendsPhases(t *testing.T) {
	cr := sampleCustomRule("uid-skip-create")
	cr.Spec.Mode = cfv1alpha1.ReconcileModeActive
	cr.Spec.Action = "skip"
	cr.Spec.Description = "Skip SBFM on machine/CLI paths"
	cr.Spec.Expression = `starts_with(http.request.uri.path, "/api/")`
	cr.Spec.ActionParameters = &cfv1alpha1.ActionParameters{Phases: []string{"http_request_sbfm"}}
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "custom-ruleset"}}
	r := &CloudflareCustomRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 1 {
		t.Fatalf("add calls = %d, want 1", cf.addCalls)
	}
	added := cf.lastAdded
	if added.Action != "skip" {
		t.Errorf("action = %q, want skip", added.Action)
	}
	if len(added.ActionParameters) == 0 {
		t.Fatalf("action_parameters missing from wire body: %+v", added)
	}
	var got map[string]any
	if err := json.Unmarshal(added.ActionParameters, &got); err != nil {
		t.Fatalf("decode action_parameters: %v", err)
	}
	phases, ok := got["phases"].([]any)
	if !ok || len(phases) != 1 || phases[0] != "http_request_sbfm" {
		t.Fatalf("phases wire body = %v, want [http_request_sbfm]", got["phases"])
	}
}

// TestCustomRuleAdoptSkipRule_DetectsPhasesDrift proves adopt-mode drift
// detection notices a change to the skip rule's action_parameters
// (e.g. someone flipped the phase in the dashboard), which is the
// only field that changes on a `skip` rule outside of expression.
func TestCustomRuleAdoptSkipRule_DetectsPhasesDrift(t *testing.T) {
	cr := sampleCustomRule("uid-skip-adopt-drift")
	cr.Spec.Mode = cfv1alpha1.ReconcileModeActive
	cr.Spec.Action = "skip"
	cr.Spec.Description = "Skip SBFM on machine/CLI paths"
	cr.Spec.Expression = `starts_with(http.request.uri.path, "/api/")`
	cr.Spec.ActionParameters = &cfv1alpha1.ActionParameters{Phases: []string{"http_request_sbfm"}}
	cr.Spec.Adopt = &cfv1alpha1.AdoptRule{RuleID: "dashboard-skip"}
	cr.Spec.CreateNewRule = false
	cr.Finalizers = []string{finalizer}

	live := cloudflare.Rule{
		ID:               "dashboard-skip",
		Ref:              "dashboard-skip",
		Description:      "Skip SBFM on machine/CLI paths",
		Expression:       `starts_with(http.request.uri.path, "/api/")`,
		Action:           "skip",
		Enabled:          true,
		ActionParameters: json.RawMessage(`{"phases":["http_ratelimit"]}`), // wrong phase
	}
	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "custom-ruleset", Rules: []cloudflare.Rule{live}}}
	r := &CloudflareCustomRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 1 {
		t.Fatalf("update calls = %d, want 1 (phase drift should be corrected)", cf.updateCalls)
	}
	sent := cf.lastUpdated
	if !strings.Contains(string(sent.ActionParameters), "http_request_sbfm") {
		t.Errorf("action_parameters wire body missing corrected phase: %s", sent.ActionParameters)
	}
}

func TestCustomRuleReconcileUpdatesAdoptedRuleAndPreservesRef(t *testing.T) {
	cr := sampleCustomRule("uid-adopt")
	cr.Spec.Adopt = &cfv1alpha1.AdoptRule{RuleID: "dashboard-rule"}
	cr.Spec.CreateNewRule = false
	cr.Finalizers = []string{finalizer}

	live := cloudflare.Rule{
		ID:          "dashboard-rule",
		Ref:         "dashboard-rule",
		Description: "Bot protection",
		Expression:  `starts_with(http.request.uri.path, "/public")`,
		Action:      "managed_challenge",
		Enabled:     true,
	}
	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "custom-ruleset", Rules: []cloudflare.Rule{live}}}
	reconciler := &CloudflareCustomRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := reconciler.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 1 {
		t.Fatalf("update calls = %d, want 1", cf.updateCalls)
	}
	got := cf.ruleset.Rules[0]
	if got.Ref != "dashboard-rule" {
		t.Errorf("adopted ref = %q, want dashboard-rule", got.Ref)
	}
	if got.Expression != cr.Spec.Expression {
		t.Errorf("expression = %q, want %q", got.Expression, cr.Spec.Expression)
	}
}
