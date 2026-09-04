package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarecacherules/finalizers,verbs=update

// CloudflareCacheRuleReconciler drives one CloudflareCacheRule toward
// its counterpart in the zone's http_request_cache_settings ruleset.
// Reconcile plumbing is shared with the rate-limit and WAF-custom-rule
// reconcilers via driveRulesetReconcile / driveRulesetDelete; only
// the payload rendering is per-CRD.
type CloudflareCacheRuleReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             RulesetAPI
	ResyncInterval time.Duration
}

func (r *CloudflareCacheRuleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarecacherule", req.Name)

	cr := &cfv1alpha1.CloudflareCacheRule{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	ref := cacheRuleRef(cr)

	if !cr.DeletionTimestamp.IsZero() {
		if err := driveRulesetDelete(ctx, r.CF, logger, cr.Spec.ZoneID, cloudflare.CacheSettingsPhase, "cache rule", ref); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
	}

	added, err := ensureFinalizer(ctx, r.Client, cr)
	if err != nil {
		return ctrl.Result{}, err
	}
	if added {
		return ctrl.Result{}, nil
	}

	desired, err := renderCacheRule(cr, ref)
	if err != nil {
		_ = writeRulesetStatus(ctx, r.Client, cr, &cr.Status, ref, "", "", fmt.Errorf("render rule: %w", err).Error(), cr.Generation)
		return ctrl.Result{}, err
	}

	out, err := driveRulesetReconcile(ctx, r.CF, logger, cr.Spec.ZoneID, cloudflare.CacheSettingsPhase, "cache rule", desired)
	if err != nil {
		_ = writeRulesetStatus(ctx, r.Client, cr, &cr.Status, ref, out.RulesetID, out.RuleID, err.Error(), cr.Generation)
		return ctrl.Result{}, err
	}
	return finishRulesetReconcile(ctx, r.Client, cr, &cr.Status, ref, out.RulesetID, out.RuleID, out.Message, cr.Generation, r.ResyncInterval)
}

// cacheRuleRef mirrors ruleRef but is namespaced to cache rules so a
// name collision between a CloudflareRateLimit and a CloudflareCacheRule
// doesn't collide on the wire.
func cacheRuleRef(cr *cfv1alpha1.CloudflareCacheRule) string {
	return makeRef(cacheRuleRefPrefix, cr.Name, string(cr.UID))
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
		if cs.EdgeTTL.Default != nil {
			edge["default"] = *cs.EdgeTTL.Default
		}
		params["edge_ttl"] = edge
	}
	if cs.BrowserTTL != nil {
		br := map[string]any{"mode": cs.BrowserTTL.Mode}
		if cs.BrowserTTL.Default != nil {
			br["default"] = *cs.BrowserTTL.Default
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
