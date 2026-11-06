package executiongateway

import (
	"net/http"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
	dto "github.com/prometheus/client_model/go"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestExecutionsAreCountedByPathAndStatus(t *testing.T) {
	lab := newDirectLab(t, http.StatusOK)
	auth := jwt(time.Now().Add(time.Hour))
	lab.capabilities(auth)
	lab.execute(auth)
	lab.awaitLease()
	lab.execute(auth)

	m := lab.gateway.metrics
	if server, leased := testutil.ToFloat64(m.executions.WithLabelValues("server", "OK")), testutil.ToFloat64(m.executions.WithLabelValues("lease", "OK")); server != 1 || leased != 1 {
		t.Fatalf("server executions %v, leased executions %v; want one each", server, leased)
	}
	if n := testutil.CollectAndCount(m.duration); n != 2 {
		t.Fatalf("%d duration series; want one per path", n)
	}
	if streams := testutil.ToFloat64(m.streams); streams != 0 {
		t.Fatalf("%v streams still counted after both finished", streams)
	}
}

func TestPrefetchesAreCountedByHowTheInputsWereRead(t *testing.T) {
	for _, test := range []struct {
		name  string
		store *blobStore
	}{
		{"inputs", &blobStore{blobs: map[string][]byte{}, tree: true, inputs: true}},
		{"tree", &blobStore{blobs: map[string][]byte{}, tree: true}},
		{"walk", &blobStore{blobs: map[string][]byte{}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			prefetch, _, g := prefetchLab(t, test.store)
			prefetch()
			if n := testutil.ToFloat64(g.metrics.prefetches.WithLabelValues(test.name)); n != 1 {
				t.Fatalf("%v prefetches counted as %s", n, test.name)
			}
		})
	}
}

func TestExecutedActionPhasesAreAttributed(t *testing.T) {
	m := newMetrics(prometheus.NewRegistry())
	at := func(s float64) *timestamppb.Timestamp {
		return timestamppb.New(time.Unix(1_000, 0).Add(time.Duration(s * float64(time.Second))))
	}
	m.observePhases(&re.ExecutedActionMetadata{
		QueuedTimestamp:                at(0),
		WorkerStartTimestamp:           at(2),
		InputFetchStartTimestamp:       at(2),
		InputFetchCompletedTimestamp:   at(172),
		ExecutionStartTimestamp:        at(172.5),
		ExecutionCompletedTimestamp:    at(176),
		OutputUploadStartTimestamp:     at(177),
		OutputUploadCompletedTimestamp: at(176), // reversed: skipped
	})
	m.observePhases(nil)

	for phase, want := range map[string]float64{"queued": 2, "input_fetch": 170, "execution": 3.5} {
		var metric dto.Metric
		if err := m.phases.WithLabelValues(phase).(prometheus.Histogram).Write(&metric); err != nil {
			t.Fatal(err)
		}
		if got := metric.GetHistogram().GetSampleSum(); got != want || metric.GetHistogram().GetSampleCount() != 1 {
			t.Fatalf("%s: %d samples summing to %vs; want one of %vs", phase, metric.GetHistogram().GetSampleCount(), got, want)
		}
	}
	if n := testutil.CollectAndCount(m.phases); n != 3 {
		t.Fatalf("%d phase series; the reversed output upload must not be recorded", n)
	}
}
