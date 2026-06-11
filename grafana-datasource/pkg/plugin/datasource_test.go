package plugin

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

func testDatasource(server *httptest.Server) *Datasource {
	return &Datasource{client: &tuistClient{baseURL: server.URL, http: server.Client()}}
}

// Grafana sends the resource path in req.Path and the full forwarded URL (with a
// "plugins/.../resources/" prefix) in req.URL. Dispatch must use req.Path.
func TestCallResourceDispatchesOnPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/projects" {
			_, _ = w.Write([]byte(`{"projects":[{"full_name":"acme/app"}]}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	sender := &captureSender{}
	req := &backend.CallResourceRequest{
		Method: http.MethodGet,
		Path:   "projects",
		URL:    "plugins/tuist-metrics-datasource/resources/projects?foo=bar",
	}
	if err := testDatasource(server).CallResource(context.Background(), req, sender); err != nil {
		t.Fatalf("CallResource error: %v", err)
	}
	if sender.resp.Status != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", sender.resp.Status, sender.resp.Body)
	}
	if !strings.Contains(string(sender.resp.Body), "acme/app") {
		t.Fatalf("expected projects in body, got %s", sender.resp.Body)
	}
}

func TestCallResourceSchemesUsesQueryParams(t *testing.T) {
	var gotPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		_, _ = w.Write([]byte(`{"schemes":["App"]}`))
	}))
	defer server.Close()

	sender := &captureSender{}
	req := &backend.CallResourceRequest{
		Method: http.MethodGet,
		Path:   "schemes",
		URL:    "plugins/tuist-metrics-datasource/resources/schemes?entity=tests&project=acme/app",
	}
	if err := testDatasource(server).CallResource(context.Background(), req, sender); err != nil {
		t.Fatalf("CallResource error: %v", err)
	}
	if sender.resp.Status != http.StatusOK {
		t.Fatalf("expected 200, got %d", sender.resp.Status)
	}
	if gotPath != "/api/projects/acme/app/tests/metrics/schemes" {
		t.Fatalf("expected the test schemes path from query params, got %q", gotPath)
	}
}

// A token can list projects without the metric read scopes, so health must probe
// a scoped endpoint and fail when it 403s.
func TestCheckHealthErrorsWhenMetricScopesMissing(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/api/projects":
			_, _ = w.Write([]byte(`{"projects":[{"full_name":"acme/app"}]}`))
		case strings.HasSuffix(r.URL.Path, "/metrics/schemes"):
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"message":"forbidden"}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	res, err := testDatasource(server).CheckHealth(context.Background(), &backend.CheckHealthRequest{})
	if err != nil {
		t.Fatalf("CheckHealth error: %v", err)
	}
	if res.Status != backend.HealthStatusError {
		t.Fatalf("expected error health for a mis-scoped token, got %v (%s)", res.Status, res.Message)
	}
}

func TestCheckHealthOKWhenScopesPresent(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/api/projects":
			_, _ = w.Write([]byte(`{"projects":[{"full_name":"acme/app"}]}`))
		case strings.HasSuffix(r.URL.Path, "/metrics/schemes"):
			_, _ = w.Write([]byte(`{"schemes":["App"]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	res, err := testDatasource(server).CheckHealth(context.Background(), &backend.CheckHealthRequest{})
	if err != nil {
		t.Fatalf("CheckHealth error: %v", err)
	}
	if res.Status != backend.HealthStatusOk {
		t.Fatalf("expected OK health, got %v (%s)", res.Status, res.Message)
	}
}
