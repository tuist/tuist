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
)

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
		// Windows nothing was observed in stay empty rather than being
		// backfilled, so a gap contributes no peak of its own.
		for i := 1; i < steps; i++ {
			next.BucketPeaksMilli = append(next.BucketPeaksMilli, 0)
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
	if want < current && len(state.BucketPeaksMilli) >= cpuShrinkMinBuckets {
		return want
	}
	return current
}

func cpuBand(milli int64) int32 {
	for _, band := range cpuRequestBands {
		if milli <= int64(band) {
			return band
		}
	}
	return cpuRequestBands[len(cpuRequestBands)-1]
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
	if a := instance.Status.CPUAutosize; a != nil && a.RequestMilli > 0 {
		return a.RequestMilli
	}
	return cpuColdStartMilli
}
