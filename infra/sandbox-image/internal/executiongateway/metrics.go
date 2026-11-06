package executiongateway

import (
	"log"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"github.com/prometheus/client_golang/prometheus"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Labels are fixed sets: never accounts, projects or digests.
type metrics struct {
	executions   *prometheus.CounterVec
	duration     *prometheus.HistogramVec
	streams      prometheus.Gauge
	prefetches   *prometheus.CounterVec
	publications *prometheus.CounterVec
	phases       *prometheus.HistogramVec
}

func newMetrics(registry prometheus.Registerer) *metrics {
	m := &metrics{
		executions: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "reapi_gateway_executions_total",
			Help: "Execute calls by path (lease or server) and final status: the RPC's error, or the action's status when it completed.",
		}, []string{"path", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "reapi_gateway_execute_seconds",
			Help:    "Execute calls from admission to the final message, by path.",
			Buckets: prometheus.ExponentialBuckets(0.001, 2, 20),
		}, []string{"path"}),
		streams: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "reapi_gateway_streams",
			Help: "Admitted Execute and WaitExecution streams.",
		}),
		prefetches: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "reapi_gateway_prefetches_total",
			Help: "Input prefetches by how the inputs were read (inputs, tree, walk), or why none were (skipped, failed).",
		}, []string{"result"}),
		publications: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "reapi_gateway_publications_total",
			Help: "Background action-cache publications: stored, failed, or dropped while too many were pending.",
		}, []string{"result"}),
		phases: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "reapi_gateway_action_phase_seconds",
			Help:    "Executed actions by phase, from the executor's metadata: queued (admission to worker start, including VM creation), input_fetch (reading the action and materializing its input tree), execution and output_upload.",
			Buckets: prometheus.ExponentialBuckets(0.001, 2, 20),
		}, []string{"phase"}),
	}
	registry.MustRegister(m.executions, m.duration, m.streams, m.prefetches, m.publications, m.phases)
	return m
}

// observePhases records how long each phase of an executed action took, so a
// slow action can be attributed to queueing, input fetch, the command itself
// or output upload. Phases with a missing or reversed timestamp are skipped.
func (m *metrics) observePhases(md *re.ExecutedActionMetadata) {
	if md == nil {
		return
	}
	phases := []struct {
		name       string
		start, end *timestamppb.Timestamp
	}{
		{"queued", md.QueuedTimestamp, md.WorkerStartTimestamp},
		{"input_fetch", md.InputFetchStartTimestamp, md.InputFetchCompletedTimestamp},
		{"execution", md.ExecutionStartTimestamp, md.ExecutionCompletedTimestamp},
		{"output_upload", md.OutputUploadStartTimestamp, md.OutputUploadCompletedTimestamp},
	}
	line := ""
	for _, p := range phases {
		if p.start == nil || p.end == nil || p.start.CheckValid() != nil || p.end.CheckValid() != nil {
			continue
		}
		d := p.end.AsTime().Sub(p.start.AsTime())
		if d < 0 {
			continue
		}
		m.phases.WithLabelValues(p.name).Observe(d.Seconds())
		line += " " + p.name + "=" + d.Round(time.Millisecond).String()
	}
	if line != "" {
		log.Print("action phases:" + line + casReads(md))
	}
}

// casReads returns the executor's CAS read summary (per-RPC totals and the
// slowest reads, see executor.casReadTimings) as a log suffix.
func casReads(md *re.ExecutedActionMetadata) string {
	for _, a := range md.AuxiliaryMetadata {
		var s structpb.Struct
		if !a.MessageIs(&s) || a.UnmarshalTo(&s) != nil || s.Fields["kind"].GetStringValue() != "tuist.cas_reads" {
			continue
		}
		delete(s.Fields, "kind")
		b, err := protojson.Marshal(&s)
		if err != nil {
			return ""
		}
		return " cas_reads=" + string(b)
	}
	return ""
}
