package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules/finalizers,verbs=update

// CloudflareCacheRuleReconciler drives one CloudflareCacheRule toward
// its counterpart in the zone's http_request_cache_settings ruleset.
// Shares the create-or-adopt Ruleset pattern with the rate limit
// reconciler; only the payload rendering differs.
type CloudflareCacheRuleReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             RulesetAPI
	ResyncInterval time.Duration
}

func (r *CloudflareCacheRuleReconciler) resync() time.Duration {
	if r.ResyncInterval > 0 {
		return r.ResyncInterval
	}
	return defaultResyncInterval
}

func (r *CloudflareCacheRuleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarecacherule", req.Name)

	cr := &cfv1alpha1.CloudflareCacheRule{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	ref := cacheRuleRef(cr)

	if !cr.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, cr, ref)
	}

	if !controllerutil.ContainsFinalizer(cr, finalizer) {
		controllerutil.AddFinalizer(cr, finalizer)
		if err := r.Update(ctx, cr); err != nil {
			return ctrl.Result{}, fmt.Errorf("add finalizer: %w", err)
		}
		return ctrl.Result{}, nil
	}

	rs, err := ensurePhaseRuleset(ctx, r.CF, cr.Spec.ZoneID, cloudflare.CacheSettingsPhase)
	if err != nil {
		return r.fail(ctx, cr, ref, "", "", err)
	}

	desired, err := renderCacheRule(cr, ref)
	if err != nil {
		return r.fail(ctx, cr, ref, rs.ID, "", fmt.Errorf("render rule: %w", err))
	}

	existing := cloudflare.FindRuleByRef(rs, ref)

	switch {
	case existing == nil:
		updated, err := r.CF.AddRule(ctx, cr.Spec.ZoneID, rs.ID, desired)
		if err != nil {
			return r.fail(ctx, cr, ref, rs.ID, "", fmt.Errorf("add cache rule: %w", err))
		}
		created := cloudflare.FindRuleByRef(updated, ref)
		logger.Info("created cache rule", "rulesetId", rs.ID, "ruleId", ruleIDOf(created), "ref", ref)
		return r.succeed(ctx, cr, ref, rs.ID, ruleIDOf(created), "created")

	case rulesetRuleDiffers(existing, &desired):
		updated, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rs.ID, existing.ID, desired)
		if err != nil {
			return r.fail(ctx, cr, ref, rs.ID, existing.ID, fmt.Errorf("update cache rule: %w", err))
		}
		patched := cloudflare.FindRuleByRef(updated, ref)
		logger.Info("updated cache rule", "rulesetId", rs.ID, "ruleId", ruleIDOf(patched), "ref", ref)
		return r.succeed(ctx, cr, ref, rs.ID, ruleIDOf(patched), "updated")

	default:
		return r.succeed(ctx, cr, ref, rs.ID, existing.ID, "in sync")
	}
}

func (r *CloudflareCacheRuleReconciler) reconcileDelete(ctx context.Context, cr *cfv1alpha1.CloudflareCacheRule, ref string) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarecacherule", cr.Name)
	if !controllerutil.ContainsFinalizer(cr, finalizer) {
		return ctrl.Result{}, nil
	}
	rs, err := r.CF.GetPhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.CacheSettingsPhase)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("get ruleset for delete: %w", err)
	}
	if rs != nil {
		if existing := cloudflare.FindRuleByRef(rs, ref); existing != nil {
			if err := r.CF.DeleteRule(ctx, cr.Spec.ZoneID, rs.ID, existing.ID); err != nil {
				return ctrl.Result{}, fmt.Errorf("delete cache rule: %w", err)
			}
			logger.Info("deleted cache rule", "rulesetId", rs.ID, "ruleId", existing.ID, "ref", ref)
		}
	}
	controllerutil.RemoveFinalizer(cr, finalizer)
	if err := r.Update(ctx, cr); err != nil {
		return ctrl.Result{}, fmt.Errorf("remove finalizer: %w", err)
	}
	return ctrl.Result{}, nil
}

