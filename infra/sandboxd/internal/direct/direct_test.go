package direct

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
)

type fakeClaims struct {
	sandboxID string
	nonce     []byte
	value     string
	outcome   sandbox.ClaimOutcome
	err       error
}

func (f *fakeClaims) Claim(_ context.Context, sandboxID string, nonce []byte, value string, _ time.Duration) (sandbox.ClaimOutcome, error) {
	f.sandboxID, f.nonce, f.value = sandboxID, nonce, value
	return f.outcome, f.err
}

func post(t *testing.T, h http.Handler, body string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/claims", strings.NewReader(body)))
	return rec
}

func nonceBody(value string) string {
	b, _ := json.Marshal(map[string]any{"sandbox_id": "s1", "nonce": bytes.Repeat([]byte{7}, 32), "value": value})
	return string(b)
}

func TestClaimReturnsTheCommandOutput(t *testing.T) {
	claims := &fakeClaims{outcome: sandbox.ClaimOutcome{ExitCode: 0, Stdout: []byte(`{"response":"x"}`)}}
	rec := post(t, NewHandler(claims), nonceBody(`{"hash":"h"}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d %s", rec.Code, rec.Body)
	}
	var got struct {
		ExitCode int    `json:"exit_code"`
		Stdout   []byte `json:"stdout"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || string(got.Stdout) != `{"response":"x"}` {
		t.Fatalf("body %s", rec.Body)
	}
	if claims.sandboxID != "s1" || !bytes.Equal(claims.nonce, bytes.Repeat([]byte{7}, 32)) || claims.value != `{"hash":"h"}` {
		t.Fatalf("claim %+v", claims)
	}
}

func TestClaimRefusals(t *testing.T) {
	for name, tc := range map[string]struct {
		claims *fakeClaims
		body   string
		status int
	}{
		"refused":     {&fakeClaims{err: sandbox.ErrClaimRefused}, nonceBody("{}"), http.StatusNotFound},
		"exec error":  {&fakeClaims{outcome: sandbox.ClaimOutcome{Err: errors.New("vsock")}}, nonceBody("{}"), http.StatusBadGateway},
		"short nonce": {&fakeClaims{}, `{"sandbox_id":"s1","nonce":"AAAA","value":"{}"}`, http.StatusBadRequest},
		"no sandbox":  {&fakeClaims{}, `{"nonce":"` + strings.Repeat("A", 43) + `=","value":"{}"}`, http.StatusBadRequest},
		"malformed":   {&fakeClaims{}, `{`, http.StatusBadRequest},
	} {
		t.Run(name, func(t *testing.T) {
			if rec := post(t, NewHandler(tc.claims), tc.body); rec.Code != tc.status {
				t.Fatalf("status %d, want %d: %s", rec.Code, tc.status, rec.Body)
			}
		})
	}
}
