package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func writeLogdWedged(t *testing.T, dir string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, logdWedgedFile), []byte("2026-10-30T09:47:00Z\n"), 0o644); err != nil {
		t.Fatalf("write %s: %v", logdWedgedFile, err)
	}
}

func TestRunnerTerminationReportsAWedgedLogd(t *testing.T) {
	dir := t.TempDir()
	writeLogdWedged(t, dir)

	code, reason := (&Reconciler{}).runnerTermination(&Entry{StatusDir: dir}, nil)

	if code != 1 || reason != runnerExitReasonLogdWedged {
		t.Fatalf("runnerTermination = %d/%q, want 1/%q", code, reason, runnerExitReasonLogdWedged)
	}
}

func TestRunnerTerminationPrefersTheGuestReportOverAWedgedLogd(t *testing.T) {
	dir := t.TempDir()
	writeLogdWedged(t, dir)
	if err := os.WriteFile(filepath.Join(dir, runnerExitFile), []byte("0"), 0o644); err != nil {
		t.Fatal(err)
	}

	code, reason := (&Reconciler{}).runnerTermination(&Entry{StatusDir: dir}, nil)

	if code != 0 || reason != runnerExitReasonCompleted {
		t.Fatalf("runnerTermination = %d/%q, want 0/%q", code, reason, runnerExitReasonCompleted)
	}
}

func TestStopWedgedGuest(t *testing.T) {
	setup := func(t *testing.T, wedged bool) (*Reconciler, *corev1.Pod, string) {
		t.Helper()
		dir := t.TempDir()
		calls := filepath.Join(dir, "calls")
		bin := filepath.Join(dir, "faketart")
		if err := os.WriteFile(bin, []byte("#!/bin/sh\necho \"$@\" >>"+calls+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
		statusDir := filepath.Join(dir, "status")
		if err := os.MkdirAll(statusDir, 0o755); err != nil {
			t.Fatal(err)
		}
		if wedged {
			writeLogdWedged(t, statusDir)
		}
		pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-wedged"}}
		store := NewStore()
		store.Put(pod.Namespace, pod.Name, &Entry{VMName: "vm-wedged", StatusDir: statusDir})
		return &Reconciler{Tart: &tart.Client{Binary: bin}, Store: store}, pod, calls
	}
	readCalls := func(path string) []string {
		b, _ := os.ReadFile(path)
		if len(b) == 0 {
			return nil
		}
		return strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	}

	t.Run("stops a VM whose guest reported a wedged logd, once", func(t *testing.T) {
		r, pod, calls := setup(t, true)

		r.stopWedgedGuest(context.Background(), pod)
		r.stopWedgedGuest(context.Background(), pod)

		want := []string{"stop vm-wedged --timeout 1"}
		deadline := time.Now().Add(5 * time.Second)
		for len(readCalls(calls)) == 0 && time.Now().Before(deadline) {
			time.Sleep(10 * time.Millisecond)
		}
		time.Sleep(100 * time.Millisecond)
		got := readCalls(calls)
		if strings.Join(got, "\n") != strings.Join(want, "\n") {
			t.Fatalf("tart calls = %q, want one %q", got, want)
		}
		if !r.Store.Get(pod.Namespace, pod.Name).LogdWedgedStopped {
			t.Fatal("entry not marked as stopping")
		}
	})

	t.Run("leaves a healthy guest running", func(t *testing.T) {
		r, pod, calls := setup(t, false)

		r.stopWedgedGuest(context.Background(), pod)

		time.Sleep(100 * time.Millisecond)
		if got := readCalls(calls); len(got) != 0 {
			t.Fatalf("tart calls = %q, want none", got)
		}
	})
}
