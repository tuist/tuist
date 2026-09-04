// Package controllers holds the reconcilers for the Cloudflare
// operator. The rate-limit reconciler is designed for a safe first
// production rollout:
//
//   - spec.mode defaults to `read_only`: reconciles compute the intended
//     diff, log it, mirror it into status.proposedChanges, but issue no
//     Cloudflare writes. This includes ruleset creation and finalizer
//     cleanup — a CR in read_only mode never touches Cloudflare.
//   - spec.paused halts the reconcile loop entirely; useful as
//     break-glass without editing every field.
//   - spec.adopt.ruleId binds the CR to an existing (e.g. dashboard-
//     created) rule by its Cloudflare id, so the operator manages that
//     rule directly instead of creating a duplicate under its own ref.
//   - spec.createNewRule must be explicitly true for the operator to
//     POST a brand-new rule; the combination of adopt=nil and
//     createNewRule=false is a hard refusal, so an accidental
//     `kubectl apply` cannot spawn a rule alongside a dashboard-managed
//     one.
//   - spec.retainOnDelete (default true) leaves the Cloudflare rule
//     alone on CR deletion. The finalizer drops without a rule delete.
//   - status.managedZoneId records the zone the rule actually lives
//     in; the delete path uses this rather than spec.zoneId so a
//     mutation to spec.zoneId cannot orphan the rule (spec.zoneId is
//     also declared immutable at the CRD level as a belt-and-braces).
package controllers

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"time"

	"github.com/go-logr/logr"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// metav1Now is a thin wrapper so tests can override wall-clock in the
// future without touching every call site.
func metav1Now() metav1.Time { return metav1.NewTime(time.Now().UTC()) }

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareratelimits,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareratelimits/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareratelimits/finalizers,verbs=update

// CloudflareRateLimitReconciler drives one CloudflareRateLimit toward
// its Cloudflare counterpart.
type CloudflareRateLimitReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             RulesetAPI
	ResyncInterval time.Duration
}

func (r *CloudflareRateLimitReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflareratelimit", req.Name)

	cr := &cfv1alpha1.CloudflareRateLimit{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	ref := ruleRef(cr)

	if !cr.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, logger, cr, ref)
	}

	if cr.Spec.Paused {
		logger.V(1).Info("reconcile paused, skipping")
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
	}

	added, err := ensureFinalizer(ctx, r.Client, cr)
	if err != nil {
		return ctrl.Result{}, err
	}
	if added {
		return ctrl.Result{}, nil
	}

	desired := renderRule(cr, ref)
	plan, err := r.planReconcile(ctx, cr, desired)
	if err != nil {
		_ = writeRateLimitStatus(ctx, r.Client, cr, ref, plan.rulesetID, plan.ruleID, err.Error(), "", cr.Generation)
		return ctrl.Result{}, err
	}

	mode := cr.Spec.EffectiveMode()
	if mode == cfv1alpha1.ReconcileModeReadOnly {
		logger.Info("read_only: would "+plan.action, "rulesetId", plan.rulesetID, "ruleId", plan.ruleID, "ref", ref)
		if err := writeRateLimitStatus(ctx, r.Client, cr, ref, plan.rulesetID, plan.ruleID, "read_only: "+plan.action, plan.summary, cr.Generation); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
	}

	if err := r.applyPlan(ctx, logger, cr, desired, plan); err != nil {
		_ = writeRateLimitStatus(ctx, r.Client, cr, ref, plan.rulesetID, plan.ruleID, err.Error(), "", cr.Generation)
		return ctrl.Result{}, err
	}
	if err := writeRateLimitStatus(ctx, r.Client, cr, ref, plan.rulesetID, plan.ruleID, plan.action, "", cr.Generation); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
}

// rateLimitPlan is what planReconcile hands back to the executor.
type rateLimitPlan struct {
	// operation is one of: create, adopt-noop, update, in-sync.
	operation string

	// action is a short label suitable for status.message and logs
	// (e.g. "created", "would create", "updated", "in sync",
	// "adoption failed: rule id not found").
	action string

	// summary is a longer proposed-changes string used only for
	// read_only mode.
	summary string

	rulesetID string
	ruleID    string

	// existing is the live Cloudflare rule when we found one, so the
	// executor doesn't have to re-fetch. nil for creates.
	existing *cloudflare.Rule
}

