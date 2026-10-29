package plugin

import (
	"strings"
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/data"
)

var defaultSeries = []string{"average", "p50", "p90", "p99"}

// framesFromMetrics turns a DurationMetrics response into a wide time-series
// frame: a time field plus one numeric field per requested series.
func framesFromMetrics(qm queryModel, metrics *durationMetrics) *data.Frame {
	times := make([]time.Time, len(metrics.Dates))
	for i, ts := range metrics.Dates {
		times[i] = time.Unix(ts, 0).UTC()
	}

	if qm.ResultMode == "total" {
		frames := data.NewFrame("duration")
		requested := qm.Series
		if len(requested) == 0 {
			requested = defaultSeries
		}
		for _, name := range requested {
			if s, ok := seriesByName(metrics, name); ok {
				field := data.NewField(name, nil, []float64{s.Total})
				field.Config = &data.FieldConfig{Unit: "ms"}
				frames.Fields = append(frames.Fields, field)
			}
		}
		return frames
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

var buildMetricUnits = map[string]string{
	"builds": "short", "successful_builds": "short", "failed_builds": "short", "cancelled_builds": "short",
	"success_rate": "percent", "average": "ms", "p50": "ms", "p90": "ms", "p99": "ms",
	"slow_build_threshold": "ms", "builds_needing_attention": "short", "cache_time_saved": "ms", "cache_time_saved_samples": "short", "cache_work_avoided": "ms", "cache_work_avoided_samples": "short",
}

func frameFromBuildHealth(qm queryModel, metrics *buildHealthMetrics, baseURL string) *data.Frame {
	frame := data.NewFrame(qm.QueryType)
	switch qm.QueryType {
	case "buildHealth", "gradleHealth":
		if qm.ResultMode == "total" {
			field := data.NewField(qm.Metric, nil, []*float64{metrics.Totals[qm.Metric]})
			field.Config = &data.FieldConfig{Unit: buildMetricUnits[qm.Metric]}
			frame.Fields = append(frame.Fields, field)
		} else {
			times := make([]time.Time, len(metrics.Dates))
			for i, date := range metrics.Dates {
				times[i] = time.Unix(date, 0).UTC()
			}
			field := data.NewField(qm.Metric, nil, metrics.Series[qm.Metric])
			field.Config = &data.FieldConfig{Unit: buildMetricUnits[qm.Metric]}
			frame.Fields = append(frame.Fields, data.NewField("time", nil, times), field)
		}
	case "buildWorkloads", "gradleWorkloads":
		workloads, builds := []string{}, []float64{}
		rates, medians, p90s := []*float64{}, []*float64{}, []*float64{}
		for _, row := range metrics.Rows {
			workloads = append(workloads, row.Workload)
			builds = append(builds, row.Builds)
			rates = append(rates, row.SuccessRate)
			medians = append(medians, row.P50)
			p90s = append(p90s, row.P90)
		}
		frame.Fields = append(frame.Fields, data.NewField("Workload", nil, workloads), data.NewField("Builds", nil, builds),
			data.NewField("Success rate", nil, rates), data.NewField("Median duration", nil, medians), data.NewField("90th percentile duration", nil, p90s))
		frame.Fields[2].Config = &data.FieldConfig{Unit: "percent"}
		frame.Fields[3].Config = &data.FieldConfig{Unit: "ms"}
		frame.Fields[4].Config = &data.FieldConfig{Unit: "ms"}
	case "buildFailureReasons", "gradleFailureReasons":
		categories, counts := []string{}, []float64{}
		for _, row := range metrics.Rows {
			category := row.Category
			if qm.QueryType == "buildFailureReasons" {
				switch category {
				case "all":
					category = "All failures"
				case "verification":
					category = "Verification failures"
				case "infrastructure_tooling":
					category = "Infrastructure / tooling failures"
				case "unknown":
					category = "Unclassified failures"
				}
			}
			categories = append(categories, category)
			counts = append(counts, row.Builds)
		}
		frame.Fields = append(frame.Fields, data.NewField("Failure category", nil, categories), data.NewField("Builds", nil, counts))
	case "buildRecentFailures", "gradleRecentFailures":
		times, durations := []time.Time{}, []*float64{}
		users, tasks, workloads, categories, branches, links := []string{}, []string{}, []string{}, []string{}, []string{}, []string{}
		for _, row := range metrics.Rows {
			times = append(times, time.Unix(row.StartedAt, 0).UTC())
			durations = append(durations, row.DurationMS)
			users = append(users, row.User)
			tasks = append(tasks, strings.Join(row.RequestedTasks, " "))
			workloads = append(workloads, row.Workload)
			categories = append(categories, row.FailureCategory)
			branches = append(branches, row.GitBranch)
			links = append(links, baseURL+"/"+qm.ProjectHandle+buildPath(row.BuildSystem, row.ID))
		}
		frame.Fields = append(frame.Fields, data.NewField("Started", nil, times), data.NewField("Workload", nil, workloads),
			data.NewField("Duration", nil, durations), data.NewField("User", nil, users), data.NewField("Requested tasks", nil, tasks),
			data.NewField("Failure category", nil, categories), data.NewField("Branch", nil, branches), data.NewField("Build", nil, links))
		frame.Fields[2].Config = &data.FieldConfig{Unit: "ms"}
		frame.Fields[7].Config = &data.FieldConfig{Links: []data.DataLink{{Title: "View build", URL: "${__value.raw}"}}}
	}
	return frame
}

func buildPath(system, id string) string {
	switch system {
	case "bazel":
		return "/builds/invocations/" + id
	case "once":
		return "/once/runs/" + id
	default:
		return "/builds/build-runs/" + id
	}
}
