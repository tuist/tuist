package plugin

import (
	"context"
	"encoding/json"
	"github.com/grafana/grafana-plugin-sdk-go/backend"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestGradleQueryForwardsAlertWindowAndFilters(t *testing.T) {
	threshold := int64(1234)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/projects/acme/app/gradle/builds/metrics" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		for key, value := range map[string]string{"from": "100", "to": "200", "view": "total", "git_branch": "release/a & b", "workload": "Unit tests", "is_ci": "true", "slow_build_threshold_ms": "1234"} {
			if r.URL.Query().Get(key) != value {
				t.Errorf("%s: want %q, got %q", key, value, r.URL.Query().Get(key))
			}
		}
		_, _ = w.Write([]byte(`{"totals":{"success_rate":90}}`))
	}))
	defer server.Close()
	qm := queryModel{QueryType: "gradleHealth", ProjectHandle: "acme/app", Metric: "success_rate", ResultMode: "total", GitBranch: "release/a & b", Workload: "Unit tests", Environment: "ci", SlowBuildThresholdMS: &threshold}
	body, _ := json.Marshal(qm)
	result, err := testDatasource(server).QueryData(context.Background(), &backend.QueryDataRequest{Queries: []backend.DataQuery{{RefID: "A", JSON: body, TimeRange: backend.TimeRange{From: time.Unix(100, 0), To: time.Unix(200, 0)}}}})
	if err != nil {
		t.Fatal(err)
	}
	response := result.Responses["A"]
	if response.Error != nil {
		t.Fatal(response.Error)
	}
	frame := response.Frames[0]
	if len(frame.Fields) != 1 || frame.Fields[0].Len() != 1 {
		t.Fatal("whole-period alert query must return a single numeric field")
	}
	if got := frame.Fields[0].At(0).(*float64); *got != 90 {
		t.Fatalf("unexpected rate %v", got)
	}
	if frame.Fields[0].Config.Unit != "percent" {
		t.Fatal("success rate must use 0-100 percent")
	}
}

func TestMissingCacheSavingsStayNull(t *testing.T) {
	frame := frameFromBuildHealth(queryModel{QueryType: "gradleHealth", Metric: "cache_time_saved", ResultMode: "total"}, &buildHealthMetrics{Totals: map[string]*float64{"cache_time_saved": nil}}, "https://tuist.dev")
	if frame.Fields[0].At(0).(*float64) != nil {
		t.Fatal("missing savings must stay null")
	}
	if frame.Fields[0].Config.Unit != "ms" {
		t.Fatal("expected milliseconds")
	}
}

func TestDurationTotalUsesPeriodAggregate(t *testing.T) {
	frame := framesFromMetrics(queryModel{ResultMode: "total", Series: []string{"p50"}}, &durationMetrics{P50: series{Total: 100, Values: []*float64{floatPtr(100), floatPtr(900)}}})
	if frame.Fields[0].At(0).(float64) != 100 {
		t.Fatal("must not average bucket medians")
	}
}

func TestRecentFailureLinksAndWorkloadUnits(t *testing.T) {
	frame := frameFromBuildHealth(queryModel{QueryType: "gradleRecentFailures", ProjectHandle: "acme/app"}, &buildHealthMetrics{Rows: []buildMetricRow{{ID: "123", RequestedTasks: []string{":test", ":lint"}}}}, "https://tuist.dev")
	if frame.Fields[7].At(0) != "https://tuist.dev/acme/app/builds/build-runs/123" {
		t.Fatal("wrong build detail link")
	}
	if frame.Fields[4].At(0) != ":test :lint" {
		t.Fatal("missing requested tasks")
	}
	frame = frameFromBuildHealth(queryModel{QueryType: "gradleWorkloads"}, &buildHealthMetrics{Rows: []buildMetricRow{{Workload: "Unit tests", Builds: 1}}}, "https://tuist.dev")
	if frame.Fields[2].Config.Unit != "percent" || frame.Fields[4].Config.Unit != "ms" {
		t.Fatal("workload table must retain units")
	}
}

func TestInvalidHealthQueriesNeverReachServer(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Error("invalid query reached server") }))
	defer server.Close()
	threshold := int64(-1)
	for _, qm := range []queryModel{
		{QueryType: "gradleHealth", ProjectHandle: "acme/app", Metric: "invented"},
		{QueryType: "gradleHealth", ProjectHandle: "../app", Metric: "builds"},
		{QueryType: "gradleHealth", ProjectHandle: "acme/app?token=foo", Metric: "builds"},
		{QueryType: "gradleHealth", ProjectHandle: "acme/app", SlowBuildThresholdMS: &threshold},
		{QueryType: "gradleHealth", ProjectHandle: "acme/app", ResultMode: "unknown"},
	} {
		body, _ := json.Marshal(qm)
		if testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body}).Error == nil {
			t.Fatalf("expected error for %+v", qm)
		}
	}
}

func TestPluginDeclaresBackendAlertSupport(t *testing.T) {
	body, err := os.ReadFile("../../src/plugin.json")
	if err != nil {
		t.Fatal(err)
	}
	var manifest struct {
		Backend  bool `json:"backend"`
		Alerting bool `json:"alerting"`
	}
	if err := json.Unmarshal(body, &manifest); err != nil {
		t.Fatal(err)
	}
	if !manifest.Backend || !manifest.Alerting {
		t.Fatal("Grafana requires both backend and alerting capabilities")
	}
}

