// Package controllers holds the reconcilers for the Cloudflare
// operator.
//
// Rate-limit reconciler design (safe first deploy):
//
//   - spec.mode defaults to read_only; in read_only the operator
//     computes the intended diff, mirrors it into
//     status.proposedChanges and status.conditions[Ready]=False
//     (Reason=ReadOnly), and never issues a Cloudflare write —
//     including no ruleset creation, no rule delete on finalizer
//     cleanup, and no delete on an in-flight CR removal.
//   - spec.paused halts the reconcile loop entirely, including the
//     delete branch. The finalizer stays; the object sits in
//     Terminating until spec.paused flips back to false.
//   - spec.adopt.ruleId is checked before any ruleset-create
//     decision. If the phase ruleset or the target rule id is
//     missing the plan fails closed rather than creating a new
//     ruleset + rule under the operator's ref.
//   - Adoption preserves the live rule's ref and merges only the
//     CR-managed fields over the live payload. Cloudflare-stored
//     fields the operator does not model (extra rate-limit knobs,
//     future action-parameter keys) round-trip verbatim, so the
//     first adoption reconcile of a matching dashboard rule is a
//     real zero-change no-op.
//   - status.managedZoneId records the zone the rule actually lives
//     in and the delete path uses it, so a zoneId mutation cannot
//     orphan a rule even if CRD-level CEL is bypassed.
//   - status.observedGeneration is only advanced on a successful
//     active reconcile. read_only, paused, and error paths hold
//     observedGeneration back, so kstatus consumers (Flux
//     Kustomization health checks, `kubectl wait`) see the CR as
//     NotReady until an active reconcile actually applies the
//     current spec.
//   - The controller filters status-only updates via a
//     GenerationChangedPredicate so a status patch does not
//     re-enqueue the CR and turn the resync interval into a hammer
//     loop against the Cloudflare API.
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
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

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

	// Paused short-circuits everything, including deletion. The
	// finalizer stays; a Terminating paused CR sits in place until
	// paused flips back to false. This is what makes paused a real
	// break-glass rather than "halt writes on new specs but still
	// process a delete that has already been queued".
	if cr.Spec.Paused {
		logger.V(1).Info("reconcile paused, skipping (including delete branch)")
		if !cr.DeletionTimestamp.IsZero() {
			return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, r.setNotReady(ctx, cr, cfv1alpha1.ReasonPaused, "paused: delete held", cr.Status.ObservedGeneration)
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, r.setNotReady(ctx, cr, cfv1alpha1.ReasonPaused, "paused", cr.Status.ObservedGeneration)
	}

	ref := ruleRef(cr)

	if !cr.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, logger, cr, ref)
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
		_ = r.writeStatus(ctx, cr, ref, plan.rulesetID, plan.ruleID, err.Error(), "", cfv1alpha1.ReasonReconcileError, metav1.ConditionFalse, cr.Status.ObservedGeneration)
		return ctrl.Result{}, err
	}

	mode := cr.Spec.EffectiveMode()
	if mode == cfv1alpha1.ReconcileModeReadOnly {
		logger.Info("read_only: would "+plan.action, "rulesetId", plan.rulesetID, "ruleId", plan.ruleID, "ref", ref)
		if err := r.writeStatus(ctx, cr, ref, plan.rulesetID, plan.ruleID, "read_only: "+plan.action, plan.summary, cfv1alpha1.ReasonReadOnly, metav1.ConditionFalse, cr.Status.ObservedGeneration); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
	}

	if err := r.applyPlan(ctx, logger, cr, desired, plan); err != nil {
		_ = r.writeStatus(ctx, cr, ref, plan.rulesetID, plan.ruleID, err.Error(), "", cfv1alpha1.ReasonReconcileError, metav1.ConditionFalse, cr.Status.ObservedGeneration)
		return ctrl.Result{}, err
	}
	if err := r.writeStatus(ctx, cr, ref, plan.rulesetID, plan.ruleID, plan.action, "", cfv1alpha1.ReasonReconciled, metav1.ConditionTrue, cr.Generation); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
}

