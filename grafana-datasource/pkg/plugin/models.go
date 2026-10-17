package plugin

const (
	queryTypeBuildDuration = "buildDuration"
	queryTypeTestDuration  = "testDuration"

	entityBuilds = "builds"
	entityTests  = "tests"
)

// dataSourceSettings is the non-secret configuration stored as jsonData.
type dataSourceSettings struct {
	URL string `json:"url"`
}

// queryModel is the per-panel query sent by the query editor.
type queryModel struct {
	QueryType     string   `json:"queryType"`
	ProjectHandle string   `json:"projectHandle"`
	Series        []string `json:"series"`
	// Environment mirrors the dashboard filter: "any" (default), "ci", or "local".
	Environment          string `json:"environment"`
	Scheme               string `json:"scheme"`
	Configuration        string `json:"configuration"`
	Category             string `json:"category"`
	Status               string `json:"status"`
	ResultMode           string `json:"resultMode"`
	Metric               string `json:"metric"`
	GitBranch            string `json:"gitBranch"`
	Workload             string `json:"workload"`
	SlowBuildThresholdMS *int64 `json:"slowBuildThresholdMs"`
}

// series mirrors a single duration series in the DurationMetrics API response.
type series struct {
	Values []*float64 `json:"values"`
	Total  float64    `json:"total"`
}

// durationMetrics mirrors the server's DurationMetrics response schema.
type durationMetrics struct {
	Dates   []int64 `json:"dates"`
	Average series  `json:"average"`
	P50     series  `json:"p50"`
	P90     series  `json:"p90"`
	P99     series  `json:"p99"`
	Trend   float64 `json:"trend"`
}

// project mirrors the relevant field of the GET /api/projects response.
type project struct {
	FullName string `json:"full_name"`
}

// Gradle health metrics use null for missing evidence rather than zero.
type buildHealthMetrics struct {
	Dates  []int64               `json:"dates"`
	Series map[string][]*float64 `json:"series"`
	Totals map[string]*float64   `json:"totals"`
	Rows   []buildMetricRow      `json:"rows"`
}

type buildMetricRow struct {
	BuildSystem     string   `json:"build_system"`
	Workload        string   `json:"workload"`
	Category        string   `json:"category"`
	ID              string   `json:"id"`
	StartedAt       int64    `json:"started_at"`
	DurationMS      *float64 `json:"duration_ms"`
	User            string   `json:"user"`
	RequestedTasks  []string `json:"requested_tasks"`
	FailureCategory string   `json:"failure_category"`
	GitBranch       string   `json:"git_branch"`
	Builds          float64  `json:"builds"`
	SuccessRate     *float64 `json:"success_rate"`
	P50             *float64 `json:"p50"`
	P90             *float64 `json:"p90"`
}