func (r *CloudflareCacheRuleReconciler) succeed(ctx context.Context, cr *cfv1alpha1.CloudflareCacheRule, ref, rulesetID, ruleID, message string) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, ref, rulesetID, ruleID, message); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.resync()}, nil
}

func (r *CloudflareCacheRuleReconciler) fail(ctx context.Context, cr *cfv1alpha1.CloudflareCacheRule, ref, rulesetID, ruleID string, cause error) (ctrl.Result, error) {
	message := cause.Error()
	if statusErr := r.setStatus(ctx, cr, ref, rulesetID, ruleID, message); statusErr != nil {
		return ctrl.Result{}, statusErr
	}
	return ctrl.Result{}, cause
}

func (r *CloudflareCacheRuleReconciler) setStatus(ctx context.Context, cr *cfv1alpha1.CloudflareCacheRule, ref, rulesetID, ruleID, message string) error {
	now := metav1.NewTime(time.Now().UTC())
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.Ref = ref
	cr.Status.RulesetID = rulesetID
	cr.Status.RuleID = ruleID
	cr.Status.Message = message
	cr.Status.ObservedGeneration = cr.Generation
	cr.Status.LastReconciledAt = &now
	if err := r.Status().Patch(ctx, cr, patch); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("patch status: %w", err)
	}
	return nil
}

// cacheRuleRef mirrors ruleRef but is namespaced to cache rules so a
// name collision between a CloudflareRateLimit and a CloudflareCacheRule
// doesn't collide on the wire.
func cacheRuleRef(cr *cfv1alpha1.CloudflareCacheRule) string {
	uid := string(cr.UID)
	if len(uid) > 12 {
		uid = uid[:12]
	}
	return fmt.Sprintf("%scache_%s_%s", refPrefix, cr.Name, uid)
}

// renderCacheRule turns a CR into the Cloudflare rule payload. The
// `action_parameters` block is marshalled from a plain map so the
// operator can tolerate Cloudflare adding new fields without a CRD
// migration.
func renderCacheRule(cr *cfv1alpha1.CloudflareCacheRule, ref string) (cloudflare.Rule, error) {
	params := map[string]any{}
	cs := cr.Spec.CacheSettings
	if cs.Cache != nil {
		params["cache"] = *cs.Cache
	}
	if cs.EdgeTTL != nil {
		edge := map[string]any{"mode": cs.EdgeTTL.Mode}
		if cs.EdgeTTL.Default > 0 {
			edge["default"] = cs.EdgeTTL.Default
		}
		params["edge_ttl"] = edge
	}
	if cs.BrowserTTL != nil {
		br := map[string]any{"mode": cs.BrowserTTL.Mode}
		if cs.BrowserTTL.Default > 0 {
			br["default"] = cs.BrowserTTL.Default
		}
		params["browser_ttl"] = br
	}
	if cs.RespectStrongEtags != nil {
		params["respect_strong_etags"] = *cs.RespectStrongEtags
	}
	if cs.CacheDeceptionArmor != nil {
		params["cache_deception_armor"] = *cs.CacheDeceptionArmor
	}
	if cs.OriginErrorPagePassthru != nil {
		params["origin_error_page_passthru"] = *cs.OriginErrorPagePassthru
	}
	if len(cs.AdditionalCacheablePorts) > 0 {
		params["additional_cacheable_ports"] = cs.AdditionalCacheablePorts
	}
	raw, err := json.Marshal(params)
	if err != nil {
		return cloudflare.Rule{}, err
	}
	return cloudflare.Rule{
		Action:           "set_cache_settings",
		Expression:       cr.Spec.Expression,
		Description:      cr.Spec.Description,
		Enabled:          cr.Spec.IsEnabled(),
		Ref:              ref,
		ActionParameters: raw,
	}, nil
}

func (r *CloudflareCacheRuleReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareCacheRule{}).
		Complete(r)
}
