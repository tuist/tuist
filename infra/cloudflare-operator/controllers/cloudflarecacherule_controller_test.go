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

func sampleCacheRule(uid string) *cfv1alpha1.CloudflareCacheRule {
	enabled := true
	yes := true
	return &cfv1alpha1.CloudflareCacheRule{
		ObjectMeta: metaWithUID("marketing-and-docs", uid),
		Spec: cfv1alpha1.CloudflareCacheRuleSpec{
			ZoneID:      "zone-abc",
			Description: "Cache marketing + docs at the edge",
			Expression:  `starts_with(http.request.uri.path, "/docs") and http.request.method eq "GET"`,
			Enabled:     &enabled,
			CacheSettings: cfv1alpha1.CacheSettings{
				Cache: &yes,
				EdgeTTL: &cfv1alpha1.EdgeTTL{
					Mode:    "override_origin",
					Default: 300,
				},
			},
		},
	}
}

// TestCacheRuleReconcile_Create exercises the create branch and
// verifies the rendered rule targets the cache-settings phase.
func TestCacheRuleReconcile_Create(t *testing.T) {
	cr := sampleCacheRule("uid-cache-abc")
	cr.Finalizers = []string{finalizer}

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-cache", Phase: cloudflare.CacheSettingsPhase}}

	r := &CloudflareCacheRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 1 {
		t.Fatalf("expected 1 AddRule, got %d", cf.addCalls)
	}
	if len(cf.ruleset.Rules) != 1 {
		t.Fatalf("expected 1 rule in ruleset, got %d", len(cf.ruleset.Rules))
	}
	got := cf.ruleset.Rules[0]
	if got.Action != "set_cache_settings" {
		t.Errorf("action = %s, want set_cache_settings", got.Action)
	}
	if len(got.ActionParameters) == 0 {
		t.Error("expected action_parameters payload on the rule")
	}
}

// TestCacheRuleReconcile_NoOpWhenInSync verifies that a subsequent
// reconcile after a successful sync does not re-issue a PATCH — the
// action-parameters comparison must be byte-stable across renders.
func TestCacheRuleReconcile_NoOpWhenInSync(t *testing.T) {
	cr := sampleCacheRule("uid-cache-sync-abc")
	cr.Finalizers = []string{finalizer}
	ref := cacheRuleRef(cr)

	live, err := renderCacheRule(cr, ref)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	live.ID = "existing-id"

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeCF{ruleset: &cloudflare.Ruleset{ID: "rs-cache", Rules: []cloudflare.Rule{live}}}

	r := &CloudflareCacheRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.addCalls != 0 || cf.updateCalls != 0 {
		t.Fatalf("expected no writes when in sync, got add=%d update=%d", cf.addCalls, cf.updateCalls)
	}
}
