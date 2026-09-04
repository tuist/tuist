package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"

	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// RulesetAPI is the subset of the Cloudflare client the rate-limit,
// cache-rule, and WAF-custom-rule reconcilers all use. Every method is
// phase-agnostic; the reconciler passes the phase it manages.
type RulesetAPI interface {
	GetPhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error)
	CreatePhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error)
	AddRule(ctx context.Context, zoneID, rulesetID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	UpdateRule(ctx context.Context, zoneID, rulesetID, ruleID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	DeleteRule(ctx context.Context, zoneID, rulesetID, ruleID string) error
}

// ensurePhaseRuleset returns the zone's entrypoint ruleset for phase,
// creating it if Cloudflare has none yet. Kept out of individual
// reconcilers because the create-on-first-rule contract is the same
// for every ruleset phase.
func ensurePhaseRuleset(ctx context.Context, api RulesetAPI, zoneID, phase string) (*cloudflare.Ruleset, error) {
	rs, err := api.GetPhaseRuleset(ctx, zoneID, phase)
	if err != nil {
		return nil, fmt.Errorf("get %s ruleset: %w", phase, err)
	}
	if rs != nil {
		return rs, nil
	}
	created, err := api.CreatePhaseRuleset(ctx, zoneID, phase)
	if err != nil {
		return nil, fmt.Errorf("create %s ruleset: %w", phase, err)
	}
	return created, nil
}

// rulesetRuleDiffers compares only the fields the operator sets on
// `existing` against `desired`. Server-side bookkeeping fields (ID,
// Version, LastUpdated) are ignored, and `action_parameters` is
// compared as a subset: every key/value in desired must appear
// equal-valued in existing, but Cloudflare-added defaults or fields
// we don't manage don't count as drift. That means the reconciler
// doesn't loop-PATCH cache rules whose JSON key order or server-side
// defaults differ from the freshly-marshaled Go map.
func rulesetRuleDiffers(existing, desired *cloudflare.Rule) bool {
	if existing == nil || desired == nil {
		return existing != desired
	}
	if existing.Action != desired.Action ||
		existing.Expression != desired.Expression ||
		existing.Description != desired.Description ||
		existing.Enabled != desired.Enabled ||
		existing.Ref != desired.Ref {
		return true
	}
	if !reflect.DeepEqual(existing.RateLimit, desired.RateLimit) {
		return true
	}
	return !jsonSubsetMatches(existing.ActionParameters, desired.ActionParameters)
}

// jsonSubsetMatches reports whether every key/value pair in `subset`
// also appears in `full`, ignoring keys `full` carries that `subset`
// does not. Both sides are parsed to Go values so key order and
// whitespace don't count as drift.
func jsonSubsetMatches(full, subset json.RawMessage) bool {
	if len(subset) == 0 {
		return true
	}
	var subsetV any
	if err := json.Unmarshal(subset, &subsetV); err != nil {
		// If the desired side is unparseable, treat as drift so we
		// re-render and surface the error on the next reconcile.
		return false
	}
	if len(full) == 0 {
		// Desired says something, live says nothing. Drift.
		return false
	}
	var fullV any
	if err := json.Unmarshal(full, &fullV); err != nil {
		return false
	}
	return matchesSubset(fullV, subsetV)
}

// matchesSubset walks two decoded JSON values and returns true when
// `subset` is present-and-equal inside `full`. Objects are compared
// as maps where extra keys in `full` are ignored; arrays are compared
// pairwise by index; scalars by value.
func matchesSubset(full, subset any) bool {
	switch s := subset.(type) {
	case map[string]any:
		f, ok := full.(map[string]any)
		if !ok {
			return false
		}
		for k, v := range s {
			fv, present := f[k]
			if !present || !matchesSubset(fv, v) {
				return false
			}
		}
		return true
	case []any:
		f, ok := full.([]any)
		if !ok || len(f) != len(s) {
			return false
		}
		for i := range s {
			if !matchesSubset(f[i], s[i]) {
				return false
			}
		}
		return true
	default:
		return reflect.DeepEqual(full, subset)
	}
}
