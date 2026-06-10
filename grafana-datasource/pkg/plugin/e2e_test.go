package plugin

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

// These tests exercise the plugin backend against a live Tuist server. They are
// skipped unless TUIST_E2E_TOKEN is set, so they never run in CI.
//
//	TUIST_E2E_TOKEN=<account token> \
//	TUIST_E2E_URL=http://localhost:8080 \
//	TUIST_E2E_PROJECT=account/project \
//	go test ./pkg/plugin/ -run E2E -v

func liveDatasource(t *testing.T) (*Datasource, string) {
	t.Helper()
	token := os.Getenv("TUIST_E2E_TOKEN")
	if token == "" {
		t.Skip("set TUIST_E2E_TOKEN to run the live e2e tests")
	}
	url := os.Getenv("TUIST_E2E_URL")
	if url == "" {
		url = "http://localhost:8080"
	}
	settings := backend.DataSourceInstanceSettings{
		JSONData:                []byte(`{"url":"` + url + `"}`),
		DecryptedSecureJSONData: map[string]string{"apiToken": token},
	}
	inst, err := NewDatasource(context.Background(), settings)
	if err != nil {
		t.Fatalf("NewDatasource: %v", err)
	}
	project := os.Getenv("TUIST_E2E_PROJECT")
	if project == "" {
		project = "tuist/tuist"
	}
	return inst.(*Datasource), project
}

func runQuery(t *testing.T, ds *Datasource, qm queryModel) *backend.DataResponse {
	t.Helper()
	raw, err := json.Marshal(qm)
	if err != nil {
		t.Fatalf("marshal query: %v", err)
	}
	resp, err := ds.QueryData(context.Background(), &backend.QueryDataRequest{
		Queries: []backend.DataQuery{{
			RefID: "A",
			JSON:  raw,
			TimeRange: backend.TimeRange{
				From: time.Now().Add(-30 * 24 * time.Hour),
				To:   time.Now(),
			},
		}},
	})
	if err != nil {
		t.Fatalf("QueryData: %v", err)
	}
	dr := resp.Responses["A"]
	return &dr
}

func TestE2EBuildDuration(t *testing.T) {
	ds, project := liveDatasource(t)
	dr := runQuery(t, ds, queryModel{
		QueryType:     queryTypeBuildDuration,
		ProjectHandle: project,
		Series:        []string{"p50", "p90", "p99"},
	})
	if dr.Error != nil {
		t.Fatalf("response error: %v", dr.Error)
	}
	if len(dr.Frames) != 1 {
		t.Fatalf("want 1 frame, got %d", len(dr.Frames))
	}
	frame := dr.Frames[0]
	if len(frame.Fields) != 4 { // time + p50 + p90 + p99
		t.Fatalf("want 4 fields, got %d", len(frame.Fields))
	}
	if frame.Fields[0].Name != "time" {
		t.Fatalf("first field should be time, got %q", frame.Fields[0].Name)
	}
	points := frame.Fields[0].Len()
	if points == 0 {
		t.Fatal("expected at least one data point")
	}
	t.Logf("buildDuration: %d points, fields=[time %s %s %s]", points,
		frame.Fields[1].Name, frame.Fields[2].Name, frame.Fields[3].Name)
}

func TestE2ETestDuration(t *testing.T) {
	ds, project := liveDatasource(t)
	dr := runQuery(t, ds, queryModel{
		QueryType:     queryTypeTestDuration,
		ProjectHandle: project,
		Series:        []string{"average", "p50", "p90", "p99"},
	})
	if dr.Error != nil {
		t.Fatalf("response error: %v", dr.Error)
	}
	frame := dr.Frames[0]
	if len(frame.Fields) != 5 { // time + average + p50 + p90 + p99
		t.Fatalf("want 5 fields, got %d", len(frame.Fields))
	}
	t.Logf("testDuration: %d points", frame.Fields[0].Len())
}

func TestE2ECheckHealth(t *testing.T) {
	ds, _ := liveDatasource(t)
	res, err := ds.CheckHealth(context.Background(), &backend.CheckHealthRequest{})
	if err != nil {
		t.Fatalf("CheckHealth: %v", err)
	}
	if res.Status != backend.HealthStatusOk {
		t.Fatalf("want healthy, got %v: %s", res.Status, res.Message)
	}
	t.Logf("CheckHealth: %s", res.Message)
}

type captureSender struct {
	resp *backend.CallResourceResponse
}

func (c *captureSender) Send(r *backend.CallResourceResponse) error {
	c.resp = r
	return nil
}

func TestE2ECallResourceProjects(t *testing.T) {
	ds, projectHandle := liveDatasource(t)
	sender := &captureSender{}
	err := ds.CallResource(context.Background(), &backend.CallResourceRequest{
		Path:   "projects",
		URL:    "projects",
		Method: "GET",
	}, sender)
	if err != nil {
		t.Fatalf("CallResource: %v", err)
	}
	if sender.resp.Status != 200 {
		t.Fatalf("want 200, got %d: %s", sender.resp.Status, string(sender.resp.Body))
	}
	var projects []project
	if err := json.Unmarshal(sender.resp.Body, &projects); err != nil {
		t.Fatalf("decode projects: %v", err)
	}
	found := false
	for _, p := range projects {
		if p.FullName == projectHandle {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected project %q in resource response", projectHandle)
	}
	t.Logf("CallResource projects: %d returned", len(projects))
}
