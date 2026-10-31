package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"

	corev1 "k8s.io/api/core/v1"
)

const gracefulDrainAnnotation = "tuist.dev/graceful-drain"

// servingMarkerAnnotation opts a Pod into the guest's serving marker: the
// guest writes it before it can first take a job, so its absence proves there
// is nothing to drain. Guests from before the marker leave it out of the Pod.
const servingMarkerAnnotation = "tuist.dev/graceful-drain-serving-marker"

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
	return requestGuestDrain(entry.StatusDir, string(pod.UID), pod.Annotations[servingMarkerAnnotation] == "true")
}

func requestGuestDrain(dir, uid string, marksServing bool) (bool, error) {
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
	// The guest writes its marker before it reads the request a last time and
	// resumes its queue, so reading the marker only after the request exists
	// means a guest without one can no longer take a job.
	if marksServing {
		if _, err := root.Lstat("serving"); os.IsNotExist(err) {
			return false, nil
		}
	}
	reply, ok := readGuestFile(dir, "drain-complete", 128)
	return !ok || string(reply) != string(request), nil
}
