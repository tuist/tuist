package controllers

import (
	"context"
	"encoding/json"
	"testing"

	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// phaseRecordingCF records which ruleset phases the reconciler reads
// and creates, so a cache rule landing in another phase fails a test.
type phaseRecordingCF struct {
	fakeCF
	phases []string
}

func (f *phaseRecordingCF) GetPhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error) {
	f.phases = append(f.phases, phase)
	return f.fakeCF.GetPhaseRuleset(ctx, zoneID, phase)
}

func (f *phaseRecordingCF) CreatePhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error) {
	f.phases = append(f.phases, phase)
	return f.fakeCF.CreatePhaseRuleset(ctx, zoneID, phase)
}

func sampleCacheRule(uid string) *cfv1alpha1.CloudflareCacheRule {
	return &cfv1alpha1.CloudflareCacheRule{
		ObjectMeta: metaWithUID("luft-work-assets", uid),
		Spec: cfv1alpha1.CloudflareCacheRuleSpec{
			ZoneID:        "zone-luft",
			Description:   "Cache luft.work's hashed assets",
			Expression:    `(starts_with(http.request.uri.path, "/assets/"))`,
			Cache:         true,
			EdgeTTL:       &cfv1alpha1.CacheTTL{Mode: "respect_origin"},
			Mode:          cfv1alpha1.ReconcileModeActive,
			CreateNewRule: true,
		},
	}
}

func reconcileCacheRule(t *testing.T, cr *cfv1alpha1.CloudflareCacheRule, cf RulesetAPI) {
	t.Helper()
	cr.Finalizers = []string{finalizer}
	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	r := &CloudflareCacheRuleReconciler{Client: kClient, Scheme: scheme, CF: cf}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
}

func TestCacheRuleCreatesSetCacheSettingsRuleInCachePhase(t *testing.T) {
	cr := sampleCacheRule("uid-create")
	cr.Spec.BrowserTTL = &cfv1alpha1.CacheTTL{Mode: "override_origin", Default: ptr(int64(60))}
	cf := &phaseRecordingCF{fakeCF: fakeCF{createRS: &cloudflare.Ruleset{ID: "cache-ruleset"}}}

	reconcileCacheRule(t, cr, cf)

	for _, phase := range cf.phases {
		if phase != cloudflare.CacheSettingsPhase {
			t.Fatalf("touched phase %q, want only %q", phase, cloudflare.CacheSettingsPhase)
		}
	}
	if cf.createCalls != 1 || cf.addCalls != 1 {
		t.Fatalf("create=%d add=%d, want a new ruleset and one rule", cf.createCalls, cf.addCalls)
	}
	added := cf.lastAdded
	if added.Action != "set_cache_settings" {
		t.Errorf("action = %q, want set_cache_settings", added.Action)
	}
	var got map[string]any
	if err := json.Unmarshal(added.ActionParameters, &got); err != nil {
		t.Fatalf("decode action_parameters: %v", err)
	}
	want := map[string]any{
		"cache":       true,
		"edge_ttl":    map[string]any{"mode": "respect_origin"},
		"browser_ttl": map[string]any{"mode": "override_origin", "default": float64(60)},
	}
	if b1, b2 := mustJSON(got), mustJSON(want); b1 != b2 {
		t.Errorf("action_parameters = %s, want %s", b1, b2)
	}
}

func TestCacheRuleReadOnlyDoesNotWrite(t *testing.T) {
	cr := sampleCacheRule("uid-read-only")
	cr.Spec.Mode = cfv1alpha1.ReconcileModeReadOnly
	cf := &phaseRecordingCF{fakeCF: fakeCF{createRS: &cloudflare.Ruleset{ID: "cache-ruleset"}}}

	reconcileCacheRule(t, cr, cf)

	if cf.createCalls != 0 || cf.addCalls != 0 || cf.updateCalls != 0 {
		t.Fatalf("read_only must not write: create=%d add=%d update=%d", cf.createCalls, cf.addCalls, cf.updateCalls)
	}
}

// A dashboard edit to the TTL mode is drift the operator corrects,
// while a rule already matching the CR is left alone.
func TestCacheRuleCorrectsTTLDriftOnly(t *testing.T) {
	cr := sampleCacheRule("uid-drift")
	desired := renderCacheRule(cr, cacheRuleRef(cr))

	inSync := desired
	inSync.ID = "rule-1"
	cf := &phaseRecordingCF{fakeCF: fakeCF{ruleset: &cloudflare.Ruleset{ID: "cache-ruleset", Rules: []cloudflare.Rule{inSync}}}}
	reconcileCacheRule(t, sampleCacheRule("uid-drift"), cf)
	if cf.updateCalls != 0 || cf.addCalls != 0 {
		t.Fatalf("in-sync rule written: update=%d add=%d", cf.updateCalls, cf.addCalls)
	}

	drifted := desired
	drifted.ID = "rule-1"
	drifted.ActionParameters = json.RawMessage(`{"cache":true,"edge_ttl":{"mode":"bypass_by_default"}}`)
	cf = &phaseRecordingCF{fakeCF: fakeCF{ruleset: &cloudflare.Ruleset{ID: "cache-ruleset", Rules: []cloudflare.Rule{drifted}}}}
	reconcileCacheRule(t, sampleCacheRule("uid-drift"), cf)
	if cf.updateCalls != 1 {
		t.Fatalf("update calls = %d, want 1 for TTL drift", cf.updateCalls)
	}
	if !actionParametersEqual(cf.lastUpdated.ActionParameters, desired.ActionParameters) {
		t.Errorf("update sent %s, want %s", cf.lastUpdated.ActionParameters, desired.ActionParameters)
	}
}

func ptr[T any](v T) *T { return &v }

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}
