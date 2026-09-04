package controllers

import (
	"testing"

	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// TestRulesetRuleDiffers_KeyOrderNotDrift confirms two payloads with
// the same key set but different serialisation order are equal, so
// the reconciler does not PATCH on every resync just because
// Cloudflare re-ordered keys or added whitespace.
func TestRulesetRuleDiffers_KeyOrderNotDrift(t *testing.T) {
	desired := &cloudflare.Rule{
		Ref:              "cfrl_abc",
		Action:           "block",
		Enabled:          true,
		ActionParameters: []byte(`{"a":1,"b":2}`),
	}
	existing := &cloudflare.Rule{
		Ref:              desired.Ref,
		Action:           desired.Action,
		Enabled:          true,
		ActionParameters: []byte(`{"b":2,"a":1}`),
	}
	if rulesetRuleDiffers(existing, desired) {
		t.Fatal("expected no drift when only key order differs")
	}
}

// TestRulesetRuleDiffers_MissingKeyIsDrift is the regression Marek
// reproduced: removing a field from the CR must be treated as
// drift, otherwise Cloudflare keeps the old value forever.
func TestRulesetRuleDiffers_MissingKeyIsDrift(t *testing.T) {
	desired := &cloudflare.Rule{
		Ref:              "cfrl_abc",
		Action:           "block",
		Enabled:          true,
		ActionParameters: []byte(`{"a":1}`),
	}
	existing := &cloudflare.Rule{
		Ref:              desired.Ref,
		Action:           desired.Action,
		Enabled:          true,
		ActionParameters: []byte(`{"a":1,"b":2}`),
	}
	if !rulesetRuleDiffers(existing, desired) {
		t.Fatal("expected drift when desired dropped a key")
	}
}

// TestRulesetRuleDiffers_ExtraDesiredKeyIsDrift covers the other
// direction: a key present in desired but missing in existing (a
// create-in-progress).
func TestRulesetRuleDiffers_ExtraDesiredKeyIsDrift(t *testing.T) {
	desired := &cloudflare.Rule{
		Ref:              "cfrl_abc",
		Action:           "block",
		Enabled:          true,
		ActionParameters: []byte(`{"a":1,"b":2}`),
	}
	existing := &cloudflare.Rule{
		Ref:              desired.Ref,
		Action:           desired.Action,
		Enabled:          true,
		ActionParameters: []byte(`{"a":1}`),
	}
	if !rulesetRuleDiffers(existing, desired) {
		t.Fatal("expected drift when desired has a new key")
	}
}

// TestActionParametersEqual_BothEmpty is the degenerate case: rate-
// limit rules do not set action_parameters, so we exercise both
// sides empty explicitly.
func TestActionParametersEqual_BothEmpty(t *testing.T) {
	if !actionParametersEqual(nil, nil) {
		t.Fatal("both nil should be equal")
	}
	if !actionParametersEqual([]byte(""), nil) {
		t.Fatal("empty vs nil should be equal")
	}
}
