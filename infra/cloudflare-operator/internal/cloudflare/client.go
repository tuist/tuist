// Package cloudflare is a small wrapper over Cloudflare's Ruleset Engine
// REST API, scoped to the operator's needs: find or create a zone's
// http_ratelimit ruleset, then upsert or delete individual rules within
// it addressed by a stable ref the operator sets. Everything is
// idempotent so the reconciler can call it on every requeue without
// tracking Cloudflare-assigned ids in its own state.
package cloudflare

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	defaultBaseURL = "https://api.cloudflare.com/client/v4"

	// RateLimitPhase is the Ruleset Engine phase for rate limiting rules.
	// Every zone has at most one entrypoint ruleset per phase.
	RateLimitPhase = "http_ratelimit"

	// RulesetKind for zone-scoped entrypoint rulesets.
	rulesetKindZone = "zone"
)

// Client is a stateless HTTP client bound to one Cloudflare API token.
// Zero value is not usable; call New.
type Client struct {
	baseURL string
	token   string
	http    *http.Client
}

// New returns a Client that authenticates with token. Pass an empty
// baseURL to use Cloudflare's production API endpoint.
func New(token string, baseURL string) *Client {
	if baseURL == "" {
		baseURL = defaultBaseURL
	}
	return &Client{
		baseURL: baseURL,
		token:   token,
		http:    &http.Client{Timeout: 30 * time.Second},
	}
}

// Rule is one entry in a ruleset. The shape here covers what the
// operator sets today (rate limiting) and can be extended for other
// rule kinds later.
type Rule struct {
	ID          string          `json:"id,omitempty"`
	Version     string          `json:"version,omitempty"`
	Action      string          `json:"action"`
	Expression  string          `json:"expression"`
	Description string          `json:"description,omitempty"`
	Enabled     bool            `json:"enabled"`
	Ref         string          `json:"ref,omitempty"`
	RateLimit   *RuleRateLimit  `json:"ratelimit,omitempty"`
	LastUpdated string          `json:"last_updated,omitempty"`
	Extra       json.RawMessage `json:"-"`
}

// RuleRateLimit mirrors the Cloudflare rule's ratelimit block. Field
// names match the API's snake_case wire format.
type RuleRateLimit struct {
	Characteristics       []string `json:"characteristics"`
	Period                int      `json:"period"`
	RequestsPerPeriod     int      `json:"requests_per_period"`
	MitigationTimeout     int      `json:"mitigation_timeout"`
	CountingExpression    string   `json:"counting_expression,omitempty"`
	RequestsToOrigin      bool     `json:"requests_to_origin,omitempty"`
	ScorePerPeriod        int      `json:"score_per_period,omitempty"`
	ScoreResponseHeaderNm string   `json:"score_response_header_name,omitempty"`
}

// Ruleset is a phase entrypoint ruleset. Only the fields the operator
// reads are modeled.
type Ruleset struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Kind        string `json:"kind"`
	Phase       string `json:"phase"`
	Rules       []Rule `json:"rules"`
}

// GetRateLimitRuleset returns the zone's entrypoint http_ratelimit
// ruleset. If none exists yet Cloudflare returns 404 and this function
// returns (nil, nil) so callers can lazily create it.
func (c *Client) GetRateLimitRuleset(ctx context.Context, zoneID string) (*Ruleset, error) {
	path := fmt.Sprintf("/zones/%s/rulesets/phases/%s/entrypoint", zoneID, RateLimitPhase)
	var wrapper struct {
		Result Ruleset `json:"result"`
	}
	status, err := c.do(ctx, http.MethodGet, path, nil, &wrapper)
	if err != nil {
		return nil, err
	}
	if status == http.StatusNotFound {
		return nil, nil
	}
	return &wrapper.Result, nil
}

