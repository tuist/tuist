package controllers

import (
	"context"
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
