package plugin

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

func TestExistingDurationPanelsWorkWithOlderServer(t *testing.T) {
	for _, entity := range []string{"builds", "tests"} {
		t.Run(entity, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/api/projects/acme/app/"+entity+"/metrics/duration" {
					t.Errorf("existing panel reached new endpoint %s", r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
					return
				}
				if r.Header.Get("Authorization") != "Bearer existing-token" {
					t.Error("existing secure token was not used")
				}
				filters := map[string]string{"from": "100", "to": "200", "is_ci": "true", "scheme": "App"}
				if entity == "builds" {
					filters["configuration"] = "Release"
					filters["category"] = "incremental"
					filters["status"] = "failure"
				}
				for key, want := range filters {
					if r.URL.Query().Get(key) != want {
						t.Errorf("lost filter %s", key)
					}
				}
				_, _ = w.Write([]byte(`{"dates":[100,150],"average":{"values":[11,null],"total":11},"p50":{"values":[10,null],"total":10},"p90":{"values":[20,null],"total":20},"p99":{"values":[30,null],"total":30},"trend":0}`))
			}))
			defer server.Close()
			client, err := newTuistClient(backend.DataSourceInstanceSettings{JSONData: json.RawMessage(`{"url":"` + server.URL + `"}`), DecryptedSecureJSONData: map[string]string{"apiToken": "existing-token"}})
			if err != nil {
				t.Fatal(err)
			}
			queryType := "buildDuration"
			if entity == "tests" {
				queryType = "testDuration"
			}
			// This is the saved panel format from before whole-period queries existed.
			body := json.RawMessage(`{"queryType":"` + queryType + `","projectHandle":"acme/app","series":["p99","p50"],"environment":"ci","scheme":"App","configuration":"Release","category":"incremental","status":"failure"}`)
			response := (&Datasource{client: client}).query(context.Background(), backend.DataQuery{JSON: body, TimeRange: backend.TimeRange{From: time.Unix(100, 0), To: time.Unix(200, 0)}})
			if response.Error != nil {
				t.Fatal(response.Error)
			}
			frame := response.Frames[0]
			if frame.Name != "duration" || len(frame.Fields) != 3 || frame.Fields[0].Name != "time" || frame.Fields[1].Name != "p99" || frame.Fields[2].Name != "p50" {
				t.Fatal("existing frame names or series order changed")
			}
			if frame.Fields[0].At(0).(time.Time).Unix() != 100 {
				t.Fatal("timestamps changed")
			}
			if *frame.Fields[1].At(0).(*float64) != 30 || frame.Fields[1].At(1).(*float64) != nil || frame.Fields[1].Config.Unit != "ms" {
				t.Fatal("existing values, nulls or units changed")
			}
		})
	}
}

func TestLegacyGradleQueriesAndDashboardStayAvailable(t *testing.T) {
	body, err := os.ReadFile("../../src/dashboards/gradle-build-health.json")
	if err != nil {
		t.Fatal(err)
	}
	var dashboard struct {
		UID    string `json:"uid"`
		Panels []struct {
			Targets []queryModel `json:"targets"`
		} `json:"panels"`
	}
	if err = json.Unmarshal(body, &dashboard); err != nil {
		t.Fatal(err)
	}
	if dashboard.UID != "tuist-gradle-build-health" {
		t.Fatal("legacy dashboard identifier changed")
	}
	seen := map[string]bool{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/projects/acme/app/gradle/builds/metrics" {
			t.Errorf("legacy query changed endpoint: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"dates":[100],"series":{"p50":[1000]},"totals":{"p50":1000},"rows":[]}`))
	}))
	defer server.Close()
	for _, panel := range dashboard.Panels {
		for _, target := range panel.Targets {
			seen[target.QueryType] = true
		}
	}
	for _, queryType := range []string{"gradleHealth", "gradleWorkloads", "gradleFailureReasons", "gradleRecentFailures"} {
		if !seen[queryType] {
			t.Fatalf("missing legacy query %s in dashboard", queryType)
		}
		body, _ := json.Marshal(queryModel{QueryType: queryType, ProjectHandle: "acme/app", Metric: "p50", ResultMode: "total"})
		response := testDatasource(server).query(context.Background(), backend.DataQuery{JSON: body})
		if response.Error != nil {
			t.Fatal(response.Error)
		}
		if response.Frames[0].Name != queryType {
			t.Fatal("legacy frame name changed")
		}
	}
}

func TestExistingDurationPanelsWithoutSeriesKeepDefaults(t *testing.T) {
	// Older handles can contain dots even though new projects reject them.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/projects/acme/legacy.app/builds/metrics/duration" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"dates":[100],"average":{"values":[11],"total":11},"p50":{"values":[10],"total":10},"p90":{"values":[20],"total":20},"p99":{"values":[30],"total":30}}`))
	}))
	defer server.Close()
	response := testDatasource(server).query(context.Background(), backend.DataQuery{
		JSON:      json.RawMessage(`{"queryType":"buildDuration","projectHandle":"acme/legacy.app"}`),
		TimeRange: backend.TimeRange{From: time.Unix(100, 0), To: time.Unix(200, 0)},
	})
	if response.Error != nil {
		t.Fatal(response.Error)
	}
	frame := response.Frames[0]
	want := []string{"time", "average", "p50", "p90", "p99"}
	if len(frame.Fields) != len(want) {
		t.Fatalf("default series changed: got %d fields", len(frame.Fields))
	}
	for i, name := range want {
		if frame.Fields[i].Name != name {
			t.Fatalf("field %d: got %s, want %s", i, frame.Fields[i].Name, name)
		}
		if i > 0 && (frame.Fields[i].Config.Unit != "ms" || frame.Fields[i].Config.DisplayName != name) {
			t.Fatalf("default duration field configuration changed: %s", name)
		}
	}
}
