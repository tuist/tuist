package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	corev1 "k8s.io/api/core/v1"
)

const gracefulDrainAnnotation = "tuist.dev/graceful-drain"

// drainPod never waits inside the sole reconcile worker. Its request lives
// beside the VM, so an agent restart resumes the same drain. Failure keeps the
// finalizer and VM: an elapsed grace period is not proof that a job finished.
// Explicit force deletion (zero grace) remains the operator's escape hatch.
func (r *Reconciler) drainPod(ctx context.Context, pod *corev1.Pod) (bool, error) {
	if pod.Annotations[gracefulDrainAnnotation] != "xcresult-v1" ||
		(pod.DeletionGracePeriodSeconds != nil && *pod.DeletionGracePeriodSeconds == 0) {
		return false, nil
	}
	entry := r.Store.Get(pod.Namespace, pod.Name)
	if entry == nil {
		return false, nil
	}
	if entry.Run != nil {
		if _, exited := entry.Run.Exited(); exited {
			return false, nil
		}
		if !drainRequested(entry.StatusDir) && neverServed(pod, entry) {
			return false, nil
		}
	} else {
		running, err := r.Tart.IsRunning(ctx, entry.VMName)
		if err != nil {
			return true, err
		}
		if !running {
			return false, nil
		}
	}
	if entry.StatusDir == "" {
		return true, fmt.Errorf("VM has no drain status share")
	}
	return requestGuestDrain(entry.StatusDir, string(pod.UID))
}

// neverServed reports whether a VM this agent booted never passed its
// readinessProbe: it never had an IP, or the guest answers and has never
// passed. The
// processor's /ready requires Postgres, ClickHouse and an unpaused queue, so
// such a guest has no work to drain, and a release that cannot start would
// never acknowledge. A recovered VM's earlier readiness is unknown, so callers
// only ask for VMs with a Run handle.
func neverServed(pod *corev1.Pod, entry *Entry) bool {
	if probe, err := readinessProbeFor(pod); probe == nil || err != nil {
		return false
	}
	return entry.Readiness == nil || entry.Readiness.NeverReady()
}

// drainRequested reports whether a drain request is already in the share. A
// draining guest pauses its queue, which fails /ready, so once requested a
// failing probe no longer means the guest never served.
func drainRequested(dir string) bool {
	if dir == "" {
		return false
	}
	_, err := os.Lstat(filepath.Join(dir, "drain-request"))
	return !os.IsNotExist(err)
}

func requestGuestDrain(dir, uid string) (bool, error) {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return true, err
	}
	defer root.Close()
	request := []byte(uid + "\n")
	f, err := root.OpenFile("drain-request", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err == nil {
		_, writeErr := f.Write(request)
		closeErr := f.Close()
		if err := errors.Join(writeErr, closeErr); err != nil {
			return true, err
		}
	} else if !os.IsExist(err) {
		return true, err
	}
	existing, ok := readGuestFile(dir, "drain-request", 128)
	if !ok || string(existing) != string(request) {
		return true, fmt.Errorf("drain request does not match this Pod UID")
	}
	reply, ok := readGuestFile(dir, "drain-complete", 128)
	return !ok || string(reply) != string(request), nil
}
