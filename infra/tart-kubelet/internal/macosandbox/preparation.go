package macosandbox

import (
	"context"
	"errors"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const templatePreparationTimeout = time.Hour

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
		for {
			probeCtx, endProbe := context.WithTimeout(ctx, 3*time.Second)
			current, err := s.Kube.CoreV1().Pods(control.Namespace).Get(probeCtx, control.Name, metav1.GetOptions{})
			endProbe()
			if err != nil {
				cancel(fmt.Errorf("check preparing control Pod: %w", err))
				return
			}
			if current.UID != control.UID || !current.DeletionTimestamp.IsZero() || current.Annotations[ConfigAnnotation] != control.Annotations[ConfigAnnotation] {
				cancel(errors.New("preparing control Pod was removed or changed"))
				return
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
	return err
}
