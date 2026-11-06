package podagent

import (
	"context"
	"math"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// Boot stage markers the guest writes into the status share. Their mtimes are
// stamped by the host, so they share a clock with the host-side stages.
const (
	bootAgentFile     = "boot-agent"
	bootPollerFile    = "boot-poller"
	bootFirstPollFile = "boot-first-poll"
)

func readBootMark(statusDir, name string) (time.Time, bool) {
	f, fi, ok := openGuestFile(statusDir, name)
	if !ok {
		return time.Time{}, false
	}
	f.Close()
	return fi.ModTime(), true
}

// bootTimingFields returns how long each stage from Pod creation to the guest's
// first dispatch poll took, as log key-value pairs. False until the guest has
// polled. Stages with a missing marker are left out.
func bootTimingFields(created, run, ip time.Time, statusDir string) ([]any, bool) {
	firstPoll, ok := readBootMark(statusDir, bootFirstPollFile)
	if !ok {
		return nil, false
	}
	agent, _ := readBootMark(statusDir, bootAgentFile)
	poller, _ := readBootMark(statusDir, bootPollerFile)

	stages := []struct {
		key      string
		from, to time.Time
	}{
		{"createdToRun", created, run},
		{"runToIP", run, ip},
		{"ipToAgent", ip, agent},
		{"agentToPoller", agent, poller},
		{"pollerToFirstPoll", poller, firstPoll},
		{"runToFirstPoll", run, firstPoll},
		{"createdToFirstPoll", created, firstPoll},
	}
	fields := make([]any, 0, 2*len(stages))
	for _, s := range stages {
		if s.from.IsZero() || s.to.IsZero() {
			continue
		}
		fields = append(fields, s.key, math.Round(s.to.Sub(s.from).Seconds()*100)/100)
	}
	return fields, true
}

// logBootTiming logs the boot stages of a VM this host started, once, after the
// guest's first dispatch poll.
func (r *Reconciler) logBootTiming(ctx context.Context, pod *corev1.Pod) {
	entry := r.Store.Get(pod.Namespace, pod.Name)
	if entry == nil || entry.BootTimingLogged || entry.IPAt.IsZero() {
		return
	}
	fields, ok := bootTimingFields(pod.CreationTimestamp.Time, entry.StartTS.Time, entry.IPAt, entry.StatusDir)
	if !ok {
		return
	}
	entry.BootTimingLogged = true
	fields = append(fields, "vm", entry.VMName, "pool", pod.Labels["tuist.dev/runner-pool"])
	log.FromContext(ctx).Info("runner boot", fields...)
}
