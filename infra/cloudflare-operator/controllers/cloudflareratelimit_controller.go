// Package controllers holds the reconcilers for the Cloudflare
// operator. Each reconciler owns one CRD and keeps its live Cloudflare
// counterpart in sync with the CR spec. The pattern is stateless: no
// separate state backend, no client-side ids to track. The operator
// finds its rules by a stable Ref it sets on Cloudflare and computes
// the delta on every reconcile.
//
// The Ruleset-shaped reconcilers (rate limit, cache rule, WAF custom
// rule) share almost all of their reconcile plumbing via
// driveRulesetReconcile / driveRulesetDelete in ruleset_common.go;
// each concrete reconciler only owns its CR fetch, phase choice,
// ref/render, and status write.
package controllers

import (
	"context"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

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
		if err := driveRulesetDelete(ctx, r.CF, logger, cr.Spec.ZoneID, cloudflare.RateLimitPhase, "rate limit rule", ref); err != nil {
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

	desired := renderRule(cr, ref)
	out, err := driveRulesetReconcile(ctx, r.CF, logger, cr.Spec.ZoneID, cloudflare.RateLimitPhase, "rate limit rule", desired)
	if err != nil {
		_ = writeRulesetStatus(ctx, r.Client, cr, &cr.Status, ref, out.RulesetID, out.RuleID, err.Error(), cr.Generation)
		return ctrl.Result{}, err
	}
	return finishRulesetReconcile(ctx, r.Client, cr, &cr.Status, ref, out.RulesetID, out.RuleID, out.Message, cr.Generation, r.ResyncInterval)
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
