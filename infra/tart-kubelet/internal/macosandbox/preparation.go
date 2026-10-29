package macosandbox

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const templatePreparationTimeout = time.Hour

var errPreparingControlChanged = errors.New("preparing control Pod was removed or changed")

// A slow cold pull must not prevent removing or replacing its control identity.
// Ownership reconciliation runs independently; only template preparation uses
// this longer deadline. Join the watcher before releasing the service's lock.
func (s *Service) withPreparingControl(parent context.Context, control *corev1.Pod, prepare func(context.Context) error) error {
	bounded, stop := context.WithTimeout(parent, templatePreparationTimeout)
	defer stop()
	ctx, cancel := context.WithCancelCause(bounded)
	done := make(chan struct{})
	go func() {
		defer close(done)
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		reportedFailure := false
		for {
			err := s.checkPreparingControl(ctx, control)
			if err != nil {
				if apierrors.IsNotFound(err) || apierrors.IsForbidden(err) || apierrors.IsUnauthorized(err) || errors.Is(err, errPreparingControlChanged) {
					cancel(err)
					return
				}
				// Fetching template bytes grants no VM capacity. Keep a healthy
				// download through transient API outages, then revalidate below
				// before permitting a native connection or readiness report.
				if !reportedFailure && ctx.Err() == nil {
					slog.Warn("retrying preparing control Pod check", "error", err)
				}
				reportedFailure = true
			} else {
				reportedFailure = false
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	defer func() { cancel(nil); <-done }()
	err := prepare(ctx)
	if ctx.Err() != nil {
		return errors.Join(err, ctx.Err(), context.Cause(ctx))
	}
	if err != nil {
		return err
	}
	return s.checkPreparingControl(ctx, control)
}

func (s *Service) checkPreparingControl(ctx context.Context, control *corev1.Pod) error {
	probeCtx, endProbe := context.WithTimeout(ctx, 3*time.Second)
	defer endProbe()
	current, err := s.Kube.CoreV1().Pods(control.Namespace).Get(probeCtx, control.Name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("check preparing control Pod: %w", err)
	}
	if current.UID != control.UID || !current.DeletionTimestamp.IsZero() || current.Annotations[ConfigAnnotation] != control.Annotations[ConfigAnnotation] {
		return errPreparingControlChanged
	}
	return nil
}
