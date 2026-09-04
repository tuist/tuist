package cloudflare

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestGetRateLimitRuleset_Success confirms the client parses the
// standard Ruleset response envelope Cloudflare uses.
func TestGetRateLimitRuleset_Success(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Errorf("method = %s, want GET", r.Method)
		}
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Errorf("missing bearer token")
		}
		want := "/zones/zone-abc/rulesets/phases/http_ratelimit/entrypoint"
		if r.URL.Path != want {
			t.Errorf("path = %s, want %s", r.URL.Path, want)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"result":{"id":"rs-1","name":"default","kind":"zone","phase":"http_ratelimit","rules":[{"id":"r1","ref":"cfop_test_abc","action":"managed_challenge"}]}}`))
	}))
	defer server.Close()

	c := New("test-token", server.URL)
	rs, err := c.GetRateLimitRuleset(context.Background(), "zone-abc")
	if err != nil {
		t.Fatalf("GetRateLimitRuleset: %v", err)
	}
	if rs == nil || rs.ID != "rs-1" || len(rs.Rules) != 1 {
		t.Fatalf("unexpected ruleset: %+v", rs)
	}
	if rs.Rules[0].Ref != "cfop_test_abc" {
		t.Errorf("ref = %s", rs.Rules[0].Ref)
	}
}

// TestGetRateLimitRuleset_NotFoundReturnsNil documents the lazy-create
// contract: a 404 from Cloudflare on the entrypoint lookup surfaces as
// (nil, nil) so the reconciler can create the ruleset without treating
// the absence as an error.
func TestGetRateLimitRuleset_NotFoundReturnsNil(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"success":false,"errors":[{"code":10101,"message":"ruleset not found"}]}`))
	}))
	defer server.Close()

	c := New("t", server.URL)
	rs, err := c.GetRateLimitRuleset(context.Background(), "zone-abc")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if rs != nil {
		t.Fatalf("expected nil ruleset on 404, got %+v", rs)
	}
}

// TestAddRule_SendsPayload asserts the client marshals the rule fields
// Cloudflare expects (in particular the snake-case ratelimit block).
func TestAddRule_SendsPayload(t *testing.T) {
	var got Rule
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/rules") {
			t.Errorf("path = %s", r.URL.Path)
		}
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Fatalf("decode: %v", err)
		}
		_, _ = w.Write([]byte(`{"result":{"id":"rs-1","rules":[{"id":"new","ref":"cfop_x"}]}}`))
	}))
	defer server.Close()

	c := New("t", server.URL)
	_, err := c.AddRule(context.Background(), "zone-abc", "rs-1", Rule{
		Action:      "managed_challenge",
		Expression:  `http.request.method eq "GET"`,
		Description: "test",
		Enabled:     true,
		Ref:         "cfop_x",
		RateLimit: &RuleRateLimit{
			Characteristics:   []string{"ip.src"},
			Period:            10,
			RequestsPerPeriod: 60,
			MitigationTimeout: 60,
		},
	})
	if err != nil {
		t.Fatalf("AddRule: %v", err)
	}
	if got.RateLimit == nil {
		t.Fatal("payload missing ratelimit block")
	}
	if got.RateLimit.RequestsPerPeriod != 60 {
		t.Errorf("requests_per_period = %d", got.RateLimit.RequestsPerPeriod)
	}
	if got.Ref != "cfop_x" {
		t.Errorf("ref = %s", got.Ref)
	}
}

// TestFindRuleByRef exercises the pure helper used by the reconciler
// to locate its rule inside a full ruleset response.
func TestFindRuleByRef(t *testing.T) {
	rs := &Ruleset{Rules: []Rule{{Ref: "a"}, {Ref: "b"}, {Ref: "c"}}}
	if r := FindRuleByRef(rs, "b"); r == nil || r.Ref != "b" {
		t.Errorf("FindRuleByRef(b) = %+v", r)
	}
	if r := FindRuleByRef(rs, "missing"); r != nil {
		t.Errorf("FindRuleByRef(missing) = %+v", r)
	}
	if r := FindRuleByRef(nil, "a"); r != nil {
		t.Errorf("FindRuleByRef(nil, _) = %+v", r)
	}
	if r := FindRuleByRef(rs, ""); r != nil {
		t.Errorf("FindRuleByRef(_, \"\") = %+v", r)
	}
}

// TestAPIError_MessagePropagation confirms error details lift out of
// Cloudflare's error envelope so operator logs show the underlying
// reason rather than raw JSON.
func TestAPIError_MessagePropagation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"success":false,"errors":[{"code":10014,"message":"expression is invalid"}]}`))
	}))
	defer server.Close()

	c := New("t", server.URL)
	_, err := c.AddRule(context.Background(), "z", "rs-1", Rule{Action: "block"})
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "expression is invalid") {
		t.Errorf("expected api message in error, got %q", err.Error())
	}
}
