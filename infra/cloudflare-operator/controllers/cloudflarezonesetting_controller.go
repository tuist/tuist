package controllers

import (
	"bytes"
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
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// ZoneSettingAPI is the CF subset the zone-setting reconciler uses.
type ZoneSettingAPI interface {
	GetZoneSetting(ctx context.Context, zoneID, settingID string) (*cloudflare.ZoneSetting, error)
	UpdateZoneSetting(ctx context.Context, zoneID, settingID string, value json.RawMessage) (*cloudflare.ZoneSetting, error)
}

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarezonesettings,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarezonesettings/status,verbs=get;update;patch

// CloudflareZoneSettingReconciler pins one zone setting to a desired
// value. Zone settings are not deleted individually (Cloudflare has a
// concept of "default", not "absent"), so this reconciler has no
// finalizer: removing the CR just stops managing that setting; it does
// not revert Cloudflare to a default.
type CloudflareZoneSettingReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             ZoneSettingAPI
	ResyncInterval time.Duration
}

func (r *CloudflareZoneSettingReconciler) resync() time.Duration {
	if r.ResyncInterval > 0 {
		return r.ResyncInterval
	}
	return defaultResyncInterval
}

func (r *CloudflareZoneSettingReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarezonesetting", req.Name)

	cr := &cfv1alpha1.CloudflareZoneSetting{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// Deleted CRs just stop syncing; the setting stays where it is.
	// Documented in the CRD moduledoc; changing this would risk
	// reverting a compliance-critical setting on a `kubectl delete`.
	if !cr.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, nil
	}

	desiredValue, err := cr.Spec.Value.MarshalJSON()
	if err != nil {
		return r.fail(ctx, cr, nil, fmt.Errorf("marshal desired value: %w", err))
	}

	current, err := r.CF.GetZoneSetting(ctx, cr.Spec.ZoneID, cr.Spec.SettingID)
	if err != nil {
		return r.fail(ctx, cr, nil, fmt.Errorf("get setting: %w", err))
	}

	if current != nil && bytes.Equal(current.Value, desiredValue) {
		return r.succeed(ctx, cr, current.Value, "in sync")
	}

	updated, err := r.CF.UpdateZoneSetting(ctx, cr.Spec.ZoneID, cr.Spec.SettingID, desiredValue)
	if err != nil {
		return r.fail(ctx, cr, currentValue(current), fmt.Errorf("update setting: %w", err))
	}
	logger.Info("updated zone setting", "settingId", cr.Spec.SettingID)
	return r.succeed(ctx, cr, updated.Value, "updated")
}

func (r *CloudflareZoneSettingReconciler) succeed(ctx context.Context, cr *cfv1alpha1.CloudflareZoneSetting, observed json.RawMessage, message string) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, observed, message); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.resync()}, nil
}

func (r *CloudflareZoneSettingReconciler) fail(ctx context.Context, cr *cfv1alpha1.CloudflareZoneSetting, observed json.RawMessage, cause error) (ctrl.Result, error) {
	if err := r.setStatus(ctx, cr, observed, cause.Error()); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{}, cause
}

func (r *CloudflareZoneSettingReconciler) setStatus(ctx context.Context, cr *cfv1alpha1.CloudflareZoneSetting, observed json.RawMessage, message string) error {
	now := metav1.NewTime(time.Now().UTC())
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.ObservedValue = cfv1alpha1.NewRawJSON(observed)
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

func currentValue(s *cloudflare.ZoneSetting) json.RawMessage {
	if s == nil {
		return nil
	}
	return s.Value
}

func (r *CloudflareZoneSettingReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareZoneSetting{}).
		Complete(r)
}
