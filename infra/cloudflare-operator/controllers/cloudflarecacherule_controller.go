package controllers

import (
	"context"
	"encoding/json"
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

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules/finalizers,verbs=update

type CloudflareCacheRuleReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             RulesetAPI
	ResyncInterval time.Duration
}

type cacheRulePlan struct {
	operation string
	action    string
	summary   string
	rulesetID string
	ruleID    string
	existing  *cloudflare.Rule
}

func (r *CloudflareCacheRuleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarecacherule", req.Name)
	cr := &cfv1alpha1.CloudflareCacheRule{}
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

	ref := cacheRuleRef(cr)
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

	desired := renderCacheRule(cr, ref)
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

func (r *CloudflareCacheRuleReconciler) planReconcile(ctx context.Context, cr *cfv1alpha1.CloudflareCacheRule, desired cloudflare.Rule) (cacheRulePlan, error) {
	plan := cacheRulePlan{}
	rs, err := r.CF.GetPhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.CacheSettingsPhase)
	if err != nil {
		return plan, fmt.Errorf("get ruleset: %w", err)
	}

	if cr.Spec.Adopt != nil {
		if rs == nil {
			plan.action = fmt.Sprintf("adoption target %q not found: zone has no cache settings ruleset", cr.Spec.Adopt.RuleID)
			return plan, errors.New(plan.action)
		}
		plan.rulesetID = rs.ID
		plan.existing = cloudflare.FindRuleByID(rs, cr.Spec.Adopt.RuleID)
		if plan.existing == nil {
			plan.action = fmt.Sprintf("adoption target %q not found in ruleset %s", cr.Spec.Adopt.RuleID, rs.ID)
			return plan, errors.New(plan.action)
		}
		plan.ruleID = plan.existing.ID
		merged := mergeCacheRule(*plan.existing, desired)
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

func (r *CloudflareCacheRuleReconciler) applyPlan(ctx context.Context, logger logr.Logger, cr *cfv1alpha1.CloudflareCacheRule, desired cloudflare.Rule, plan cacheRulePlan) error {
	rulesetID := plan.rulesetID
	if rulesetID == "" {
		rs, err := r.CF.CreatePhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.CacheSettingsPhase)
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
		logger.Info("created cache rule", "rulesetId", rulesetID, "ref", desired.Ref)
	case "update":
		if _, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rulesetID, plan.existing.ID, desired); err != nil {
			return fmt.Errorf("update rule: %w", err)
		}
	case "adopt-update":
		merged := mergeCacheRule(*plan.existing, desired)
		if _, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rulesetID, plan.existing.ID, merged); err != nil {
			return fmt.Errorf("update adopted rule: %w", err)
		}
	case "in-sync", "adopt-noop":
	default:
		return fmt.Errorf("planReconcile produced unhandled operation %q", plan.operation)
	}
	return nil
}

func (r *CloudflareCacheRuleReconciler) reconcileDelete(ctx context.Context, logger logr.Logger, cr *cfv1alpha1.CloudflareCacheRule, ref string) (ctrl.Result, error) {
	zone := cr.Status.ManagedZoneID
	if zone == "" {
		zone = cr.Spec.ZoneID
	}
	if cr.Spec.RetainOnDelete || cr.Spec.EffectiveMode() == cfv1alpha1.ReconcileModeReadOnly {
		return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
	}
	if err := driveRulesetDelete(ctx, r.CF, logger, zone, cloudflare.CacheSettingsPhase, "cache rule", ref); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
}

func (r *CloudflareCacheRuleReconciler) writeStatus(ctx context.Context, cr *cfv1alpha1.CloudflareCacheRule, ref, rulesetID, ruleID, message, proposed, reason string, readyStatus metav1.ConditionStatus, observedGeneration int64) error {
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

func mergeCacheRule(base, desired cloudflare.Rule) cloudflare.Rule {
	out := base
	out.Action = desired.Action
	out.Expression = desired.Expression
	out.Description = desired.Description
	out.Enabled = desired.Enabled
	// The CR owns every cache setting it can express, so an adopted
	// rule's action_parameters are replaced, not merged.
	out.ActionParameters = desired.ActionParameters
	return out
}

func cacheRuleRef(cr *cfv1alpha1.CloudflareCacheRule) string {
	return makeRef(cacheRuleRefPrefix, cr.Name, string(cr.UID))
}

// cacheActionParameters is the `set_cache_settings` payload for the
// settings the CR models.
type cacheActionParameters struct {
	Cache      bool      `json:"cache"`
	EdgeTTL    *cacheTTL `json:"edge_ttl,omitempty"`
	BrowserTTL *cacheTTL `json:"browser_ttl,omitempty"`
}

type cacheTTL struct {
	Mode    string `json:"mode"`
	Default *int64 `json:"default,omitempty"`
}

func toCacheTTL(ttl *cfv1alpha1.CacheTTL) *cacheTTL {
	if ttl == nil {
		return nil
	}
	return &cacheTTL{Mode: ttl.Mode, Default: ttl.Default}
}

func renderCacheRule(cr *cfv1alpha1.CloudflareCacheRule, ref string) cloudflare.Rule {
	params, _ := json.Marshal(cacheActionParameters{
		Cache:      cr.Spec.Cache,
		EdgeTTL:    toCacheTTL(cr.Spec.EdgeTTL),
		BrowserTTL: toCacheTTL(cr.Spec.BrowserTTL),
	})
	return cloudflare.Rule{
		Action:           "set_cache_settings",
		Expression:       cr.Spec.Expression,
		Description:      cr.Spec.Description,
		Enabled:          cr.Spec.IsEnabled(),
		Ref:              ref,
		ActionParameters: params,
	}
}

func (r *CloudflareCacheRuleReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareCacheRule{}, builder.WithPredicates(predicate.Or(predicate.GenerationChangedPredicate{}, annotationOrDeletionChanged()))).
		Complete(r)
}
