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

func sampleWAFRule(uid string) *cfv1alpha1.CloudflareWAFCustomRule {
	enabled := true
	return &cfv1alpha1.CloudflareWAFCustomRule{
		ObjectMeta: metaWithUID("auth-managed-challenge", uid),
		Spec: cfv1alpha1.CloudflareWAFCustomRuleSpec{
			ZoneID:      "zone-abc",
			Description: "Managed Challenge on interactive auth-form POSTs",
			Expression:  `http.request.method eq "POST" and http.request.uri.path eq "/users/log_in"`,
			Action:      "managed_challenge",
			Enabled:     &enabled,
		},
	}
}

func TestWAFRuleReconcile_Create(t *testing.T) {
	cr := sampleWAFRule("uid-waf-abc")
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-waf", Phase: cloudflare.CustomFirewallPhase}}

	r := &CloudflareWAFCustomRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 1 {
		t.Fatalf("expected 1 AddRule, got %d", cf.addCalls)
	}
	got := cf.ruleset.Rules[0]
	if got.Action != "managed_challenge" {
		t.Errorf("action = %s", got.Action)
	}
}

func TestWAFRuleReconcile_UpdatesWhenSpecChanges(t *testing.T) {
	cr := sampleWAFRule("uid-waf-update-abc")
	cr.Finalizers = []string{finalizer}
	ref := wafRuleRef(cr)

	live := renderWAFRule(cr, ref)
	live.ID = "existing-id"
	live.Action = "log"

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-waf", Rules: []cloudflare.Rule{live}}}

	r := &CloudflareWAFCustomRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 1 {
		t.Fatalf("expected 1 UpdateRule call, got %d", cf.updateCalls)
	}
}
