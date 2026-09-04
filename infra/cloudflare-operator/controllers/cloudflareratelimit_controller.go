// Package controllers holds the reconcilers for the Cloudflare
// operator. Each reconciler owns one CRD and keeps its live Cloudflare
// counterpart in sync with the CR spec. The pattern is stateless: no
// separate state backend, no client-side ids to track. The operator
// finds its rules by a stable Ref it sets on Cloudflare and computes
// the delta on every reconcile.
package controllers

import (
	"context"
	"fmt"
	"reflect"
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

const (
	defaultResyncInterval = 5 * time.Minute

	// finalizer runs the Cloudflare-side delete when a CR is removed so
	// the live rule follows the CR through git deletions.
	finalizer = "cloudflare.tuist.dev/finalizer"

	// refPrefix keeps the operator's rule refs distinguishable from any
	// hand-created rule in the same ruleset.
	refPrefix = "cfop_"
)

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareratelimits,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareratelimits/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareratelimits/finalizers,verbs=update

// CloudflareRateLimitReconciler drives one CloudflareRateLimit toward
// its Cloudflare counterpart.
type CloudflareRateLimitReconciler struct {
	client.Client
	Scheme *runtime.Scheme
	CF     RateLimitAPI

	// ResyncInterval is the requeue after a successful reconcile so the
	// operator corrects dashboard drift without waiting for a spec edit.
	ResyncInterval time.Duration
}

// RateLimitAPI is the subset of the Cloudflare client the reconciler
// depends on. Kept narrow so tests can stub it.
type RateLimitAPI interface {
	GetRateLimitRuleset(ctx context.Context, zoneID string) (*cloudflare.Ruleset, error)
	CreateRateLimitRuleset(ctx context.Context, zoneID string) (*cloudflare.Ruleset, error)
	AddRule(ctx context.Context, zoneID, rulesetID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	UpdateRule(ctx context.Context, zoneID, rulesetID, ruleID string, rule cloudflare.Rule) (*cloudflare.Ruleset, error)
	DeleteRule(ctx context.Context, zoneID, rulesetID, ruleID string) error
}

func (r *CloudflareRateLimitReconciler) resync() time.Duration {
	if r.ResyncInterval > 0 {
		return r.ResyncInterval
	}
	return defaultResyncInterval
}

func (r *CloudflareRateLimitReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflareratelimit", req.Name)

	cr := &cfv1alpha1.CloudflareRateLimit{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	ref := ruleRef(cr)

	if !cr.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, cr, ref)
	}

	if !controllerutil.ContainsFinalizer(cr, finalizer) {
		controllerutil.AddFinalizer(cr, finalizer)
		if err := r.Update(ctx, cr); err != nil {
			return ctrl.Result{}, fmt.Errorf("add finalizer: %w", err)
		}
		// Update triggers a fresh reconcile; nothing else to do this pass.
		return ctrl.Result{}, nil
	}

	rs, err := r.ensureRuleset(ctx, cr.Spec.ZoneID)
	if err != nil {
		return r.fail(ctx, cr, ref, "", "", err)
	}

	desired := renderRule(cr, ref)
	existing := cloudflare.FindRuleByRef(rs, ref)

	switch {
	case existing == nil:
		updated, err := r.CF.AddRule(ctx, cr.Spec.ZoneID, rs.ID, desired)
		if err != nil {
			return r.fail(ctx, cr, ref, rs.ID, "", fmt.Errorf("add rule: %w", err))
		}
		created := cloudflare.FindRuleByRef(updated, ref)
		logger.Info("created rate limit rule", "rulesetId", rs.ID, "ruleId", ruleIDOf(created), "ref", ref)
		return r.succeed(ctx, cr, ref, rs.ID, ruleIDOf(created), "created")

	case ruleDiffers(existing, &desired):
		updated, err := r.CF.UpdateRule(ctx, cr.Spec.ZoneID, rs.ID, existing.ID, desired)
		if err != nil {
			return r.fail(ctx, cr, ref, rs.ID, existing.ID, fmt.Errorf("update rule: %w", err))
		}
		patched := cloudflare.FindRuleByRef(updated, ref)
		logger.Info("updated rate limit rule", "rulesetId", rs.ID, "ruleId", ruleIDOf(patched), "ref", ref)
		return r.succeed(ctx, cr, ref, rs.ID, ruleIDOf(patched), "updated")

	default:
		return r.succeed(ctx, cr, ref, rs.ID, existing.ID, "in sync")
	}
}

func (r *CloudflareRateLimitReconciler) reconcileDelete(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, ref string) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflareratelimit", cr.Name)
	if !controllerutil.ContainsFinalizer(cr, finalizer) {
		return ctrl.Result{}, nil
	}

	rs, err := r.CF.GetRateLimitRuleset(ctx, cr.Spec.ZoneID)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("get ruleset for delete: %w", err)
	}
	if rs != nil {
		if existing := cloudflare.FindRuleByRef(rs, ref); existing != nil {
			if err := r.CF.DeleteRule(ctx, cr.Spec.ZoneID, rs.ID, existing.ID); err != nil {
				return ctrl.Result{}, fmt.Errorf("delete rule: %w", err)
			}
			logger.Info("deleted rate limit rule", "rulesetId", rs.ID, "ruleId", existing.ID, "ref", ref)
		}
	}
	controllerutil.RemoveFinalizer(cr, finalizer)
	if err := r.Update(ctx, cr); err != nil {
		return ctrl.Result{}, fmt.Errorf("remove finalizer: %w", err)
	}
	return ctrl.Result{}, nil
}

