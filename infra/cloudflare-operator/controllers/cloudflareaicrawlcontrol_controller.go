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
// Control configuration to Cloudflare. AI Crawl Control's API shape
// is newer than the Rulesets API and has iterated; the reconciler
// therefore compares payloads byte-for-byte rather than
// field-by-field.
type CloudflareAICrawlControlReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             AICrawlControlAPI
	ResyncInterval time.Duration
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
		_ = writeSettingsStatus(ctx, r.Client, cr, &cr.Status, nil, fmt.Errorf("marshal desired config: %w", err).Error(), cr.Generation)
		return ctrl.Result{}, err
	}

	out, err := driveSettingsReconcile(ctx, logger, cr.Spec.ZoneID, "AI crawl control config", desired, r.CF.GetAICrawlControl, r.CF.UpdateAICrawlControl)
	if err != nil {
		_ = writeSettingsStatus(ctx, r.Client, cr, &cr.Status, out.Observed, err.Error(), cr.Generation)
		return ctrl.Result{}, err
	}
	return finishSettingsReconcile(ctx, r.Client, cr, &cr.Status, out.Observed, out.Message, cr.Generation, r.ResyncInterval)
}

func (r *CloudflareAICrawlControlReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareAICrawlControl{}).
		Complete(r)
}