// planReconcile figures out what the reconciler would do, without
// making any Cloudflare writes past the read-only GET. The output is
// consumed both by read_only mode (to render the plan) and by active
// mode (to execute it).
func (r *CloudflareRateLimitReconciler) planReconcile(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, desired cloudflare.Rule) (rateLimitPlan, error) {
	plan := rateLimitPlan{}
	rs, err := r.CF.GetPhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.RateLimitPhase)
	if err != nil {
		return plan, fmt.Errorf("get ruleset: %w", err)
	}
	if rs == nil {
		// No ruleset yet. In read_only we advertise a create; in
		// active the executor will POST the ruleset first.
		plan.operation = "create-ruleset-and-rule"
		plan.action = "would create ruleset + rule"
		plan.summary = "phase ruleset absent; would POST ruleset then POST rule"
		return plan, nil
	}
	plan.rulesetID = rs.ID

	// Adoption path: the CR pins a specific Cloudflare rule id.
	if cr.Spec.Adopt != nil {
		existing := cloudflare.FindRuleByID(rs, cr.Spec.Adopt.RuleID)
		if existing == nil {
			plan.operation = "adopt-missing"
			plan.action = fmt.Sprintf("adoption target %q not found in ruleset %s", cr.Spec.Adopt.RuleID, rs.ID)
			return plan, errors.New(plan.action)
		}
		plan.existing = existing
		plan.ruleID = existing.ID
		merged := mergeAdopted(*existing, desired)
		if rulesetRuleDiffers(existing, &merged) {
			plan.operation = "adopt-update"
			plan.action = "would update adopted rule"
			plan.summary = summariseDiff(existing, &merged)
			return plan, nil
		}
		plan.operation = "adopt-noop"
		plan.action = "in sync (adopted)"
		return plan, nil
	}

	// Managed-by-ref path. Existing rule wins the id; new rules
	// require the explicit CreateNewRule flag to prevent accidental
	// duplicates.
	existing := cloudflare.FindRuleByRef(rs, desired.Ref)
	if existing == nil {
		if !cr.Spec.CreateNewRule {
			plan.operation = "refuse-create"
			plan.action = "refusing to create: set spec.createNewRule=true or spec.adopt.ruleId"
			return plan, errors.New(plan.action)
		}
		plan.operation = "create"
		plan.action = "would create"
		plan.summary = "no rule with ref " + desired.Ref
		return plan, nil
	}
	plan.existing = existing
	plan.ruleID = existing.ID
	if rulesetRuleDiffers(existing, &desired) {
		plan.operation = "update"
		plan.action = "would update"
		plan.summary = summariseDiff(existing, &desired)
		return plan, nil
	}
	plan.operation = "in-sync"
	plan.action = "in sync"
	return plan, nil
}

func (r *CloudflareRateLimitReconciler) applyPlan(ctx context.Context, logger logr.Logger, cr *cfv1alpha1.CloudflareRateLimit, desired cloudflare.Rule, plan rateLimitPlan) error {
	rulesetID := plan.rulesetID
	if rulesetID == "" {
		rs, err := r.CF.CreatePhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.RateLimitPhase)
		if err != nil {
			return fmt.Errorf("create ruleset: %w", err)
		}
		rulesetID = rs.ID
		logger.Info("created ruleset", "rulesetId", rulesetID)
	}
	switch plan.operation {
	case "create", "create-ruleset-and-rule":
		updated, err := r.CF.AddRule(ctx, cr.Spec.ZoneID, rulesetID, desired)
		if err != nil {
			return fmt.Errorf("add rule: %w", err)
		}
		if created := cloudflare.FindRuleByRef(updated, desired.Ref); created != nil {
			logger.Info("created rate limit rule", "rulesetId", rulesetID, "ruleId", created.ID, "ref", desired.Ref)
		}
	case "update":
		if _, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rulesetID, plan.existing.ID, desired); err != nil {
			return fmt.Errorf("update rule: %w", err)
		}
		logger.Info("updated rate limit rule", "rulesetId", rulesetID, "ruleId", plan.existing.ID)
	case "adopt-update":
		merged := mergeAdopted(*plan.existing, desired)
		if _, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rulesetID, plan.existing.ID, merged); err != nil {
			return fmt.Errorf("update adopted rule: %w", err)
		}
		logger.Info("updated adopted rate limit rule", "rulesetId", rulesetID, "ruleId", plan.existing.ID)
	case "in-sync", "adopt-noop":
		// nothing to do
	default:
		return fmt.Errorf("planReconcile produced unhandled operation %q", plan.operation)
	}
	return nil
}

// reconcileDelete handles the CR delete path. Behaviour depends on
// spec.retainOnDelete (default true) and spec.mode. The zone comes
// from status.managedZoneId when set — that is where the rule
// actually lives, and using spec.zoneId here would leak a rule if
// zoneId had been mutated before CEL made it immutable.
func (r *CloudflareRateLimitReconciler) reconcileDelete(ctx context.Context, logger logr.Logger, cr *cfv1alpha1.CloudflareRateLimit, ref string) (ctrl.Result, error) {
	zone := cr.Status.ManagedZoneID
	if zone == "" {
		zone = cr.Spec.ZoneID
	}

	if cr.Spec.RetainOnDelete {
		logger.Info("retainOnDelete=true: leaving Cloudflare rule in place", "zoneId", zone, "ref", ref)
		return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
	}
	if cr.Spec.EffectiveMode() == cfv1alpha1.ReconcileModeReadOnly {
		logger.Info("read_only: would delete Cloudflare rule", "zoneId", zone, "ref", ref)
		return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
	}
	if err := driveRulesetDelete(ctx, r.CF, logger, zone, cloudflare.RateLimitPhase, "rate limit rule", ref); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
}