func TestStandardDashboardQueriesUseSharedEndpoint(t *testing.T) {
	for _, queryType := range []string{"buildHealth", "buildWorkloads", "buildFailureReasons", "buildRecentFailures"} {
		t.Run(queryType, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/api/projects/acme/app/builds/metrics/health" {
					t.Errorf("wrong shared endpoint %s", r.URL.Path)
				}
				if r.URL.Query().Get("git_branch") != "main" {
					t.Error("branch was not forwarded")
				}
				_, _ = w.Write([]byte(`{"totals":{"builds":2},"rows":[]}`))
			}))
			defer server.Close()
			qm := queryModel{QueryType: queryType, ProjectHandle: "acme/app", Metric: "builds", ResultMode: "total", GitBranch: "main"}
			body, _ := json.Marshal(qm)
			response := testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body})
			if response.Error != nil {
				t.Fatal(response.Error)
			}
			if len(response.Frames) != 1 {
				t.Fatal("expected one frame")
			}
		})
	}
}

func TestSharedRecentFailuresLinkToEachBuildSystem(t *testing.T) {
	for system, path := range map[string]string{"xcode": "/builds/build-runs/", "gradle": "/builds/build-runs/", "bazel": "/builds/invocations/", "once": "/once/runs/"} {
		frame := frameFromBuildHealth(queryModel{QueryType: "buildRecentFailures", ProjectHandle: "acme/app"}, &buildHealthMetrics{Rows: []buildMetricRow{{ID: "run-123", BuildSystem: system}}}, "https://tuist.dev")
		if frame.Fields[7].At(0) != "https://tuist.dev/acme/app"+path+"run-123" {
			t.Fatalf("wrong link for %s", system)
		}
		if frame.Fields[2].At(0).(*float64) != nil {
			t.Fatalf("missing duration became zero for %s", system)
		}
	}
}

func TestFailureLabelsPreserveLegacyIdentifiers(t *testing.T) {
	metrics := &buildHealthMetrics{Rows: []buildMetricRow{{Category: "all", Builds: 3}, {Category: "verification", Builds: 1}}}
	generic := frameFromBuildHealth(queryModel{QueryType: "buildFailureReasons"}, metrics, "")
	legacy := frameFromBuildHealth(queryModel{QueryType: "gradleFailureReasons"}, metrics, "")
	if generic.Fields[0].At(0) != "All failures" || generic.Fields[0].At(1) != "Verification failures" || legacy.Fields[0].At(1) != "verification" {
		t.Fatal("failure labels or legacy category identifiers changed")
	}
}

func TestGenericPartialBucketIsVisibleWithoutChangingLegacyTimestamps(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"dates":[100],"series":{"builds":[4]},"totals":{"builds":4}}`))
	}))
	defer server.Close()
	from := time.Unix(125, 500000000)
	for _, kind := range []string{"buildHealth", "gradleHealth"} {
		body, _ := json.Marshal(queryModel{QueryType: kind, ProjectHandle: "acme/app", Metric: "builds"})
		response := testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body, TimeRange: backend.TimeRange{From: from, To: time.Unix(200, 0)}})
		if response.Error != nil {
			t.Fatal(response.Error)
		}
		got := response.Frames[0].Fields[0].At(0).(time.Time)
		want := from
		if kind == "gradleHealth" {
			want = time.Unix(100, 0)
		}
		if !got.Equal(want) {
			t.Fatalf("%s timestamp: got %v, want %v", kind, got, want)
		}
	}
}

func TestAlertFiltersRequireResolvedValuesAndNormalizeAll(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for _, key := range []string{"git_branch", "workload", "status", "is_ci"} {
			if r.URL.Query().Get(key) != "" {
				t.Errorf("All must omit %s", key)
			}
		}
		_, _ = w.Write([]byte(`{"totals":{"builds":4}}`))
	}))
	defer server.Close()
	for _, qm := range []queryModel{
		{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "builds", GitBranch: "$branch"},
		{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "builds", GitBranch: "[[branch]]"},
		{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "builds", Workload: "${workload}"},
		{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "builds", Status: "$status"},
		{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "$metric"},
	} {
		body, _ := json.Marshal(qm)
		response := testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body, TimeRange: backend.TimeRange{From: time.Unix(100, 0), To: time.Unix(200, 0)}})
		if response.Error == nil || !strings.Contains(response.Error.Error(), "fixed") {
			t.Fatalf("expected unresolved filter error: %+v", response)
		}
	}
	qm := queryModel{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "builds", ResultMode: "total", GitBranch: "__tuist_all__", Workload: "__tuist_all__", Status: "__tuist_all__", Environment: "__tuist_all__"}
	body, _ := json.Marshal(qm)
	response := testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body, TimeRange: backend.TimeRange{From: time.Unix(100, 0), To: time.Unix(200, 0)}})
	if response.Error != nil {
		t.Fatal(response.Error)
	}
	if *response.Frames[0].Fields[0].At(0).(*float64) != 4 {
		t.Fatal("All filter unexpectedly excluded builds")
	}
}

func TestLiteralDollarBranchIsPreserved(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("git_branch") != "release$1" {
			t.Error("literal branch changed")
		}
		_, _ = w.Write([]byte(`{"totals":{"builds":1}}`))
	}))
	defer server.Close()
	qm := queryModel{QueryType: "buildHealth", ProjectHandle: "acme/app", Metric: "builds", ResultMode: "total", GitBranch: "release$1"}
	body, _ := json.Marshal(qm)
	response := testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body, TimeRange: backend.TimeRange{From: time.Unix(100, 0), To: time.Unix(200, 0)}})
	if response.Error != nil {
		t.Fatal(response.Error)
	}
}
