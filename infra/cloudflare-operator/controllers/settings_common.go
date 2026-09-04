package controllers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// SettingsStatusWriter is what every settings-shaped CRD's status
// implements so the shared reconciler can write into it uniformly.
type SettingsStatusWriter interface {
	SetSettingsStatus(observed json.RawMessage, message string, generation int64, now *metav1.Time)
}

// SettingsReconcileOutcome carries what the shared settings reconcile
// pass hands back to a per-CRD reconciler.
type SettingsReconcileOutcome struct {
	Observed json.RawMessage
	Message  string
}

// driveSettingsReconcile runs the GET-then-diff-then-PATCH/PUT loop
// shared by the two settings-shaped CRDs (zone setting, AI Crawl
// Control). getCurrent and update are the CRD-specific Cloudflare
// calls; kindLabel goes into log lines.
func driveSettingsReconcile(
	ctx context.Context,
	log logr.Logger,
	zoneID, kindLabel string,
	desired json.RawMessage,
	getCurrent func(context.Context, string) (json.RawMessage, error),
	update func(context.Context, string, json.RawMessage) (json.RawMessage, error),
) (SettingsReconcileOutcome, error) {
	current, err := getCurrent(ctx, zoneID)
	if err != nil {
		return SettingsReconcileOutcome{}, fmt.Errorf("get %s: %w", kindLabel, err)
	}
	if bytes.Equal(current, desired) {
		return SettingsReconcileOutcome{Observed: current, Message: "in sync"}, nil
	}
	updated, err := update(ctx, zoneID, desired)
	if err != nil {
		return SettingsReconcileOutcome{Observed: current}, fmt.Errorf("update %s: %w", kindLabel, err)
	}
	log.Info("updated "+kindLabel, "zoneId", zoneID)
	return SettingsReconcileOutcome{Observed: updated, Message: "updated"}, nil
}

// writeSettingsStatus stamps the shared settings status fields on the
// CR and PATCHes the status subresource. Not-found on the CR itself
// is treated as gone rather than an error.
func writeSettingsStatus(
	ctx context.Context,
	c client.Client,
	cr client.Object,
	writer SettingsStatusWriter,
	observed json.RawMessage,
	message string,
	generation int64,
) error {
	now := metav1.NewTime(time.Now().UTC())
	patch := client.MergeFrom(cr.DeepCopyObject().(client.Object))
	writer.SetSettingsStatus(observed, message, generation, &now)
	if err := c.Status().Patch(ctx, cr, patch); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("patch status: %w", err)
	}
	return nil
}

// finishSettingsReconcile writes the status and requeues.
func finishSettingsReconcile(
	ctx context.Context,
	c client.Client,
	cr client.Object,
	writer SettingsStatusWriter,
	observed json.RawMessage,
	message string,
	generation int64,
	resync time.Duration,
) (ctrl.Result, error) {
	if err := writeSettingsStatus(ctx, c, cr, writer, observed, message, generation); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: resyncOrDefault(resync)}, nil
}
