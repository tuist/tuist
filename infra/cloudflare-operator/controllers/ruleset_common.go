package controllers

import (
	"context"
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

// rulesetRuleDiffers compares only the fields the operator sets. It
// diffs Rule payloads the reconcilers hand it, treating server-side
// bookkeeping fields (ID, Version, LastUpdated) as noise so a
// semantically equal rule doesn't cause a needless PATCH on every
// resync.
func rulesetRuleDiffers(a, b *cloudflare.Rule) bool {
	if a == nil || b == nil {
		return a != b
	}
	if a.Action != b.Action ||
		a.Expression != b.Expression ||
		a.Description != b.Description ||
		a.Enabled != b.Enabled ||
		a.Ref != b.Ref {
		return true
	}
	if !reflect.DeepEqual(a.RateLimit, b.RateLimit) {
		return true
	}
	return !bytesEqual(a.ActionParameters, b.ActionParameters)
}

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
