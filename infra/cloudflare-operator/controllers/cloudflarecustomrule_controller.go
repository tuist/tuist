package controllers

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecustomrules,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecustomrules/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecustomrules/finalizers,verbs=update

type CloudflareCustomRuleReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             RulesetAPI
	ResyncInterval time.Duration
}

type customRulePlan struct {
	operation string
	action    string
	summary   string
	rulesetID string
	ruleID    string
	existing  *cloudflare.Rule
}

func (r *CloudflareCustomRuleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarecustomrule", req.Name)
	cr := &cfv1alpha1.CloudflareCustomRule{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if cr.Spec.Paused {
		message := "paused"
		if !cr.DeletionTimestamp.IsZero() {
			message = "paused: delete held"
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, r.writeStatus(
			ctx, cr, cr.Status.Ref, cr.Status.RulesetID, cr.Status.RuleID, message, "",
			cfv1alpha1.ReasonPaused, metav1.ConditionFalse, cr.Status.ObservedGeneration,
		)
	}

	ref := customRuleRef(cr)
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

	desired := renderCustomRule(cr, ref)
	plan, err := r.planReconcile(ctx, cr, desired)
	if err != nil {
		_ = r.writeStatus(ctx, cr, ref, plan.rulesetID, plan.ruleID, err.Error(), "", cfv1alpha1.ReasonReconcileError, metav1.ConditionFalse, cr.Status.ObservedGeneration)
		return ctrl.Result{}, err
	}

	if cr.Spec.EffectiveMode() == cfv1alpha1.ReconcileModeReadOnly {
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

func (r *CloudflareCustomRuleReconciler) planReconcile(ctx context.Context, cr *cfv1alpha1.CloudflareCustomRule, desired cloudflare.Rule) (customRulePlan, error) {
	plan := customRulePlan{}
	rs, err := r.CF.GetPhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.CustomFirewallPhase)
	if err != nil {
		return plan, fmt.Errorf("get ruleset: %w", err)
	}

	if cr.Spec.Adopt != nil {
		if rs == nil {
			plan.action = fmt.Sprintf("adoption target %q not found: zone has no custom firewall ruleset", cr.Spec.Adopt.RuleID)
			return plan, errors.New(plan.action)
		}
		plan.rulesetID = rs.ID
		plan.existing = cloudflare.FindRuleByID(rs, cr.Spec.Adopt.RuleID)
		if plan.existing == nil {
			plan.action = fmt.Sprintf("adoption target %q not found in ruleset %s", cr.Spec.Adopt.RuleID, rs.ID)
			return plan, errors.New(plan.action)
		}
		plan.ruleID = plan.existing.ID
		merged := mergeCustomRule(*plan.existing, desired)
		if rulesetRuleDiffers(plan.existing, &merged) {
			plan.operation = "adopt-update"
			plan.action = "would update adopted rule"
			plan.summary = summariseDiff(plan.existing, &merged)
		} else {
			plan.operation = "adopt-noop"
			plan.action = "in sync (adopted)"
		}
		return plan, nil
	}

	if rs == nil {
		if !cr.Spec.CreateNewRule {
			plan.action = "refusing to create: set spec.createNewRule=true or spec.adopt.ruleId"
			return plan, errors.New(plan.action)
		}
		plan.operation = "create-ruleset-and-rule"
		plan.action = "would create ruleset + rule"
		plan.summary = "phase ruleset absent; would POST ruleset then POST rule"
		return plan, nil
	}
	plan.rulesetID = rs.ID
	plan.existing = cloudflare.FindRuleByRef(rs, desired.Ref)
	if plan.existing == nil {
		if !cr.Spec.CreateNewRule {
			plan.action = "refusing to create: set spec.createNewRule=true or spec.adopt.ruleId"
			return plan, errors.New(plan.action)
		}
		plan.operation = "create"
		plan.action = "would create"
		plan.summary = "no rule with ref " + desired.Ref
		return plan, nil
	}
	plan.ruleID = plan.existing.ID
	if rulesetRuleDiffers(plan.existing, &desired) {
		plan.operation = "update"
		plan.action = "would update"
		plan.summary = summariseDiff(plan.existing, &desired)
	} else {
		plan.operation = "in-sync"
		plan.action = "in sync"
	}
	return plan, nil
}

func (r *CloudflareCustomRuleReconciler) applyPlan(ctx context.Context, logger logr.Logger, cr *cfv1alpha1.CloudflareCustomRule, desired cloudflare.Rule, plan customRulePlan) error {
	rulesetID := plan.rulesetID
	if rulesetID == "" {
		rs, err := r.CF.CreatePhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.CustomFirewallPhase)
		if err != nil {
			return fmt.Errorf("create ruleset: %w", err)
		}
		rulesetID = rs.ID
	}

	switch plan.operation {
	case "create", "create-ruleset-and-rule":
		if _, err := r.CF.AddRule(ctx, cr.Spec.ZoneID, rulesetID, desired); err != nil {
			return fmt.Errorf("add rule: %w", err)
		}
		logger.Info("created custom firewall rule", "rulesetId", rulesetID, "ref", desired.Ref)
	case "update":
		if _, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rulesetID, plan.existing.ID, desired); err != nil {
			return fmt.Errorf("update rule: %w", err)
		}
	case "adopt-update":
		merged := mergeCustomRule(*plan.existing, desired)
		if _, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rulesetID, plan.existing.ID, merged); err != nil {
			return fmt.Errorf("update adopted rule: %w", err)
		}
	case "in-sync", "adopt-noop":
	default:
		return fmt.Errorf("planReconcile produced unhandled operation %q", plan.operation)
	}
	return nil
}