// ensureRuleset returns the zone's http_ratelimit entrypoint ruleset,
// creating it if Cloudflare has none yet. Creation happens lazily so a
// zone that has never had a rate limit rule doesn't require operator
// bootstrapping to be viable.
func (r *CloudflareRateLimitReconciler) ensureRuleset(ctx context.Context, zoneID string) (*cloudflare.Ruleset, error) {
	rs, err := r.CF.GetRateLimitRuleset(ctx, zoneID)
	if err != nil {
		return nil, fmt.Errorf("get ruleset: %w", err)
	}
	if rs != nil {
		return rs, nil
	}
	created, err := r.CF.CreateRateLimitRuleset(ctx, zoneID)
	if err != nil {
		return nil, fmt.Errorf("create ruleset: %w", err)
	}
	return created, nil
}

func (r *CloudflareRateLimitReconciler) succeed(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, ref, rulesetID, ruleID, message string) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, ref, rulesetID, ruleID, message); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.resync()}, nil
}

func (r *CloudflareRateLimitReconciler) fail(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, ref, rulesetID, ruleID string, cause error) (ctrl.Result, error) {
	message := cause.Error()
	if statusErr := r.setStatus(ctx, cr, ref, rulesetID, ruleID, message); statusErr != nil {
		return ctrl.Result{}, statusErr
	}
	return ctrl.Result{}, cause
}

func (r *CloudflareRateLimitReconciler) setStatus(ctx context.Context, cr *cfv1alpha1.CloudflareRateLimit, ref, rulesetID, ruleID, message string) error {
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

// ruleRef derives the operator's stable identifier for a CR, used as
// the Cloudflare rule's Ref so subsequent reconciles find the same rule
// without a state backend. Includes the UID to survive a delete + same-
// name recreate cleanly.
func ruleRef(cr *cfv1alpha1.CloudflareRateLimit) string {
	uid := string(cr.UID)
	if len(uid) > 12 {
		uid = uid[:12]
	}
	return fmt.Sprintf("%s%s_%s", refPrefix, cr.Name, uid)
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

// ruleDiffers compares only the fields the operator sets, ignoring
// server-side ones (ID, Version, LastUpdated) so a semantically equal
// rule doesn't cause a needless PATCH on every resync.
func ruleDiffers(a, b *cloudflare.Rule) bool {
	if a == nil || b == nil {
		return a != b
	}
	if a.Action != b.Action ||
		a.Expression != b.Expression ||
		a.Description != b.Description ||
		a.Enabled != b.Enabled ||
		a.Ref != b.Ref {
		return true
	}
	return !reflect.DeepEqual(a.RateLimit, b.RateLimit)
}

func ruleIDOf(r *cloudflare.Rule) string {
	if r == nil {
		return ""
	}
	return r.ID
}

func (r *CloudflareRateLimitReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareRateLimit{}).
		Complete(r)
}
