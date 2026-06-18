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
	Environment   string `json:"environment"`
	Scheme        string `json:"scheme"`
	Configuration string `json:"configuration"`
	Category      string `json:"category"`
	Status        string `json:"status"`
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
