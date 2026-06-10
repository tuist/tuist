package plugin

import (
	"testing"
)

func floatPtr(v float64) *float64 { return &v }

func TestFramesFromMetricsSelectsRequestedSeries(t *testing.T) {
	metrics := &durationMetrics{
		Dates:   []int64{1714262400, 1714348800},
		Average: series{Values: []*float64{floatPtr(100), floatPtr(200)}},
		P50:     series{Values: []*float64{floatPtr(90), floatPtr(180)}},
		P90:     series{Values: []*float64{floatPtr(150), floatPtr(300)}},
		P99:     series{Values: []*float64{floatPtr(190), floatPtr(380)}},
	}

	frame := framesFromMetrics(queryModel{Series: []string{"p50", "p99"}}, metrics)

	// time field + p50 + p99
	if got := len(frame.Fields); got != 3 {
		t.Fatalf("expected 3 fields, got %d", got)
	}
	if frame.Fields[0].Name != "time" {
		t.Fatalf("expected first field to be time, got %q", frame.Fields[0].Name)
	}
	if frame.Fields[1].Name != "p50" || frame.Fields[2].Name != "p99" {
		t.Fatalf("expected p50 and p99 fields, got %q and %q", frame.Fields[1].Name, frame.Fields[2].Name)
	}
	if frame.Fields[1].Config == nil || frame.Fields[1].Config.Unit != "ms" {
		t.Fatalf("expected ms unit on series field")
	}
}

func TestFramesFromMetricsDefaultsToPercentiles(t *testing.T) {
	metrics := &durationMetrics{Dates: []int64{1714262400}}
	frame := framesFromMetrics(queryModel{}, metrics)

	// time + p50 + p90 + p99
	if got := len(frame.Fields); got != 4 {
		t.Fatalf("expected 4 fields by default, got %d", got)
	}
}

func TestEntityForQueryType(t *testing.T) {
	cases := map[string]string{
		queryTypeBuildDuration: entityBuilds,
		queryTypeTestDuration:  entityTests,
	}
	for queryType, want := range cases {
		got, err := entityForQueryType(queryType)
		if err != nil {
			t.Fatalf("unexpected error for %q: %v", queryType, err)
		}
		if got != want {
			t.Fatalf("entityForQueryType(%q) = %q, want %q", queryType, got, want)
		}
	}

	if _, err := entityForQueryType("nope"); err == nil {
		t.Fatal("expected error for unknown query type")
	}
}
