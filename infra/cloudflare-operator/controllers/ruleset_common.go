package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"time"

	"github.com/go-logr/logr"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

const (
	defaultResyncInterval = 5 * time.Minute

	// finalizer runs the Cloudflare-side delete when a CR is removed
	// so the live rule follows the CR through git deletions. Applied
	// by the CloudflareRateLimit reconciler; a settings-shaped CRD
	// would deliberately leave settings in place on delete.
	finalizer = "cloudflare.tuist.dev/finalizer"
)

// RulesetStatusWriter is what every ruleset-shaped CRD's status
// implements so shared helpers can stamp fields uniformly.
type RulesetStatusWriter interface {
	SetRulesetStatus(ref, rulesetID, ruleID, message string, observedGeneration int64, now *metav1.Time)
}

// RulesetAPI is the Cloudflare surface the reconciler needs.
type RulesetAPI interface {
	GetPhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error)
	CreatePhaseRuleset(ctx context.Context, zoneID, phase string) (*cloudflare.Ruleset, error)
	AddRule(ctx context.Context, zoneID, rulesetID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	UpdateRule(ctx context.Context, zoneID, rulesetID, ruleID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	DeleteRule(ctx context.Context, zoneID, rulesetID, ruleID string) error
}

// resyncOrDefault returns d if positive, else the shared default.
func resyncOrDefault(d time.Duration) time.Duration {
	if d > 0 {
		return d
	}
	return defaultResyncInterval
}

// ensureFinalizer adds the shared finalizer to cr if missing and
// persists the update. Returns (added, error). added=true means the
// caller should return without further work — the Update triggered a
// fresh reconcile.
func ensureFinalizer(ctx context.Context, c client.Client, cr client.Object) (bool, error) {
	if controllerutil.ContainsFinalizer(cr, finalizer) {
		return false, nil
	}
	controllerutil.AddFinalizer(cr, finalizer)
	if err := c.Update(ctx, cr); err != nil {
		return false, fmt.Errorf("add finalizer: %w", err)
	}
	return true, nil
}

// removeFinalizerAndPersist drops the shared finalizer from cr and
// persists the update.
func removeFinalizerAndPersist(ctx context.Context, c client.Client, cr client.Object) error {
	controllerutil.RemoveFinalizer(cr, finalizer)
	if err := c.Update(ctx, cr); err != nil {
		return fmt.Errorf("remove finalizer: %w", err)
	}
	return nil
}

// driveRulesetDelete removes a rule by ref. Missing ruleset or
// missing rule is treated as already-gone. Caller drops the CR
// finalizer separately.
func driveRulesetDelete(
	ctx context.Context,
	api RulesetAPI,
	log logr.Logger,
	zoneID, phase, kindLabel, ref string,
) error {
	rs, err := api.GetPhaseRuleset(ctx, zoneID, phase)
	if err != nil {
		return fmt.Errorf("get %s ruleset for delete: %w", phase, err)
	}
	if rs == nil {
		return nil
	}
	existing := cloudflare.FindRuleByRef(rs, ref)
	if existing == nil {
		return nil
	}
	if err := api.DeleteRule(ctx, zoneID, rs.ID, existing.ID); err != nil {
		return fmt.Errorf("delete %s: %w", kindLabel, err)
	}
	log.Info("deleted "+kindLabel, "rulesetId", rs.ID, "ruleId", existing.ID, "ref", ref)
	return nil
}

// rulesetRuleDiffers compares only the fields the operator sets on
// `existing` against `desired`. Server-side bookkeeping (ID, Version,
// LastUpdated) is ignored.
//
// For the rate-limit block the diff is field-by-CR-managed-field: the
// operator manages Characteristics, Period, RequestsPerPeriod,
// MitigationTimeout, CountingExpression, and treats a difference in
// any of those as drift. Fields Cloudflare accepts but the CR does not
// model (RequestsToOrigin, ScorePerPeriod, ScoreResponseHeaderName)
// are ignored on comparison, but round-trip verbatim on the wire so
// an adopted rule keeps them.
//
// `action_parameters` is compared symmetrically: keys present on
// either side but not the other, or with a different value, count as
// drift. That catches "removed a field from CR" (a real regression
// the review reproduced) without flapping on Cloudflare-side key
// ordering.
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
	if !rateLimitManagedEqual(existing.RateLimit, desired.RateLimit) {
		return true
	}
	return !actionParametersEqual(existing.ActionParameters, desired.ActionParameters)
}

// rateLimitManagedEqual returns true iff the CR-managed rate-limit
// fields match. Fields Cloudflare stores that the CR does not model
// are ignored — a dashboard-set RequestsToOrigin does not cause the
// reconciler to think the CR is out of sync.
func rateLimitManagedEqual(a, b *cloudflare.RuleRateLimit) bool {
	if a == nil || b == nil {
		return a == b
	}
	if a.Period != b.Period ||
		a.RequestsPerPeriod != b.RequestsPerPeriod ||
		a.MitigationTimeout != b.MitigationTimeout ||
		a.CountingExpression != b.CountingExpression {
		return false
	}
	return reflect.DeepEqual(a.Characteristics, b.Characteristics)
}

// actionParametersEqual reports whether two action_parameters blobs
// carry the same operator-managed content. It parses both to Go
// values and diffs them symmetrically for object keys, so:
//   - a key present in desired but missing in existing is drift
//     (a create is pending),
//   - a key present in existing but missing in desired is drift
//     (the operator stopped managing it and Cloudflare needs to
//     drop it — otherwise removing a field from a CR would be a
//     silent no-op, which the review flagged as a real regression).
//
// Server-added defaults still show up as drift here. That is the
// price of not maintaining an explicit list of operator-owned keys;
// if that becomes a problem we can add one, but for the rate-limit
// CRD there is no action_parameters block, so this only matters if
// a later CRD reintroduces one.
func actionParametersEqual(a, b json.RawMessage) bool {
	if len(a) == 0 && len(b) == 0 {
		return true
	}
	var av, bv any
	if len(a) > 0 {
		if err := json.Unmarshal(a, &av); err != nil {
			return false
		}
	}
	if len(b) > 0 {
		if err := json.Unmarshal(b, &bv); err != nil {
			return false
		}
	}
	return reflect.DeepEqual(av, bv)
}
