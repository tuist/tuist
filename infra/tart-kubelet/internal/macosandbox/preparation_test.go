package macosandbox

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
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