// writeRateLimitStatus stamps the rate-limit-specific status fields
// (managedZoneId, mode, proposedChanges) on top of the shared ones.
func writeRateLimitStatus(ctx context.Context, c client.Client, cr *cfv1alpha1.CloudflareRateLimit, ref, rulesetID, ruleID, message, proposed string, generation int64) error {
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.Ref = ref
	cr.Status.RulesetID = rulesetID
	cr.Status.RuleID = ruleID
	cr.Status.Message = message
	cr.Status.ProposedChanges = proposed
	cr.Status.Mode = cr.Spec.EffectiveMode()
	cr.Status.ObservedGeneration = cr.Generation
	if cr.Status.ManagedZoneID == "" && cr.Spec.ZoneID != "" {
		// Only stamp on first successful pass; never overwrite so a
		// zoneId mutation cannot re-point our delete.
		cr.Status.ManagedZoneID = cr.Spec.ZoneID
	}
	_ = generation
	now := metav1Now()
	cr.Status.LastReconciledAt = &now
	return c.Status().Patch(ctx, cr, patch)
}

// mergeAdopted takes the live Cloudflare rule as the baseline and
// overlays only the fields the CR explicitly sets. Fields Cloudflare
// stores that the operator does not model (things beyond
// Action/Expression/Description/Enabled/RateLimit) are preserved
// verbatim, so an adoption reconcile of a dashboard-created rule
// produces zero drift unless the CR intentionally changes something.
func mergeAdopted(base, desired cloudflare.Rule) cloudflare.Rule {
	out := base
	out.Ref = desired.Ref // ref may be set by adoption
	if desired.Action != "" {
		out.Action = desired.Action
	}
	if desired.Expression != "" {
		out.Expression = desired.Expression
	}
	if desired.Description != "" {
		out.Description = desired.Description
	}
	out.Enabled = desired.Enabled
	if desired.RateLimit != nil {
		out.RateLimit = desired.RateLimit
	}
	if len(desired.ActionParameters) > 0 {
		out.ActionParameters = desired.ActionParameters
	}
	return out
}

// summariseDiff is a compact human-readable diff for status /
// proposedChanges. Not exhaustive — covers the fields most likely
// to change and hides the rest so status stays readable.
func summariseDiff(existing, desired *cloudflare.Rule) string {
	if existing == nil {
		return "would create"
	}
	fields := []string{}
	if existing.Action != desired.Action {
		fields = append(fields, fmt.Sprintf("action: %s -> %s", existing.Action, desired.Action))
	}
	if existing.Expression != desired.Expression {
		fields = append(fields, "expression differs")
	}
	if existing.Description != desired.Description {
		fields = append(fields, "description differs")
	}
	if existing.Enabled != desired.Enabled {
		fields = append(fields, fmt.Sprintf("enabled: %v -> %v", existing.Enabled, desired.Enabled))
	}
	if desired.RateLimit != nil && (existing.RateLimit == nil || !reflect.DeepEqual(existing.RateLimit, desired.RateLimit)) {
		fields = append(fields, "ratelimit differs")
	}
	if len(fields) == 0 {
		return "action_parameters differ"
	}
	out := fields[0]
	for _, f := range fields[1:] {
		out += "; " + f
	}
	return out
}

// ruleRef derives the operator's stable identifier for a CR, used as
// the Cloudflare rule's Ref so subsequent reconciles find the same
// rule without a state backend. Must satisfy Cloudflare's regex
// (^[a-zA-Z0-9_]{1,32}$); see makeRef.
func ruleRef(cr *cfv1alpha1.CloudflareRateLimit) string {
	return makeRef(rateLimitRefPrefix, cr.Name, string(cr.UID))
}

// renderRule turns a CR into the Cloudflare rule payload we PUT.
// Kept pure so tests can compare desired output without an API round
// trip.
func renderRule(cr *cfv1alpha1.CloudflareRateLimit, ref string) cloudflare.Rule {
	return cloudflare.Rule{
		Action:      cr.Spec.Action,
		Expression:  cr.Spec.Expression,
		Description: cr.Spec.Description,
		Enabled:     cr.Spec.IsEnabled(),
		Ref:         ref,
		RateLimit: &cloudflare.RuleRateLimit{
			Characteristics:    append([]string(nil), cr.Spec.RateLimit.Characteristics...),
			Period:             cr.Spec.RateLimit.Period,
			RequestsPerPeriod:  cr.Spec.RateLimit.RequestsPerPeriod,
			MitigationTimeout:  cr.Spec.RateLimit.MitigationTimeoutSeconds,
			CountingExpression: cr.Spec.RateLimit.CountingExpression,
		},
	}
}

func (r *CloudflareRateLimitReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareRateLimit{}).
		Complete(r)
}
