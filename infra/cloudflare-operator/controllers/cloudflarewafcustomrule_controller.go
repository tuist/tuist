package controllers

import (
	"context"
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

func (r *CloudflareWAFCustomRuleReconciler) resync() time.Duration {
	if r.ResyncInterval > 0 {
		return r.ResyncInterval
	}
	return defaultResyncInterval
}

func (r *CloudflareWAFCustomRuleReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarewafcustomrule", req.Name)

	cr := &cfv1alpha1.CloudflareWAFCustomRule{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	ref := wafRuleRef(cr)

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

	rs, err := ensurePhaseRuleset(ctx, r.CF, cr.Spec.ZoneID, cloudflare.CustomFirewallPhase)
	if err != nil {
		return r.fail(ctx, cr, ref, "", "", err)
	}

	desired := renderWAFRule(cr, ref)
	existing := cloudflare.FindRuleByRef(rs, ref)

	switch {
	case existing == nil:
		updated, err := r.CF.AddRule(ctx, cr.Spec.ZoneID, rs.ID, desired)
		if err != nil {
			return r.fail(ctx, cr, ref, rs.ID, "", fmt.Errorf("add WAF custom rule: %w", err))
		}
		created := cloudflare.FindRuleByRef(updated, ref)
		logger.Info("created WAF custom rule", "rulesetId", rs.ID, "ruleId", ruleIDOf(created), "ref", ref)
		return r.succeed(ctx, cr, ref, rs.ID, ruleIDOf(created), "created")

	case rulesetRuleDiffers(existing, &desired):
		updated, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rs.ID, existing.ID, desired)
		if err != nil {
			return r.fail(ctx, cr, ref, rs.ID, existing.ID, fmt.Errorf("update WAF custom rule: %w", err))
		}
		patched := cloudflare.FindRuleByRef(updated, ref)
		logger.Info("updated WAF custom rule", "rulesetId", rs.ID, "ruleId", ruleIDOf(patched), "ref", ref)
		return r.succeed(ctx, cr, ref, rs.ID, ruleIDOf(patched), "updated")

	default:
		return r.succeed(ctx, cr, ref, rs.ID, existing.ID, "in sync")
	}
}

func (r *CloudflareWAFCustomRuleReconciler) reconcileDelete(ctx context.Context, cr *cfv1alpha1.CloudflareWAFCustomRule, ref string) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarewafcustomrule", cr.Name)
	if !controllerutil.ContainsFinalizer(cr, finalizer) {
		return ctrl.Result{}, nil
	}
	rs, err := r.CF.GetPhaseRuleset(ctx, cr.Spec.ZoneID, cloudflare.CustomFirewallPhase)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("get ruleset for delete: %w", err)
	}
	if rs != nil {
		if existing := cloudflare.FindRuleByRef(rs, ref); existing != nil {
			if err := r.CF.DeleteRule(ctx, cr.Spec.ZoneID, rs.ID, existing.ID); err != nil {
				return ctrl.Result{}, fmt.Errorf("delete WAF custom rule: %w", err)
			}
			logger.Info("deleted WAF custom rule", "rulesetId", rs.ID, "ruleId", existing.ID, "ref", ref)
		}
	}
	controllerutil.RemoveFinalizer(cr, finalizer)
	if err := r.Update(ctx, cr); err != nil {
		return ctrl.Result{}, fmt.Errorf("remove finalizer: %w", err)
	}
	return ctrl.Result{}, nil
}

func (r *CloudflareWAFCustomRuleReconciler) succeed(ctx context.Context, cr *cfv1alpha1.CloudflareWAFCustomRule, ref, rulesetID, ruleID, message string) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, ref, rulesetID, ruleID, message); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.resync()}, nil
}

func (r *CloudflareWAFCustomRuleReconciler) fail(ctx context.Context, cr *cfv1alpha1.CloudflareWAFCustomRule, ref, rulesetID, ruleID string, cause error) (ctrl.Result, error) {
	message := cause.Error()
	if statusErr := r.setStatus(ctx, cr, ref, rulesetID, ruleID, message); statusErr != nil {
		return ctrl.Result{}, statusErr
	}
	return ctrl.Result{}, cause
}

func (r *CloudflareWAFCustomRuleReconciler) setStatus(ctx context.Context, cr *cfv1alpha1.CloudflareWAFCustomRule, ref, rulesetID, ruleID, message string) error {
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
