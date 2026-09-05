package controllers

import (
	"context"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	cpuBucketDuration = 6 * time.Hour
	cpuBucketCount    = 28

	cpuHeadroomNumerator   = 5
	cpuHeadroomDenominator = 4

	cpuColdStartMilli = 100

	cpuShrinkMinBuckets = 8

	cpuScheduleCapTTL = 24 * time.Hour
)

// cpuUnobservedWindow marks a window that closed with no reading. It is
// distinct from a reading of zero, which an idle pod genuinely produces.
const cpuUnobservedWindow int32 = -1

// Requests land on a band so load drifting within one does not re-template
// the StatefulSet and roll its pods. The ends are the floor and the ceiling.
var cpuRequestBands = []int32{50, 75, 100, 150, 250, 400, 600, 1000, 1500, 2000, 3000}

// PodMetricsClient reads current per-pod CPU from the metrics.k8s.io
// aggregated API.
type PodMetricsClient interface {
	PodCPUMilli(ctx context.Context, namespace string, selector map[string]string) (map[string]int64, error)
}

func (r *KuraInstanceReconciler) observeCPUUsage(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) {
	if r.MetricsClient == nil || len(pods) == 0 {
		return
	}
	usage, err := r.MetricsClient.PodCPUMilli(ctx, instance.Namespace, selectorLabels(instance))
	if err != nil {
		log.FromContext(ctx).V(1).Info("failed to read Kura pod CPU usage", "error", err)
		return
	}

	var peak int64
	var reported bool
	for i := range pods {
		milli, ok := usage[pods[i].Name]
		if !ok {
			continue
		}
		reported = true
		if milli > peak {
			peak = milli
		}
	}
	// A reading that could not be taken is not a reading of zero: folding one
	// in would age real samples out of the ring and shrink the fleet.
	if !reported {
		return
	}

	instance.Status.CPUAutosize = observeCPUPeak(instance.Status.CPUAutosize, peak, time.Now())
}

func observeCPUPeak(state *kurav1alpha1.KuraInstanceCPUAutosize, peakMilli int64, now time.Time) *kurav1alpha1.KuraInstanceCPUAutosize {
	next := state.DeepCopy()
	if next == nil {
		next = &kurav1alpha1.KuraInstanceCPUAutosize{}
	}
	sample := clampMilli(peakMilli)
	start := now.UTC().Truncate(cpuBucketDuration)

	switch {
	case next.BucketStartedAt == nil || len(next.BucketPeaksMilli) == 0:
		next.BucketPeaksMilli = []int32{sample}
	case start.After(next.BucketStartedAt.Time):
		steps := int(start.Sub(next.BucketStartedAt.Time) / cpuBucketDuration)
		if steps > cpuBucketCount {
			steps = cpuBucketCount
		}
		// Windows nothing was observed in are marked rather than
		// backfilled: they contribute no peak, and they are not history
		// either, so a gap cannot pass the shrink gate on its own.
		for i := 1; i < steps; i++ {
			next.BucketPeaksMilli = append(next.BucketPeaksMilli, cpuUnobservedWindow)
		}
		next.BucketPeaksMilli = append(next.BucketPeaksMilli, sample)
	default:
		last := len(next.BucketPeaksMilli) - 1
		if sample > next.BucketPeaksMilli[last] {
			next.BucketPeaksMilli[last] = sample
		}
	}

	if overflow := len(next.BucketPeaksMilli) - cpuBucketCount; overflow > 0 {
		next.BucketPeaksMilli = next.BucketPeaksMilli[overflow:]
	}
	next.BucketStartedAt = &metav1.Time{Time: start}
	next.PeakMilli = 0
	for _, bucket := range next.BucketPeaksMilli {
		if bucket > next.PeakMilli {
			next.PeakMilli = bucket
		}
	}
	next.RequestMilli = nextCPURequestMilli(next)
	return next
}

func nextCPURequestMilli(state *kurav1alpha1.KuraInstanceCPUAutosize) int32 {
	want := cpuBand(int64(state.PeakMilli) * cpuHeadroomNumerator / cpuHeadroomDenominator)
	current := state.RequestMilli
	if current == 0 {
		current = cpuColdStartMilli
	}
	// Growth applies at once. Shrinkage waits for a ring long enough that an
	// instance which merely looks idle has been watched through a full day.
	if want > current {
		return want
	}
	if want < current && observedWindows(state) >= cpuShrinkMinBuckets {
		return want
	}
	return current
}

