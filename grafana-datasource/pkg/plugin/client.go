package plugin

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

// tuistClient talks to the Tuist server's JSON API using an account token.
type tuistClient struct {
	baseURL string
	token   string
	http    *http.Client
}

func newTuistClient(settings backend.DataSourceInstanceSettings) (*tuistClient, error) {
	var s dataSourceSettings
	if len(settings.JSONData) > 0 {
		if err := json.Unmarshal(settings.JSONData, &s); err != nil {
			return nil, fmt.Errorf("parsing datasource settings: %w", err)
		}
	}

	baseURL := firstNonEmpty(s.URL, "https://tuist.dev")

	return &tuistClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   settings.DecryptedSecureJSONData["apiToken"],
		http:    &http.Client{Timeout: 30 * time.Second},
	}, nil
}

func (c *tuistClient) get(ctx context.Context, path string, query url.Values, out any) error {
	endpoint := c.baseURL + path
	if len(query) > 0 {
		endpoint += "?" + query.Encode()
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("tuist API %s returned %d: %s", path, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(body, out)
}

func (c *tuistClient) durationMetrics(ctx context.Context, entity, projectHandle string, from, to int64, qm queryModel) (*durationMetrics, error) {
	q := url.Values{}
	q.Set("from", strconv.FormatInt(from, 10))
	q.Set("to", strconv.FormatInt(to, 10))
	switch qm.Environment {
	case "ci":
		q.Set("is_ci", "true")
	case "local":
		q.Set("is_ci", "false")
	}
	setIfNotEmpty(q, "scheme", qm.Scheme)
	if entity == entityBuilds {
		setIfNotEmpty(q, "configuration", qm.Configuration)
		setIfNotEmpty(q, "category", qm.Category)
		setIfNotEmpty(q, "status", qm.Status)
	}

	var out durationMetrics
	path := fmt.Sprintf("/api/projects/%s/%s/metrics/duration", projectHandle, entity)
	if err := c.get(ctx, path, q, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *tuistClient) projects(ctx context.Context) ([]project, error) {
	var out struct {
		Projects []project `json:"projects"`
	}
	if err := c.get(ctx, "/api/projects", nil, &out); err != nil {
		return nil, err
	}
	return out.Projects, nil
}

func (c *tuistClient) dimensionValues(ctx context.Context, entity, dimension, projectHandle string) ([]string, error) {
	var out struct {
		Values []string `json:"values"`
	}
	path := fmt.Sprintf("/api/projects/%s/%s/metrics/dimensions/%s/values", projectHandle, entity, dimension)
	if err := c.get(ctx, path, nil, &out); err != nil {
		return nil, err
	}
	return out.Values, nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if trimmed := strings.TrimSpace(v); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func setIfNotEmpty(q url.Values, key, value string) {
	if strings.TrimSpace(value) != "" {
		q.Set(key, value)
	}
}