// CreateRateLimitRuleset creates the zone's http_ratelimit entrypoint
// ruleset. Cloudflare returns an error if one already exists; call
// GetRateLimitRuleset first.
func (c *Client) CreateRateLimitRuleset(ctx context.Context, zoneID string) (*Ruleset, error) {
	body := map[string]any{
		"name":        "default",
		"description": "Zone rate limiting ruleset (managed by cloudflare-operator).",
		"kind":        rulesetKindZone,
		"phase":       RateLimitPhase,
		"rules":       []Rule{},
	}
	path := fmt.Sprintf("/zones/%s/rulesets", zoneID)
	var wrapper struct {
		Result Ruleset `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodPost, path, body, &wrapper); err != nil {
		return nil, err
	}
	return &wrapper.Result, nil
}

// AddRule appends a rule to the ruleset and returns the resulting
// updated ruleset.
func (c *Client) AddRule(ctx context.Context, zoneID, rulesetID string, rule Rule) (*Ruleset, error) {
	path := fmt.Sprintf("/zones/%s/rulesets/%s/rules", zoneID, rulesetID)
	var wrapper struct {
		Result Ruleset `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodPost, path, rule, &wrapper); err != nil {
		return nil, err
	}
	return &wrapper.Result, nil
}

// UpdateRule replaces a rule addressed by its id.
func (c *Client) UpdateRule(ctx context.Context, zoneID, rulesetID, ruleID string, rule Rule) (*Ruleset, error) {
	path := fmt.Sprintf("/zones/%s/rulesets/%s/rules/%s", zoneID, rulesetID, ruleID)
	var wrapper struct {
		Result Ruleset `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodPatch, path, rule, &wrapper); err != nil {
		return nil, err
	}
	return &wrapper.Result, nil
}

// DeleteRule removes a rule from the ruleset. Returns nil if the rule
// is already gone.
func (c *Client) DeleteRule(ctx context.Context, zoneID, rulesetID, ruleID string) error {
	path := fmt.Sprintf("/zones/%s/rulesets/%s/rules/%s", zoneID, rulesetID, ruleID)
	status, err := c.do(ctx, http.MethodDelete, path, nil, nil)
	if err != nil {
		if status == http.StatusNotFound {
			return nil
		}
		return err
	}
	return nil
}

// FindRuleByRef returns the rule in ruleset whose Ref matches, or nil.
// Cloudflare guarantees Ref is unique within a ruleset when the caller
// sets it.
func FindRuleByRef(rs *Ruleset, ref string) *Rule {
	if rs == nil || ref == "" {
		return nil
	}
	for i := range rs.Rules {
		if rs.Rules[i].Ref == ref {
			return &rs.Rules[i]
		}
	}
	return nil
}

// APIError is returned when Cloudflare responds with a non-2xx status.
type APIError struct {
	Status  int
	Body    string
	Errors  []APIErrorDetail
	Message string
}

// APIErrorDetail is one entry in Cloudflare's `errors` array.
type APIErrorDetail struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *APIError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("cloudflare api %d: %s", e.Status, e.Message)
	}
	return fmt.Sprintf("cloudflare api %d: %s", e.Status, e.Body)
}

func (c *Client) do(ctx context.Context, method, path string, body any, out any) (int, error) {
	var buf io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return 0, fmt.Errorf("marshal request body: %w", err)
		}
		buf = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, buf)
	if err != nil {
		return 0, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("perform request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp.StatusCode, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode == http.StatusNotFound {
		return resp.StatusCode, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		apiErr := &APIError{Status: resp.StatusCode, Body: string(respBody)}
		var parsed struct {
			Success  bool             `json:"success"`
			Errors   []APIErrorDetail `json:"errors"`
			Messages []APIErrorDetail `json:"messages"`
		}
		if jsonErr := json.Unmarshal(respBody, &parsed); jsonErr == nil {
			apiErr.Errors = parsed.Errors
			if len(parsed.Errors) > 0 {
				apiErr.Message = parsed.Errors[0].Message
			}
		}
		return resp.StatusCode, apiErr
	}
	if out != nil {
		if err := json.Unmarshal(respBody, out); err != nil {
			return resp.StatusCode, fmt.Errorf("decode response: %w", err)
		}
	}
	return resp.StatusCode, nil
}

// IsNotFound reports whether an error came from a 404 from the API.
func IsNotFound(err error) bool {
	var apiErr *APIError
	if errors.As(err, &apiErr) {
		return apiErr.Status == http.StatusNotFound
	}
	return false
}
