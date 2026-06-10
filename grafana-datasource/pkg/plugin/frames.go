package plugin

import (
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/data"
)

var defaultSeries = []string{"p50", "p90", "p99"}

// framesFromMetrics turns a DurationMetrics response into a wide time-series
// frame: a time field plus one numeric field per requested series.
func framesFromMetrics(qm queryModel, metrics *durationMetrics) *data.Frame {
	times := make([]time.Time, len(metrics.Dates))
	for i, ts := range metrics.Dates {
		times[i] = time.Unix(ts, 0).UTC()
	}

	frame := data.NewFrame("duration")
	frame.Fields = append(frame.Fields, data.NewField("time", nil, times))

	requested := qm.Series
	if len(requested) == 0 {
		requested = defaultSeries
	}

	for _, name := range requested {
		s, ok := seriesByName(metrics, name)
		if !ok {
			continue
		}
		field := data.NewField(name, nil, s.Values)
		field.Config = &data.FieldConfig{Unit: "ms", DisplayName: name}
		frame.Fields = append(frame.Fields, field)
	}

	return frame
}

func seriesByName(metrics *durationMetrics, name string) (series, bool) {
	switch name {
	case "average":
		return metrics.Average, true
	case "p50":
		return metrics.P50, true
	case "p90":
		return metrics.P90, true
	case "p99":
		return metrics.P99, true
	default:
		return series{}, false
	}
}
