package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
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

// defaultImageFile names the default template's image this host last served.
const defaultImageFile = "default-image"

// prepareDefault prepares the default template's image and answers the image
// the default serves. A host connects only once its default is prepared, so
// when the new image cannot be had yet (a cold pull below the disk floor, a
// failed pull) it serves the previous default while that is still in its
// store, and prepareTemplates switches it to the new one later. On 2026-11-27
// a deploy moved the default to an image 16 of 23 rack hosts had not staged
// and had no disk floor to pull, and they all left placement for as long.
func (s *Service) prepareDefault(parent context.Context, control *corev1.Pod, runtime *TartRuntime, image string) (string, error) {
	err := s.withPreparingControl(parent, control, func(ctx context.Context) error {
		return ensureImage(ctx, runtime.Client, s.CIStore, image)
	})
	if err == nil {
		return image, atomicFile(filepath.Join(s.Root, defaultImageFile), []byte(image))
	}
	// A removed or changed control Pod, or a stopping service, serves nothing.
	if parent.Err() != nil || s.checkPreparingControl(parent, control) != nil {
		return "", err
	}
	previous, readErr := os.ReadFile(filepath.Join(s.Root, defaultImageFile))
	if readErr != nil || len(previous) == 0 || string(previous) == image {
		return "", err
	}
	if cached, cacheErr := hasImage(parent, runtime.Client, string(previous)); cacheErr != nil || !cached {
		return "", err
	}
	slog.Warn("macOS sandbox default template not prepared yet; serving the previous default", "image", image, "previous", string(previous), "error", err)
	return string(previous), nil
}

// rememberDefault records the default of configData, the configuration this
// host served before, unless the host already records one. Hosts that
// predate defaultImageFile learn it from there.
func rememberDefault(root string, configData []byte) {
	path := filepath.Join(root, defaultImageFile)
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		return
	}
	var cfg Config
	if json.Unmarshal(configData, &cfg) != nil || cfg.Image == "" {
		return
	}
	if err := atomicFile(path, []byte(cfg.templates()[0].Image)); err != nil {
		slog.Warn("could not record the macOS sandbox default template", "error", err)
	}
}

// templateRetryInterval spaces retries of a template whose image could not be
// prepared yet, such as one that is not in the CI store on a host below the
// cold-pull disk floor.
var templateRetryInterval = 5 * time.Minute

// prepareTemplates prepares the templates after the default, one at a time,
// while the control Pod that configured them stays current, and adds each to
// templates once its image is in the sandbox store. Each one is usually a CI
// runner image the host already holds, so seeding it from the CI store takes
// seconds. A template that fails is retried after the others.
func (s *Service) prepareTemplates(ctx context.Context, control *corev1.Pod, runtime *TartRuntime, templates *Templates, pending []TemplateConfig) {
	for len(pending) > 0 {
		var failed []TemplateConfig
		for _, t := range pending {
			err := s.withPreparingControl(ctx, control, func(prepareCtx context.Context) error {
				return ensureImage(prepareCtx, runtime.Client, s.CIStore, t.Image)
			})
			if ctx.Err() != nil {
				return
			}
			if err != nil {
				slog.Warn("macOS sandbox template not prepared yet", "template", t.Template, "image", t.Image, "error", err)
				failed = append(failed, t)
				continue
			}
			templates.set(t.Template, t.Image)
			slog.Info("macOS sandbox template ready", "template", t.Template, "image", t.Image)
		}
		pending = failed
		if len(pending) == 0 {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(templateRetryInterval):
		}
	}
}
