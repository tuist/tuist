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

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarewafcustomrules,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarewafcustomrules/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarewafcustomrules/finalizers,verbs=update

// CloudflareWAFCustomRuleReconciler drives one CloudflareWAFCustomRule
// toward its counterpart in the zone's http_request_firewall_custom
// ruleset.
type CloudflareWAFCustomRuleReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             RulesetAPI
	ResyncInterval time.Duration
}

func (r *CloudflareWAFCustomRuleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarewafcustomrule", req.Name)

	cr := &cfv1alpha1.CloudflareWAFCustomRule{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	ref := wafRuleRef(cr)

	if !cr.DeletionTimestamp.IsZero() {
		if err := driveRulesetDelete(ctx, r.CF, logger, cr.Spec.ZoneID, cloudflare.CustomFirewallPhase, "WAF custom rule", ref); err != nil {
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

	desired := renderWAFRule(cr, ref)
	out, err := driveRulesetReconcile(ctx, r.CF, logger, cr.Spec.ZoneID, cloudflare.CustomFirewallPhase, "WAF custom rule", desired)
	if err != nil {
		_ = writeRulesetStatus(ctx, r.Client, cr, &cr.Status, ref, out.RulesetID, out.RuleID, err.Error(), cr.Generation)
		return ctrl.Result{}, err
	}
	return finishRulesetReconcile(ctx, r.Client, cr, &cr.Status, ref, out.RulesetID, out.RuleID, out.Message, cr.Generation, r.ResyncInterval)
}

func wafRuleRef(cr *cfv1alpha1.CloudflareWAFCustomRule) string {
	return makeRef(wafRuleRefPrefix, cr.Name, string(cr.UID))
}

func renderWAFRule(cr *cfv1alpha1.CloudflareWAFCustomRule, ref string) cloudflare.Rule {
	return cloudflare.Rule{
		Action:      cr.Spec.Action,
		Expression:  cr.Spec.Expression,
		Description: cr.Spec.Description,
		Enabled:     cr.Spec.IsEnabled(),
		Ref:         ref,
	}
}

func (r *CloudflareWAFCustomRuleReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareWAFCustomRule{}).
		Complete(r)
}