func observedWindows(state *kurav1alpha1.KuraInstanceCPUAutosize) int {
	observed := 0
	for _, bucket := range state.BucketPeaksMilli {
		if bucket != cpuUnobservedWindow {
			observed++
		}
	}
	return observed
}

func cpuBand(milli int64) int32 {
	for _, band := range cpuRequestBands {
		if milli <= int64(band) {
			return band
		}
	}
	return cpuRequestBands[len(cpuRequestBands)-1]
}

// bandBelow is the largest band under milli, floored at the ladder's first
// entry.
func bandBelow(milli int32) int32 {
	below := cpuRequestBands[0]
	for _, band := range cpuRequestBands {
		if band >= milli {
			break
		}
		below = band
	}
	return below
}

func clampMilli(milli int64) int32 {
	ceiling := int64(cpuRequestBands[len(cpuRequestBands)-1]) * cpuHeadroomDenominator
	switch {
	case milli < 0:
		return 0
	case milli > ceiling:
		return int32(ceiling)
	default:
		return int32(milli)
	}
}

func cpuRequestMilli(instance *kurav1alpha1.KuraInstance) int32 {
	state := instance.Status.CPUAutosize
	if state == nil {
		return cpuColdStartMilli
	}
	milli := state.RequestMilli
	if milli == 0 {
		milli = cpuColdStartMilli
	}
	if state.ScheduleCapMilli > 0 && state.ScheduleCapMilli < milli {
		return state.ScheduleCapMilli
	}
	return milli
}

// applyScheduleCap bounds the template request by what the scheduler has
// shown it will admit. A raise the node cannot fit deletes the running pod
// and leaves the replacement Pending, and a Pending pod reports no metrics,
// so the observation that asked for the raise would otherwise hold it
// forever. The cap is remembered, or the next pass would raise the request
// again and roll the pod straight back into Pending.
func applyScheduleCap(instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, now time.Time) {
	state := instance.Status.CPUAutosize
	if state == nil {
		state = &kurav1alpha1.KuraInstanceCPUAutosize{}
	}

	// The cap describes one moment's occupancy of one box, so it is
	// forgotten once that box has had time to change.
	if state.ScheduleCapSetAt != nil && now.Sub(state.ScheduleCapSetAt.Time) >= cpuScheduleCapTTL {
		state.ScheduleCapMilli = 0
		state.ScheduleCapSetAt = nil
	}

	var stuck, admitted int32
	for i := range pods {
		milli := podCPURequestMilli(&pods[i])
		if podUnschedulable(&pods[i]) {
			if stuck == 0 || milli < stuck {
				stuck = milli
			}
			continue
		}
		if pods[i].Spec.NodeName != "" && milli > admitted {
			admitted = milli
		}
	}

	if stuck > 0 {
		capped := bandBelow(stuck)
		// A scheduled sibling is proof of what fits, so recovery is one
		// step instead of a walk down the ladder.
		if admitted > 0 && admitted < capped {
			capped = admitted
		}
		if state.ScheduleCapMilli == 0 || capped < state.ScheduleCapMilli {
			state.ScheduleCapMilli = capped
			state.ScheduleCapSetAt = &metav1.Time{Time: now.UTC()}
		}
	}

	if state.ScheduleCapMilli == 0 && state.RequestMilli == 0 && len(state.BucketPeaksMilli) == 0 {
		return
	}
	instance.Status.CPUAutosize = state
}

func podUnschedulable(pod *corev1.Pod) bool {
	if pod.Status.Phase != corev1.PodPending {
		return false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodScheduled &&
			condition.Status == corev1.ConditionFalse &&
			condition.Reason == corev1.PodReasonUnschedulable {
			return true
		}
	}
	return false
}

func podCPURequestMilli(pod *corev1.Pod) int32 {
	for i := range pod.Spec.Containers {
		if pod.Spec.Containers[i].Name != kuraContainerName {
			continue
		}
		request := pod.Spec.Containers[i].Resources.Requests.Cpu()
		return int32(request.MilliValue())
	}
	return 0
}
