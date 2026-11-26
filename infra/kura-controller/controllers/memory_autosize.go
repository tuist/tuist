package controllers

import (
	"context"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// Memory autosizing raises an instance's floor above the plan's when its
// foreground requests outgrow the admission pool Kura derives from the floor.
// It follows CPU autosizing's ring of six-hour windows, with two differences:
//
//   - The signal is the pool's demand, not usage. A pool sized from the floor
//     fills and sheds reads while the container is far from its memory
//     watermarks, so neither usage nor pressure sees the shortage.
//   - Bursts count. The demand Kura reports is already a one-to-two-minute
//     peak, and a single such burst is what shed thousands of reads, so there
//     is no ten-minute mean to pass first. A window grows the floor only once
//     it has shed memoryGrowthMinTimeouts requests, though, so a stray shed
//     does not.
//
// Kura reads the floor only at startup, so a new floor reaches the pool through
// the ordinary rolling update, one replica at a time. Growth applies at once;
// shrinkage waits for the same observed history CPU does, which keeps those
// restarts rare.
const (
	memoryHeadroomNumerator   = 5
	memoryHeadroomDenominator = 4

	// Kura caps the floor pool at the gap between its soft and hard
	// watermarks, a quarter of the ceiling. Raising the ceiling by four times
	// the floor increase keeps that cap from absorbing the raise.
	memoryCeilingPerFloorMib = 4

	// A window's demand may raise the floor only once the window has shed
	// this many requests: queued, then timed out. The same scale as the
	// reapi_materialization shed alert. Replayed against production, a window
	// of a few stray sheds would otherwise have raised three instances a full
	// band each, for two rolling restarts and a week of idle reservation.
	memoryGrowthMinTimeouts = 10
)

// Floors land on a band so demand drifting within one does not roll the pods.
var memoryFloorBands = []int32{256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384}

// The scheduler's NodeResourcesFit messages for the two memory dimensions a
// Kura pod requests: the native floor and, where the region bin-packs it, the
// ceiling's extended resource.
var insufficientMemoryPredicates = []string{
	"Insufficient memory",
	"Insufficient " + string(memoryCeilingResource),
}

func memoryAutosizeEnabled(instance *kurav1alpha1.KuraInstance) bool {
	floor, _ := specMemoryProfileMib(instance)
	return instance.Spec.MemoryFloorMaxMib > floor
}

// specMemoryProfileMib is the plan's floor and ceiling, with the controller
// defaults for an instance that carries no profile.
func specMemoryProfileMib(instance *kurav1alpha1.KuraInstance) (int32, int32) {
	floorMib := instance.Spec.MemoryFloorMib
	if floorMib <= 0 {
		floorMib = defaultMemoryFloorMib
	}
	ceilingMib := instance.Spec.MemoryCeilingMib
	if ceilingMib <= 0 {
		ceilingMib = defaultMemoryCeilingMib
	}
	// The API rejects a limit below its request, so a profile that inverts the
	// two would make every pod of the instance unadmittable. Clamping keeps the
	// floor authoritative: a reservation is a promise, a ceiling is headroom.
	if ceilingMib < floorMib {
		ceilingMib = floorMib
	}
	return floorMib, ceilingMib
}

// memoryProfileMib is the floor and ceiling the pod template requests: the
// plan's, raised by what the instance has been observed to need.
func memoryProfileMib(instance *kurav1alpha1.KuraInstance) (int32, int32) {
	floorMib, ceilingMib := specMemoryProfileMib(instance)
	state := instance.Status.MemoryAutosize
	if !memoryAutosizeEnabled(instance) || state == nil {
		return floorMib, ceilingMib
	}
	learned := state.FloorMib
	if state.ScheduleCapMib > 0 && learned > state.ScheduleCapMib {
		learned = state.ScheduleCapMib
	}
	if learned > instance.Spec.MemoryFloorMaxMib {
		learned = instance.Spec.MemoryFloorMaxMib
	}
	if learned <= floorMib {
		return floorMib, ceilingMib
	}
	return learned, ceilingMib + memoryCeilingPerFloorMib*(learned-floorMib)
}

// observeMemoryDemand folds the replicas' floor-pool demand into the ring,
// under the same eligibility as CPU: a rebuild or evacuation is not steady
// demand. Turning autosizing off drops the state, so turning it back on starts
// from fresh evidence rather than from a floor learned under another plan.
func (r *KuraInstanceReconciler) observeMemoryDemand(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, samples map[string]runtimeStatus, now time.Time) {
	if !memoryAutosizeEnabled(instance) {
		instance.Status.MemoryAutosize = nil
		return
	}
	state := instance.Status.MemoryAutosize.DeepCopy()
	if state == nil {
		state = &kurav1alpha1.KuraInstanceMemoryAutosize{}
	}
	// Counters advance on every pass, eligible or not, so timeouts during a
	// rebuild are dropped rather than credited to the next steady window.
	timeouts := advancePodTimeouts(state, pods, samples)
	instance.Status.MemoryAutosize = state
	if !r.cpuObservationEligible(ctx, instance, pods, samples) {
		return
	}
	sample := memoryDemandSample{timeouts: timeouts}
	var reported bool
	for i := range pods {
		mib, ok := wantedMemoryFloorMib(&pods[i], samples[pods[i].Name])
		if !ok {
			continue
		}
		reported = true
		sample.wantedMib = max(sample.wantedMib, mib)
		sample.floorMib = max(sample.floorMib, bytesToMibCeil(podMemoryRequestBytes(&pods[i])))
	}
	// A pod on a release that predates the report gives no reading, which is
	// not a reading of zero demand.
	if !reported {
		return
	}
	instance.Status.MemoryAutosize = observeMemoryFloor(state, sample, now)
}

// memoryDemandSample is one pass's reading across the replicas: the largest
// floor any of them asked for, the largest floor any of them runs, and the
// admissions that timed out on them since the previous pass.
type memoryDemandSample struct {
	wantedMib int32
	floorMib  int32
	timeouts  uint64
}

// advancePodTimeouts returns the timeouts reported since the previous pass
// and records each pod's counter. The counters live in status so a controller
// restart neither loses nor double-counts them. A counter that went down
// belongs to a restarted process, all of whose timeouts are new; a pod seen
// for the first time only sets its baseline, since its counter may span far
// more than one window.
func advancePodTimeouts(state *kurav1alpha1.KuraInstanceMemoryAutosize, pods []corev1.Pod, samples map[string]runtimeStatus) uint64 {
	previous := map[string]int64{}
	for _, counter := range state.PodTimeouts {
		previous[counter.Pod] = counter.Timeouts
	}
	var delta uint64
	var next []kurav1alpha1.KuraInstanceMemoryPodCounter
	for i := range pods {
		name := pods[i].Name
		status, sampled := samples[name]
		last, seen := previous[name]
		if !sampled || status.FloorPoolAdmissionTimeoutsTotal == nil {
			if seen {
				next = append(next, kurav1alpha1.KuraInstanceMemoryPodCounter{Pod: name, Timeouts: last})
			}
			continue
		}
		current := int64(*status.FloorPoolAdmissionTimeoutsTotal)
		switch {
		case !seen:
		case current < last:
			delta += uint64(current)
		default:
			delta += uint64(current - last)
		}
		next = append(next, kurav1alpha1.KuraInstanceMemoryPodCounter{Pod: name, Timeouts: current})
	}
	state.PodTimeouts = next
	return delta
}

// wantedMemoryFloorMib converts one pod's report into the floor that would
// have admitted its peak demand with headroom. Kura's pool is the floor minus
// what it sets aside for its caches and process baseline; that set-aside is
// read off the pod as its floor minus the pool it reports, so a floor larger
// by N grows the pool by N.
//
// A peak that never exceeded the pool caps the result at the pod's current
// floor: headroom alone is not evidence the floor is short.
func wantedMemoryFloorMib(pod *corev1.Pod, status runtimeStatus) (int32, bool) {
	if status.FloorPoolCapacityBytes == nil || status.FloorPoolRecentPeakDemandBytes == nil {
		return 0, false
	}
	floor := podMemoryRequestBytes(pod)
	capacity := *status.FloorPoolCapacityBytes
	demand := *status.FloorPoolRecentPeakDemandBytes
	// A pool at or above the floor was sized from the ceiling: the pod runs
	// without a published floor, and the floor does not size its pool.
	if floor == 0 || capacity == 0 || capacity >= floor {
		return 0, false
	}
	setAside := floor - capacity
	wanted := setAside + (demand*memoryHeadroomNumerator+memoryHeadroomDenominator-1)/memoryHeadroomDenominator
	if demand <= capacity && wanted > floor {
		wanted = floor
	}
	return bytesToMibCeil(wanted), true
}

// observeMemoryFloor records a pass in the current window. The window keeps
// the largest floor asked for, but holds it at the floor the pods run until
// the window has shed memoryGrowthMinTimeouts requests; a burst's demand and
// its timeouts may arrive on different passes, so the window, not the pass,
// is what qualifies.
func observeMemoryFloor(state *kurav1alpha1.KuraInstanceMemoryAutosize, sample memoryDemandSample, now time.Time) *kurav1alpha1.KuraInstanceMemoryAutosize {
	next := state.DeepCopy()
	if next == nil {
		next = &kurav1alpha1.KuraInstanceMemoryAutosize{}
	}
	start := now.UTC().Truncate(cpuBucketDuration)

	switch {
	case next.BucketStartedAt == nil || len(next.BucketFloorsMib) == 0:
		next.BucketFloorsMib = []int32{0}
		next.BucketWantedMib, next.BucketTimeouts = 0, 0
	case start.After(next.BucketStartedAt.Time):
		steps := int(start.Sub(next.BucketStartedAt.Time) / cpuBucketDuration)
		if steps > cpuBucketCount {
			steps = cpuBucketCount
		}
		for i := 1; i < steps; i++ {
			next.BucketFloorsMib = append(next.BucketFloorsMib, cpuUnobservedWindow)
		}
		next.BucketFloorsMib = append(next.BucketFloorsMib, 0)
		next.BucketWantedMib, next.BucketTimeouts = 0, 0
	}
	next.BucketWantedMib = max(next.BucketWantedMib, sample.wantedMib)
	next.BucketTimeouts += int64(sample.timeouts)
	window := next.BucketWantedMib
	if next.BucketTimeouts < memoryGrowthMinTimeouts {
		window = min(window, sample.floorMib)
	}
	last := len(next.BucketFloorsMib) - 1
	next.BucketFloorsMib[last] = max(next.BucketFloorsMib[last], window)
	if overflow := len(next.BucketFloorsMib) - cpuBucketCount; overflow > 0 {
		next.BucketFloorsMib = next.BucketFloorsMib[overflow:]
	}
	next.BucketStartedAt = &metav1.Time{Time: start}

	var peak, observed int32
	for _, bucket := range next.BucketFloorsMib {
		if bucket == cpuUnobservedWindow {
			continue
		}
		observed++
		if bucket > peak {
			peak = bucket
		}
	}
	want := memoryBand(peak)
	// Growth applies at once. Shrinkage waits until the ring has watched the
	// instance through a full day, so a quiet stretch does not undo a floor a
	// recurring burst needs.
	if want > next.FloorMib || (want < next.FloorMib && observed >= cpuShrinkMinBuckets) {
		next.FloorMib = want
	}
	return next
}

// applyMemoryScheduleCap bounds the learned floor by what the scheduler has
// shown it will admit. A raise rolls the pods, and a replacement the box
// cannot fit stays Pending, reports nothing, and so could never lower the
// floor that stranded it. Mirrors applyScheduleCap.
func applyMemoryScheduleCap(instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, now time.Time) {
	if !memoryAutosizeEnabled(instance) {
		return
	}
	state := instance.Status.MemoryAutosize
	if state == nil {
		state = &kurav1alpha1.KuraInstanceMemoryAutosize{}
	}
	if state.ScheduleCapSetAt != nil && now.Sub(state.ScheduleCapSetAt.Time) >= cpuScheduleCapTTL {
		state.ScheduleCapMib = 0
		state.ScheduleCapSetAt = nil
	}

	var stuck, admitted int32
	for i := range pods {
		mib := bytesToMibCeil(podMemoryRequestBytes(&pods[i]))
		if podUnschedulableForMemory(&pods[i]) {
			if stuck == 0 || mib < stuck {
				stuck = mib
			}
			continue
		}
		if pods[i].Spec.NodeName != "" && mib > admitted {
			admitted = mib
		}
	}
	if stuck > 0 {
		capped := memoryBandBelow(stuck)
		if admitted > 0 && admitted < capped {
			capped = admitted
		}
		if state.ScheduleCapMib == 0 || capped < state.ScheduleCapMib {
			state.ScheduleCapMib = capped
			state.ScheduleCapSetAt = &metav1.Time{Time: now.UTC()}
		}
	}

	if state.ScheduleCapMib == 0 && state.FloorMib == 0 && len(state.BucketFloorsMib) == 0 {
		return
	}
	instance.Status.MemoryAutosize = state
}

func podUnschedulableForMemory(pod *corev1.Pod) bool {
	if pod.Status.Phase != corev1.PodPending {
		return false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type != corev1.PodScheduled ||
			condition.Status != corev1.ConditionFalse ||
			condition.Reason != corev1.PodReasonUnschedulable {
			continue
		}
		for _, predicate := range insufficientMemoryPredicates {
			if strings.Contains(condition.Message, predicate) {
				return true
			}
		}
	}
	return false
}

func podMemoryRequestBytes(pod *corev1.Pod) uint64 {
	for i := range pod.Spec.Containers {
		if pod.Spec.Containers[i].Name != kuraContainerName {
			continue
		}
		if value := pod.Spec.Containers[i].Resources.Requests.Memory().Value(); value > 0 {
			return uint64(value)
		}
	}
	return 0
}

func memoryBand(mib int32) int32 {
	for _, band := range memoryFloorBands {
		if mib <= band {
			return band
		}
	}
	return memoryFloorBands[len(memoryFloorBands)-1]
}

func memoryBandBelow(mib int32) int32 {
	below := memoryFloorBands[0]
	for _, band := range memoryFloorBands {
		if band >= mib {
			break
		}
		below = band
	}
	return below
}

func bytesToMibCeil(bytes uint64) int32 {
	const mib = 1024 * 1024
	value := (bytes + mib - 1) / mib
	limit := uint64(memoryFloorBands[len(memoryFloorBands)-1]) * memoryHeadroomNumerator
	if value > limit {
		value = limit
	}
	return int32(value)
}
