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
	"sigs.k8s.io/controller-runtime/pkg/log"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
)

// AICrawlControlAPI is the CF subset the AI Crawl Control reconciler
// consumes. Kept narrow so tests can stub it and so shape changes on
// the Cloudflare side are contained.
type AICrawlControlAPI interface {
	GetAICrawlControl(ctx context.Context, zoneID string) (json.RawMessage, error)
	UpdateAICrawlControl(ctx context.Context, zoneID string, config json.RawMessage) (json.RawMessage, error)
}

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareaicrawlcontrols,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflareaicrawlcontrols/status,verbs=get;update;patch

// CloudflareAICrawlControlReconciler pushes the CR-declared AI Crawl
// Control configuration to Cloudflare and mirrors what Cloudflare
// returns into the CR status so drift is visible in the cluster.
//
// AI Crawl Control's API shape is newer than the Rulesets API and has
// iterated; the reconciler therefore compares payloads byte-for-byte
// rather than field-by-field. That means a whitespace difference in a
// hand-edited CR would look like drift; keeping the CR under
// `kubectl apply -f` (as intended) sidesteps this.
type CloudflareAICrawlControlReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             AICrawlControlAPI
	ResyncInterval time.Duration
}

func (r *CloudflareAICrawlControlReconciler) resync() time.Duration {
	if r.ResyncInterval > 0 {
		return r.ResyncInterval
	}
	return defaultResyncInterval
}

func (r *CloudflareAICrawlControlReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflareaicrawlcontrol", req.Name)

	cr := &cfv1alpha1.CloudflareAICrawlControl{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !cr.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, nil
	}

	desired, err := cr.Spec.Config.MarshalJSON()
	if err != nil {
		return r.fail(ctx, cr, nil, fmt.Errorf("marshal desired config: %w", err))
	}

	current, err := r.CF.GetAICrawlControl(ctx, cr.Spec.ZoneID)
	if err != nil {
		return r.fail(ctx, cr, nil, fmt.Errorf("get AI crawl control config: %w", err))
	}

	if jsonEqual(current, desired) {
		return r.succeed(ctx, cr, current, "in sync")
	}

	updated, err := r.CF.UpdateAICrawlControl(ctx, cr.Spec.ZoneID, desired)
	if err != nil {
		return r.fail(ctx, cr, current, fmt.Errorf("update AI crawl control config: %w", err))
	}
	logger.Info("updated AI crawl control config", "zoneId", cr.Spec.ZoneID)
	return r.succeed(ctx, cr, updated, "updated")
}

func (r *CloudflareAICrawlControlReconciler) succeed(ctx context.Context, cr *cfv1alpha1.CloudflareAICrawlControl, observed json.RawMessage, message string) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, observed, message); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.resync()}, nil
}

func (r *CloudflareAICrawlControlReconciler) fail(ctx context.Context, cr *cfv1alpha1.CloudflareAICrawlControl, observed json.RawMessage, cause error) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, observed, cause.Error()); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, cause
}

func (r *CloudflareAICrawlControlReconciler) setStatus(ctx context.Context, cr *cfv1alpha1.CloudflareAICrawlControl, observed json.RawMessage, message string) error {
	now := metav1.NewTime(time.Now().UTC())
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.ObservedConfig = cfv1alpha1.NewRawJSON(observed)
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

func (r *CloudflareAICrawlControlReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareAICrawlControl{}).
		Complete(r)
}