// rateLimitPlan is what planReconcile hands back to the executor.
type rateLimitPlan struct {
	// operation is one of: create, adopt-noop, adopt-update, update,
	// in-sync.
	operation string

	// action is a short label suitable for status.message and logs.
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
// making any Cloudflare writes past the read-only GET.
//
// Adoption is checked before any create branch, so an active
// adoption CR whose target ruleset or rule is missing fails closed
// rather than silently creating a new ruleset + rule under the
// operator's own ref.
func (r *CloudflareRateLimitReconciler) planReconcile(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, desired cloudflare.Rule) (rateLimitPlan, error) {
	plan := rateLimitPlan{}
	rs, err := r.CF.GetPhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.RateLimitPhase)
	if err != nil {
		return plan, fmt.Errorf("get ruleset: %w", err)
	}

	if cr.Spec.Adopt != nil {
		if rs == nil {
			plan.operation = "adopt-missing"
			plan.action = fmt.Sprintf("adoption target %q not found: zone %s has no %s ruleset", cr.Spec.Adopt.RuleID, cr.Spec.ZoneID, cloudflare.RateLimitPhase)
			return plan, errors.New(plan.action)
		}
		plan.rulesetID = rs.ID
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

	// No-adopt, non-existent ruleset: the operator creates the ruleset
	// and the rule together, subject to CreateNewRule.
	if rs == nil {
		if !cr.Spec.CreateNewRule {
			plan.operation = "refuse-create"
			plan.action = "refusing to create: set spec.createNewRule=true or spec.adopt.ruleId"
			return plan, errors.New(plan.action)
		}
		plan.operation = "create-ruleset-and-rule"
		plan.action = "would create ruleset + rule"
		plan.summary = "phase ruleset absent; would POST ruleset then POST rule"
		return plan, nil
	}
	plan.rulesetID = rs.ID

	// Managed-by-ref path.
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
// actually lives.
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

// writeStatus stamps the CR status. observedGeneration only advances
// when the caller explicitly hands in cr.Generation on success paths;
// read_only, paused, and error paths hold it back so kstatus sees
// the CR as NotReady until a real active reconcile applies the spec.
func (r *CloudflareRateLimitReconciler) writeStatus(
	ctx context.Context,
	cr *cfv1alpha1.CloudflareRateLimit,
	ref, rulesetID, ruleID, message, proposed, reason string,
	readyStatus metav1.ConditionStatus,
	observedGeneration int64,
) error {
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.Ref = ref
	cr.Status.RulesetID = rulesetID
	cr.Status.RuleID = ruleID
	cr.Status.Message = message
	cr.Status.ProposedChanges = proposed
	cr.Status.Mode = cr.Spec.EffectiveMode()
	cr.Status.ObservedGeneration = observedGeneration
	if cr.Status.ManagedZoneID == "" && cr.Spec.ZoneID != "" && readyStatus == metav1.ConditionTrue {
		// Only stamp on first successful pass; never overwrite so a
		// zoneId mutation cannot re-point our delete.
		cr.Status.ManagedZoneID = cr.Spec.ZoneID
	}
	now := metav1Now()
	cond := metav1.Condition{
		Type:               cfv1alpha1.ConditionTypeReady,
		Status:             readyStatus,
		Reason:             reason,
		Message:            message,
		LastTransitionTime: now,
		ObservedGeneration: observedGeneration,
	}
	setCondition(&cr.Status.Conditions, cond)
	cr.Status.LastReconciledAt = &now
	return r.Status().Patch(ctx, cr, patch)
}

// setNotReady is a small helper for the paused branches that write a
// minimal status update without touching the rule fields.
func (r *CloudflareRateLimitReconciler) setNotReady(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, reason, message string, observedGeneration int64) error {
	return r.writeStatus(ctx, cr, cr.Status.Ref, cr.Status.RulesetID, cr.Status.RuleID, message, "", reason, metav1.ConditionFalse, observedGeneration)
}

// setCondition overlays cond onto conds, replacing any existing entry
// of the same Type. LastTransitionTime is only updated when the
// status actually changed.
func setCondition(conds *[]metav1.Condition, cond metav1.Condition) {
	for i, existing := range *conds {
		if existing.Type == cond.Type {
			if existing.Status == cond.Status {
				cond.LastTransitionTime = existing.LastTransitionTime
			}
			(*conds)[i] = cond
			return
		}
	}
	*conds = append(*conds, cond)
}

// mergeAdopted takes the live Cloudflare rule as the baseline and
// overlays only the fields the CR explicitly sets. The adopted rule's
// Ref is preserved unchanged so a first-adoption reconcile of a
// dashboard-created rule (whose ref is not the operator's derived
// one) is not forced into a spurious PATCH. For the rate-limit
// block, individual CR-managed fields are copied over the live block
// so Cloudflare-stored fields the operator does not model round-trip
// verbatim on the wire.
func mergeAdopted(base, desired cloudflare.Rule) cloudflare.Rule {
	out := base
	// Ref: keep the adopted rule's ref. The operator finds the rule
	// by id going forward.
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
		out.RateLimit = mergeRateLimit(out.RateLimit, desired.RateLimit)
	}
	if len(desired.ActionParameters) > 0 {
		out.ActionParameters = desired.ActionParameters
	}
	return out
}

// mergeRateLimit overlays the CR-managed rate-limit fields onto a
// base block, preserving unmodeled fields the CR does not touch
// (RequestsToOrigin, ScorePerPeriod, ScoreResponseHeaderName).
func mergeRateLimit(base, desired *cloudflare.RuleRateLimit) *cloudflare.RuleRateLimit {
	if base == nil {
		return desired
	}
	if desired == nil {
		return base
	}
	out := *base
	out.Characteristics = append([]string(nil), desired.Characteristics...)
	out.Period = desired.Period
	out.RequestsPerPeriod = desired.RequestsPerPeriod
	out.MitigationTimeout = desired.MitigationTimeout
	out.CountingExpression = desired.CountingExpression
	return &out
}

// summariseDiff is a compact human-readable diff for status /
// proposedChanges.
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
	if !rateLimitManagedEqual(existing.RateLimit, desired.RateLimit) {
		fields = append(fields, "ratelimit differs")
	}
	if !reflect.DeepEqual(existing.RateLimit, desired.RateLimit) && rateLimitManagedEqual(existing.RateLimit, desired.RateLimit) {
		// managed-equal but object-different means non-modeled fields differ; no drift.
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

// ruleRef derives the operator's stable identifier for a CR (used
// only for non-adopted, operator-created rules).
func ruleRef(cr *cfv1alpha1.CloudflareRateLimit) string {
	return makeRef(rateLimitRefPrefix, cr.Name, string(cr.UID))
}

// renderRule turns a CR into the Cloudflare rule payload we PUT.
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

// SetupWithManager wires the reconciler with a
// GenerationChangedPredicate on the owned CR type so status-only
// updates do not re-enqueue. Without this the LastReconciledAt patch
// on every pass would immediately re-trigger a reconcile and turn
// ResyncInterval into ~0.
func (r *CloudflareRateLimitReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareRateLimit{},
			builder.WithPredicates(predicate.Or(
				predicate.GenerationChangedPredicate{},
				annotationOrDeletionChanged(),
			)),
		).
		Complete(r)
}

// annotationOrDeletionChanged supplements GenerationChangedPredicate so
// that finalizer/deletion transitions (which do not bump Generation)
// still enqueue.
func annotationOrDeletionChanged() predicate.Predicate {
	return predicate.Funcs{
		UpdateFunc: func(e event.UpdateEvent) bool {
			if e.ObjectOld == nil || e.ObjectNew == nil {
				return false
			}
			// Deletion transition.
			oldDel := e.ObjectOld.GetDeletionTimestamp()
			newDel := e.ObjectNew.GetDeletionTimestamp()
			if (oldDel == nil) != (newDel == nil) {
				return true
			}
			// Finalizer transition.
			return !reflect.DeepEqual(e.ObjectOld.GetFinalizers(), e.ObjectNew.GetFinalizers())
		},
	}
}