func (r *CloudflareCustomRuleReconciler) reconcileDelete(ctx context.Context, logger logr.Logger, cr *cfv1alpha1.CloudflareCustomRule, ref string) (ctrl.Result, error) {
	zone := cr.Status.ManagedZoneID
	if zone == "" {
		zone = cr.Spec.ZoneID
	}
	if cr.Spec.RetainOnDelete || cr.Spec.EffectiveMode() == cfv1alpha1.ReconcileModeReadOnly {
		return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
	}
	if err := driveRulesetDelete(ctx, r.CF, logger, zone, cloudflare.CustomFirewallPhase, "custom firewall rule", ref); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
}

func (r *CloudflareCustomRuleReconciler) writeStatus(ctx context.Context, cr *cfv1alpha1.CloudflareCustomRule, ref, rulesetID, ruleID, message, proposed, reason string, readyStatus metav1.ConditionStatus, observedGeneration int64) error {
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.Ref = ref
	cr.Status.RulesetID = rulesetID
	cr.Status.RuleID = ruleID
	cr.Status.Message = message
	cr.Status.ProposedChanges = proposed
	cr.Status.Mode = cr.Spec.EffectiveMode()
	cr.Status.ObservedGeneration = observedGeneration
	if cr.Status.ManagedZoneID == "" && readyStatus == metav1.ConditionTrue {
		cr.Status.ManagedZoneID = cr.Spec.ZoneID
	}
	now := metav1Now()
	setCondition(&cr.Status.Conditions, metav1.Condition{Type: cfv1alpha1.ConditionTypeReady, Status: readyStatus, Reason: reason, Message: message, LastTransitionTime: now, ObservedGeneration: observedGeneration})
	cr.Status.LastReconciledAt = &now
	return r.Status().Patch(ctx, cr, patch)
}

func mergeCustomRule(base, desired cloudflare.Rule) cloudflare.Rule {
	out := base
	out.Action = desired.Action
	out.Expression = desired.Expression
	out.Description = desired.Description
	out.Enabled = desired.Enabled
	return out
}

func customRuleRef(cr *cfv1alpha1.CloudflareCustomRule) string {
	return makeRef(customRuleRefPrefix, cr.Name, string(cr.UID))
}

func renderCustomRule(cr *cfv1alpha1.CloudflareCustomRule, ref string) cloudflare.Rule {
	return cloudflare.Rule{
		Action:      cr.Spec.Action,
		Expression:  cr.Spec.Expression,
		Description: cr.Spec.Description,
		Enabled:     cr.Spec.IsEnabled(),
		Ref:         ref,
	}
}

func (r *CloudflareCustomRuleReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareCustomRule{}, builder.WithPredicates(predicate.Or(predicate.GenerationChangedPredicate{}, annotationOrDeletionChanged()))).
		Complete(r)
}
