package plugin

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
	"github.com/grafana/grafana-plugin-sdk-go/backend/instancemgmt"
	"github.com/grafana/grafana-plugin-sdk-go/data"
)

var (
	_ backend.QueryDataHandler      = (*Datasource)(nil)
	_ backend.CheckHealthHandler    = (*Datasource)(nil)
	_ backend.CallResourceHandler   = (*Datasource)(nil)
	_ instancemgmt.InstanceDisposer = (*Datasource)(nil)
)

// Datasource serves Tuist build and test duration metrics to Grafana.
type Datasource struct {
	client *tuistClient
}

// NewDatasource is the instance factory invoked per datasource configuration.
func NewDatasource(_ context.Context, settings backend.DataSourceInstanceSettings) (instancemgmt.Instance, error) {
	client, err := newTuistClient(settings)
	if err != nil {
		return nil, err
	}
	return &Datasource{client: client}, nil
}

func (d *Datasource) Dispose() {}

func (d *Datasource) QueryData(ctx context.Context, req *backend.QueryDataRequest) (*backend.QueryDataResponse, error) {
	response := backend.NewQueryDataResponse()
	for _, q := range req.Queries {
		response.Responses[q.RefID] = d.query(ctx, q)
	}
	return response, nil
}

func (d *Datasource) query(ctx context.Context, q backend.DataQuery) backend.DataResponse {
	var qm queryModel
	if err := json.Unmarshal(q.JSON, &qm); err != nil {
		return backend.ErrDataResponse(backend.StatusBadRequest, "invalid query: "+err.Error())
	}

	entity, err := entityForQueryType(qm.QueryType)
	if err != nil {
		return backend.ErrDataResponse(backend.StatusBadRequest, err.Error())
	}
	if strings.TrimSpace(qm.ProjectHandle) == "" {
		return backend.ErrDataResponse(backend.StatusBadRequest, "a project must be selected")
	}

	metrics, err := d.client.durationMetrics(ctx, entity, qm.ProjectHandle, q.TimeRange.From.Unix(), q.TimeRange.To.Unix(), qm)
	if err != nil {
		return backend.ErrDataResponse(backend.StatusInternal, err.Error())
	}

	return backend.DataResponse{Frames: data.Frames{framesFromMetrics(qm, metrics)}}
}

func (d *Datasource) CheckHealth(ctx context.Context, _ *backend.CheckHealthRequest) (*backend.CheckHealthResult, error) {
	if _, err := d.client.projects(ctx); err != nil {
		return &backend.CheckHealthResult{
			Status:  backend.HealthStatusError,
			Message: "Could not reach Tuist with the provided token: " + err.Error(),
		}, nil
	}
	return &backend.CheckHealthResult{
		Status:  backend.HealthStatusOk,
		Message: "Connected to Tuist",
	}, nil
}

// CallResource backs the query editor dropdowns and template variables so the
// account token never leaves the backend.
func (d *Datasource) CallResource(ctx context.Context, req *backend.CallResourceRequest, sender backend.CallResourceResponseSender) error {
	parsed, err := url.Parse(req.URL)
	if err != nil {
		return sendJSON(sender, http.StatusBadRequest, map[string]string{"error": "invalid resource url"})
	}
	query := parsed.Query()

	switch strings.Trim(parsed.Path, "/") {
	case "projects":
		projects, err := d.client.projects(ctx)
		if err != nil {
			return sendJSON(sender, http.StatusBadGateway, map[string]string{"error": err.Error()})
		}
		return sendJSON(sender, http.StatusOK, projects)

	case "schemes":
		entity, err := normalizeEntity(query.Get("entity"))
		if err != nil {
			return sendJSON(sender, http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		schemes, err := d.client.schemes(ctx, entity, query.Get("project"))
		if err != nil {
			return sendJSON(sender, http.StatusBadGateway, map[string]string{"error": err.Error()})
		}
		return sendJSON(sender, http.StatusOK, schemes)

	case "configurations":
		configurations, err := d.client.configurations(ctx, query.Get("project"))
		if err != nil {
			return sendJSON(sender, http.StatusBadGateway, map[string]string{"error": err.Error()})
		}
		return sendJSON(sender, http.StatusOK, configurations)

	default:
		return sendJSON(sender, http.StatusNotFound, map[string]string{"error": "unknown resource"})
	}
}

func entityForQueryType(queryType string) (string, error) {
	switch queryType {
	case queryTypeBuildDuration:
		return entityBuilds, nil
	case queryTypeTestDuration:
		return entityTests, nil
	default:
		return "", fmt.Errorf("unknown query type %q", queryType)
	}
}

func normalizeEntity(entity string) (string, error) {
	switch entity {
	case entityBuilds, entityTests:
		return entity, nil
	default:
		return "", fmt.Errorf("unknown entity %q", entity)
	}
}

func sendJSON(sender backend.CallResourceResponseSender, status int, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return sender.Send(&backend.CallResourceResponse{
		Status:  status,
		Headers: map[string][]string{"Content-Type": {"application/json"}},
		Body:    body,
	})
}
