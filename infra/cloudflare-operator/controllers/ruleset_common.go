package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"time"

	"github.com/go-logr/logr"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

const (
	defaultResyncInterval = 5 * time.Minute

	// finalizer runs the Cloudflare-side delete when a CR is removed
	// so the live rule follows the CR through git deletions. Applied
	// only by the Ruleset-shaped reconcilers; settings-shaped CRDs
	// deliberately leave settings in place on delete.
	finalizer = "cloudflare.tuist.dev/finalizer"
)

// RulesetStatusWriter is what every ruleset-shaped CRD's status
// implements so the shared reconciler can write into it without
// caring which concrete type it is.
type RulesetStatusWriter interface {
	SetRulesetStatus(ref, rulesetID, ruleID, message string, observedGeneration int64, now *metav1.Time)
}

// resyncOrDefault returns d if positive, else the shared default.
func resyncOrDefault(d time.Duration) time.Duration {
	if d > 0 {
		return d
	}
	return defaultResyncInterval
}

// ensureFinalizer adds the shared finalizer to cr if missing and
// persists the update. Returns (added, error). Add=true means the
// caller should return a fresh reconcile — the Update triggered one.
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
// persists the update. Used at the tail of a delete reconcile.
func removeFinalizerAndPersist(ctx context.Context, c client.Client, cr client.Object) error {
	controllerutil.RemoveFinalizer(cr, finalizer)
	if err := c.Update(ctx, cr); err != nil {
		return fmt.Errorf("remove finalizer: %w", err)
	}
	return nil
}

// writeRulesetStatus is a small wrapper that stamps the shared
// (ref/rulesetID/ruleID/message/generation/timestamp) fields via the
// writer and PATCHes the CR's status subresource. Not-found on the CR
// itself is treated as gone rather than an error.
func writeRulesetStatus(
	ctx context.Context,
	c client.Client,
	cr client.Object,
	writer RulesetStatusWriter,
	ref, rulesetID, ruleID, message string,
	generation int64,
) error {
	now := metav1.NewTime(time.Now().UTC())
	patch := client.MergeFrom(cr.DeepCopyObject().(client.Object))
	writer.SetRulesetStatus(ref, rulesetID, ruleID, message, generation, &now)
	if err := c.Status().Patch(ctx, cr, patch); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("patch status: %w", err)
	}
	return nil
}

// finishRulesetReconcile writes the status and returns a Result that
// requeues after the shared resync interval. Kept so per-reconciler
// call sites read as a single line.
func finishRulesetReconcile(
	ctx context.Context,
	c client.Client,
	cr client.Object,
	writer RulesetStatusWriter,
	ref, rulesetID, ruleID, message string,
	generation int64,
	resync time.Duration,
) (ctrl.Result, error) {
	if err := writeRulesetStatus(ctx, c, cr, writer, ref, rulesetID, ruleID, message, generation); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: resyncOrDefault(resync)}, nil
}

// RulesetReconcileOutcome is what a shared ruleset reconcile pass
// hands back to a per-CRD reconciler so it can write the CR status.
type RulesetReconcileOutcome struct {
	RulesetID string
	RuleID    string
	Message   string
}

// driveRulesetReconcile runs the ensure-ruleset + create/update/no-op
// pass shared by every Ruleset-shaped CRD (rate limit, cache rule,
// WAF custom rule). Concrete reconcilers own the CR fetch, finalizer
// handling, and status write; the phase-specific rule rendering; and
// the resync interval. Everything in between lives here.
func driveRulesetReconcile(
	ctx context.Context,
	api RulesetAPI,
	log logr.Logger,
	zoneID, phase, kindLabel string,
	desired cloudflare.Rule,
) (RulesetReconcileOutcome, error) {
	rs, err := ensurePhaseRuleset(ctx, api, zoneID, phase)
	if err != nil {
		return RulesetReconcileOutcome{}, err
	}
	out := RulesetReconcileOutcome{RulesetID: rs.ID}
	existing := cloudflare.FindRuleByRef(rs, desired.Ref)
	switch {
	case existing == nil:
		updated, err := api.AddRule(ctx, zoneID, rs.ID, desired)
		if err != nil {
			return out, fmt.Errorf("add %s: %w", kindLabel, err)
		}
		if created := cloudflare.FindRuleByRef(updated, desired.Ref); created != nil {
			out.RuleID = created.ID
		}
		out.Message = "created"
		log.Info("created "+kindLabel, "rulesetId", rs.ID, "ruleId", out.RuleID, "ref", desired.Ref)
	case rulesetRuleDiffers(existing, &desired):
		updated, err := api.UpdateRule(ctx, zoneID, rs.ID, existing.ID, desired)
		if err != nil {
			out.RuleID = existing.ID
			return out, fmt.Errorf("update %s: %w", kindLabel, err)
		}
		if patched := cloudflare.FindRuleByRef(updated, desired.Ref); patched != nil {
			out.RuleID = patched.ID
		}
		out.Message = "updated"
		log.Info("updated "+kindLabel, "rulesetId", rs.ID, "ruleId", out.RuleID, "ref", desired.Ref)
	default:
		out.RuleID = existing.ID
		out.Message = "in sync"
	}
	return out, nil
}

// driveRulesetDelete removes a rule by ref. Missing ruleset or
// missing rule is treated as already-gone. Caller drops the CR
// finalizer.
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
