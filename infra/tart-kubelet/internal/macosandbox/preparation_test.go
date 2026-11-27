package macosandbox

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestSlowPreparationCancelledWithControlIdentity(t *testing.T) {
	for _, change := range []string{"delete", "terminating", "replacement", "configuration", "shutdown"} {
		t.Run(change, func(t *testing.T) {
			control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "control", Namespace: Namespace, UID: "original", Annotations: map[string]string{ConfigAnnotation: "original"}}}
			k := fake.NewSimpleClientset(control)
			s := &Service{Kube: k}
			parent, stop := context.WithCancel(context.Background())
			defer stop()
			started, result := make(chan struct{}), make(chan error, 1)
			go func() {
				result <- s.withPreparingControl(parent, control, func(ctx context.Context) error {
					close(started)
					<-ctx.Done()
					return ctx.Err()
				})
			}()
			<-started
			updated := control.DeepCopy()
			switch change {
			case "delete":
				if err := k.CoreV1().Pods(Namespace).Delete(parent, control.Name, metav1.DeleteOptions{}); err != nil {
					t.Fatal(err)
				}
			case "shutdown":
				stop()
			default:
				switch change {
				case "terminating":
					now := metav1.Now()
					updated.DeletionTimestamp = &now
				case "replacement":
					updated.UID = "replacement"
				case "configuration":
					updated.Annotations[ConfigAnnotation] = "replacement"
				}
				if _, err := k.CoreV1().Pods(Namespace).Update(parent, updated, metav1.UpdateOptions{}); err != nil {
					t.Fatal(err)
				}
			}
			select {
			case err := <-result:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("preparation was not cancelled: %v", err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("slow preparation blocked control removal or shutdown")
			}
		})
	}
}

func TestPreparationSurvivesTransientControlLookup(t *testing.T) {
	control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "control", Namespace: Namespace, UID: "original"}}
	k := fake.NewSimpleClientset(control)
	firstProbe := make(chan struct{})
	var probes atomic.Int32
	k.PrependReactor("get", "pods", func(ktesting.Action) (bool, runtime.Object, error) {
		if probes.Add(1) == 1 {
			close(firstProbe)
			return true, nil, apierrors.NewServiceUnavailable("transient API outage")
		}
		return false, nil, nil
	})
	s := &Service{Kube: k}
	err := s.withPreparingControl(context.Background(), control, func(ctx context.Context) error {
		<-firstProbe
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
			return nil
		}
	})
	if err != nil {
		t.Fatalf("transient lookup aborted a healthy download: %v", err)
	}
	if probes.Load() < 2 {
		t.Fatal("preparation succeeded without a fresh control identity check")
	}
}

func TestPreparationMustRevalidateAfterDownload(t *testing.T) {
	for _, failure := range []string{"removed", "unavailable"} {
		t.Run(failure, func(t *testing.T) {
			control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "control", Namespace: Namespace, UID: "original"}}
			k := fake.NewSimpleClientset(control)
			var downloaded atomic.Bool
			k.PrependReactor("get", "pods", func(ktesting.Action) (bool, runtime.Object, error) {
				if failure == "unavailable" && downloaded.Load() {
					return true, nil, apierrors.NewServiceUnavailable("API unavailable at completion")
				}
				return false, nil, nil
			})
			s := &Service{Kube: k}
			err := s.withPreparingControl(context.Background(), control, func(ctx context.Context) error {
				if failure == "removed" {
					if err := k.CoreV1().Pods(Namespace).Delete(ctx, control.Name, metav1.DeleteOptions{}); err != nil {
						return err
					}
				}
				downloaded.Store(true)
				return nil
			})
			if err == nil {
				t.Fatal("prepared image declared ready without a valid current control identity")
			}
		})
	}
}

