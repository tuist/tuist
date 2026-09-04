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
// finalizer: removing the CR just stops managing that setting; it
// does not revert Cloudflare to a default.
type CloudflareZoneSettingReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             ZoneSettingAPI
	ResyncInterval time.Duration
}

func (r *CloudflareZoneSettingReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarezonesetting", req.Name)

	cr := &cfv1alpha1.CloudflareZoneSetting{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	if !cr.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, nil
	}

	desired, err := cr.Spec.Value.MarshalJSON()
	if err != nil {
		_ = writeSettingsStatus(ctx, r.Client, cr, &cr.Status, nil, fmt.Errorf("marshal desired value: %w", err).Error(), cr.Generation)
		return ctrl.Result{}, err
	}

	get := func(ctx context.Context, zoneID string) (json.RawMessage, error) {
		s, err := r.CF.GetZoneSetting(ctx, zoneID, cr.Spec.SettingID)
		if err != nil {
			return nil, err
		}
		if s == nil {
			return nil, nil
		}
		return s.Value, nil
	}
	upd := func(ctx context.Context, zoneID string, v json.RawMessage) (json.RawMessage, error) {
		s, err := r.CF.UpdateZoneSetting(ctx, zoneID, cr.Spec.SettingID, v)
		if err != nil {
			return nil, err
		}
		return s.Value, nil
	}

	out, err := driveSettingsReconcile(ctx, logger, cr.Spec.ZoneID, "zone setting "+cr.Spec.SettingID, desired, get, upd)
	if err != nil {
		_ = writeSettingsStatus(ctx, r.Client, cr, &cr.Status, out.Observed, err.Error(), cr.Generation)
		return ctrl.Result{}, err
	}
	return finishSettingsReconcile(ctx, r.Client, cr, &cr.Status, out.Observed, out.Message, cr.Generation, r.ResyncInterval)
}

func (r *CloudflareZoneSettingReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareZoneSetting{}).
		Complete(r)
}
