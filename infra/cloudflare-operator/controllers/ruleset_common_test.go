package controllers

import (
	"testing"

	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// TestRulesetRuleDiffers_IgnoresServerAddedFields is the regression
// test for the cache-rule reconcile-loop bug: Cloudflare returns
// action_parameters with keys we did not set (server-added defaults,
// reordered keys). Those must not count as drift, otherwise the
// reconciler PATCHes forever on every resync interval.
func TestRulesetRuleDiffers_IgnoresServerAddedFields(t *testing.T) {
	desired := &cloudflare.Rule{
		Ref:         "cfcr_abc",
		Action:      "set_cache_settings",
		Expression:  `starts_with(http.request.uri.path, "/docs")`,
		Description: "docs",
		Enabled:     true,
		ActionParameters: []byte(`{
			"cache": true,
			"edge_ttl": {"mode": "override_origin", "default": 300}
		}`),
	}
	existing := &cloudflare.Rule{
		ID:          "server-id",
		Ref:         desired.Ref,
		Action:      desired.Action,
		Expression:  desired.Expression,
		Description: desired.Description,
		Enabled:     desired.Enabled,
		// Same semantic value, different key order plus a server-added key.
		ActionParameters: []byte(`{
			"edge_ttl": {"default": 300, "mode": "override_origin"},
			"cache": true,
			"status_code_ttl": []
		}`),
	}
	if rulesetRuleDiffers(existing, desired) {
		t.Fatal("expected no drift when live has server-added keys and re-ordered fields")
	}
}

// TestRulesetRuleDiffers_DetectsRealDrift confirms the opposite:
// when a field the CR set changed on the live side, that IS drift.
func TestRulesetRuleDiffers_DetectsRealDrift(t *testing.T) {
	desired := &cloudflare.Rule{
		Ref:              "cfcr_abc",
		Action:           "set_cache_settings",
		Enabled:          true,
		ActionParameters: []byte(`{"cache": true, "edge_ttl": {"mode": "override_origin", "default": 300}}`),
	}
	existing := &cloudflare.Rule{
		Ref:              desired.Ref,
		Action:           desired.Action,
		Enabled:          true,
		ActionParameters: []byte(`{"cache": true, "edge_ttl": {"mode": "override_origin", "default": 60}}`),
	}
	if !rulesetRuleDiffers(existing, desired) {
		t.Fatal("expected drift when edge_ttl.default differs")
	}
}

// TestJSONSubsetMatches exercises the subset helper directly.
func TestJSONSubsetMatches(t *testing.T) {
	cases := []struct {
		name   string
		full   string
		subset string
		want   bool
	}{
		{"empty subset matches anything", `{"a":1}`, ``, true},
		{"same object", `{"a":1,"b":2}`, `{"a":1,"b":2}`, true},
		{"reordered", `{"b":2,"a":1}`, `{"a":1,"b":2}`, true},
		{"extra key in full is ok", `{"a":1,"b":2,"c":3}`, `{"a":1,"b":2}`, true},
		{"missing key in full is drift", `{"a":1}`, `{"a":1,"b":2}`, false},
		{"wrong value is drift", `{"a":2}`, `{"a":1}`, false},
		{"nested subset", `{"a":{"x":1,"y":2}}`, `{"a":{"x":1}}`, true},
		{"nested drift", `{"a":{"x":1,"y":2}}`, `{"a":{"x":9}}`, false},
	}
	for _, c := range cases {
		got := jsonSubsetMatches([]byte(c.full), []byte(c.subset))
		if got != c.want {
			t.Errorf("%s: got %v want %v (full=%s subset=%s)", c.name, got, c.want, c.full, c.subset)
		}
	}
}
