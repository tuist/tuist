package controllers

import (
	"encoding/json"
	"reflect"
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func TestCPUSustainedDemandDilutesAnIsolatedSpike(t *testing.T) {
	now := time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)
	for _, spikeMinute := range []int{0, 5, 15} {
		var state *kurav1alpha1.KuraInstanceCPUAutosize
		for minute := 0; minute < 30; minute++ {
			usage := int64(3)
			if minute == spikeMinute {
				usage = 1701
			}
			state = observeCPUSample(state, usage, now.Add(time.Duration(minute)*time.Minute))
			if state.RequestMilli > 250 {
				t.Fatalf("spike at minute %d reserved %dm at minute %d", spikeMinute, state.RequestMilli, minute)
			}
		}
		if state.PeakMilli != 173 || state.RequestMilli != 250 {
			t.Fatalf("spike at minute %d: mean peak/request = %d/%d, want 173/250", spikeMinute, state.PeakMilli, state.RequestMilli)
		}
	}
}

func TestCPUSustainedDemandGrowsAfterTenObservedMinutes(t *testing.T) {
	now := time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)
	var state *kurav1alpha1.KuraInstanceCPUAutosize
	for minute := 0; minute < 10; minute++ {
		state = observeCPUSample(state, 631, now.Add(time.Duration(minute)*time.Minute))
		if minute < 9 && state.RequestMilli != cpuColdStartMilli {
			t.Fatalf("request grew before ten readings: %+v", state)
		}
	}
	if state.PeakMilli != 631 || state.RequestMilli != 1000 {
		t.Fatalf("sustained 631m did not reserve 1000m: %+v", state)
	}
}

func TestCPUSustainedDemandDoesNotWeightReconcileFrequency(t *testing.T) {
	now := time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)
	state := observeCPUSample(nil, 3, now)
	for second := 0; second < 60; second++ {
		got := observeCPUSample(state, 4000, now.Add(time.Duration(second)*time.Second))
		if !reflect.DeepEqual(got, state) {
			t.Fatalf("reconcile %d reused the minute's observation: %+v", second, got)
		}
	}
	if got := observeCPUSample(state, 4000, now.Add(-time.Minute)); !reflect.DeepEqual(got, state) {
		t.Fatal("a clock moving backwards counted another reading")
	}
}

func TestCPUSustainedDemandRestartsShortWindowAfterMissingMinutes(t *testing.T) {
	now := time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)
	var state *kurav1alpha1.KuraInstanceCPUAutosize
	for minute := 0; minute < 9; minute++ {
		state = observeCPUSample(state, 800, now.Add(time.Duration(minute)*time.Minute))
	}
	before := state.DeepCopy()
	state = observeCPUSample(state, 2, now.Add(10*time.Minute))
	if len(before.SamplesMilli) != 9 || !reflect.DeepEqual(state.SamplesMilli, []int32{2}) {
		t.Fatalf("missing minute was counted or input mutated: before=%+v after=%+v", before, state)
	}
	if state.BucketStartedAt != nil || state.RequestMilli != cpuColdStartMilli {
		t.Fatalf("incomplete windows became sizing history: %+v", state)
	}
}

func TestCPUSustainedDemandSurvivesPersistenceAndBucketBoundary(t *testing.T) {
	now := time.Date(2026, 9, 23, 11, 55, 0, 0, time.UTC)
	var state *kurav1alpha1.KuraInstanceCPUAutosize
	for minute := 0; minute < 20; minute++ {
		state = observeCPUSample(state, 480, now.Add(time.Duration(minute)*time.Minute))
		encoded, err := json.Marshal(state)
		if err != nil {
			t.Fatal(err)
		}
		state = &kurav1alpha1.KuraInstanceCPUAutosize{}
		if err := json.Unmarshal(encoded, state); err != nil {
			t.Fatal(err)
		}
	}
	if len(state.SamplesMilli) != 10 || state.RequestMilli != 600 || state.PeakMilli != 480 {
		t.Fatalf("persisted sustained window lost its evidence: %+v", state)
	}
}

func TestCPUSustainedMigrationRebuildsHistoryBeforeShrinking(t *testing.T) {
	now := time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)
	legacy := &kurav1alpha1.KuraInstanceCPUAutosize{
		RequestMilli: 3000, PeakMilli: 1701,
		BucketStartedAt:  &metav1.Time{Time: now},
		BucketPeaksMilli: []int32{1701, 3, 3, 3, 3, 3, 3, 3},
		ScheduleCapMilli: 2000, ScheduleCapSetAt: &metav1.Time{Time: now},
	}
	state := observeCPUSample(legacy, 3, now)
	if state.RequestMilli != 3000 || state.ScheduleCapMilli != 2000 || len(state.BucketPeaksMilli) != 0 {
		t.Fatalf("migration changed the reservation or retained raw peaks: %+v", state)
	}
	if legacy.PeakMilli != 1701 || len(legacy.BucketPeaksMilli) != 8 {
		t.Fatal("migration mutated the caller's state")
	}
	for bucket := 0; bucket < cpuShrinkMinBuckets; bucket++ {
		for minute := 0; minute < 10; minute++ {
			state = observeCPUSample(state, 3, now.Add(time.Duration(bucket)*cpuBucketDuration+time.Duration(minute)*time.Minute))
			if (bucket < cpuShrinkMinBuckets-1 || minute < 9) && state.RequestMilli != 3000 {
				t.Fatalf("request shrank before sustained history replaced legacy evidence: %+v", state)
			}
		}
	}
	if state.RequestMilli != 50 || state.PeakMilli != 3 {
		t.Fatalf("legacy spike still dictates the reservation: %+v", state)
	}
}