func TestPreparationHasSeparateBoundedDeadline(t *testing.T) {
	control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "control", Namespace: Namespace, UID: "original"}}
	s := &Service{Kube: fake.NewSimpleClientset(control)}
	err := s.withPreparingControl(context.Background(), control, func(ctx context.Context) error {
		deadline, ok := ctx.Deadline()
		if !ok || time.Until(deadline) < 59*time.Minute || time.Until(deadline) > time.Hour {
			t.Error("cold template preparation did not get its bounded one-hour deadline")
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

// A host whose new default image cannot be had serves the previous default it
// still holds, so a release no host staged does not take it out of placement.
// It never falls back for a control Pod that changed, an image it no longer
// holds, or without a default it served before.
func TestDefaultFallsBackToThePreviousImageTheHostHolds(t *testing.T) {
	const next, previous = "ghcr.io/tuist/tuist-runner@sha256:next", "ghcr.io/tuist/tuist-runner@sha256:previous"
	for name, c := range map[string]struct {
		recorded  string
		cached    []string
		changed   bool
		want      string
		wantError bool
	}{
		"new image prepared":            {recorded: previous, cached: []string{next, previous}, want: next},
		"new image unavailable":         {recorded: previous, cached: []string{previous}, want: previous},
		"previous no longer held":       {recorded: previous, cached: nil, wantError: true},
		"no previous default":           {cached: []string{previous}, wantError: true},
		"previous is the new image":     {recorded: next, cached: []string{previous}, wantError: true},
		"control Pod changed meanwhile": {recorded: previous, cached: []string{previous}, changed: true, wantError: true},
	} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			// list answers the cached images; pull always fails, as a host below
			// the disk floor or without the registry would.
			list := "["
			for i, image := range c.cached {
				if i > 0 {
					list += ","
				}
				list += fmt.Sprintf(`{"Name":%q,"Source":"OCI"}`, image)
			}
			list += "]"
			binary := filepath.Join(dir, "tart")
			script := fmt.Sprintf("#!/bin/sh\n[ \"$1\" = list ] && echo '%s' && exit 0\nexit 1\n", list)
			if err := os.WriteFile(binary, []byte(script), 0o700); err != nil {
				t.Fatal(err)
			}
			root := filepath.Join(dir, "root")
			if err := os.MkdirAll(root, 0o700); err != nil {
				t.Fatal(err)
			}
			if c.recorded != "" {
				if err := os.WriteFile(filepath.Join(root, defaultImageFile), []byte(c.recorded), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			control := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "control", Namespace: Namespace, UID: "control-1",
				Annotations: map[string]string{ConfigAnnotation: "configured"}}}
			stored := control.DeepCopy()
			if c.changed {
				stored.Annotations[ConfigAnnotation] = "reconfigured"
			}
			s := &Service{Kube: fake.NewSimpleClientset(stored), Root: root, CIStore: filepath.Join(dir, "ci")}
			runtime := &TartRuntime{Client: &tart.Client{Binary: binary, HomeDir: filepath.Join(dir, "home"), PullTimeout: time.Second}}
			if err := os.MkdirAll(runtime.Client.HomeDir, 0o700); err != nil {
				t.Fatal(err)
			}
			got, err := s.prepareDefault(context.Background(), control, runtime, next)
			if c.wantError {
				if err == nil {
					t.Fatalf("served %q instead of failing", got)
				}
				return
			}
			if err != nil || got != c.want {
				t.Fatalf("served %q, %v; want %q", got, err, c.want)
			}
			// Only a prepared default becomes the one to fall back to.
			recorded, _ := os.ReadFile(filepath.Join(root, defaultImageFile))
			if string(recorded) != c.want {
				t.Fatalf("recorded %q as the default served, want %q", recorded, c.want)
			}
		})
	}
}

// A host that predates the record learns its previous default from the
// configuration it served, and an existing record is never overwritten.
func TestRememberDefaultKeepsTheRecordedImage(t *testing.T) {
	root := t.TempDir()
	rememberDefault(root, []byte(`{"url":"https://tuist.dev","image":"ghcr.io/tuist/tuist-runner@sha256:old","template":"macos"}`))
	rememberDefault(root, []byte(`{"url":"https://tuist.dev","image":"ghcr.io/tuist/tuist-runner@sha256:new","template":"macos"}`))
	recorded, err := os.ReadFile(filepath.Join(root, defaultImageFile))
	if err != nil || string(recorded) != "ghcr.io/tuist/tuist-runner@sha256:old" {
		t.Fatalf("recorded %q, %v", recorded, err)
	}
}
