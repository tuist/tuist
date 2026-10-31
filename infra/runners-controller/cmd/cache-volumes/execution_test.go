package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func presentExecution(t *testing.T, a *agent, ip string, body map[string]any) int {
	t.Helper()
	data, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/execution", bytes.NewReader(data))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	return w.Code
}

func executionAgent(t *testing.T, status int) (*agent, map[string]any) {
	t.Helper()
	a, _ := dockerAgent(t, http.StatusOK)
	forwarded := map[string]any{}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/execution" || r.Header.Get("Authorization") != "Bearer agent-token" {
			t.Errorf("request %s with %q", r.URL.Path, r.Header.Get("Authorization"))
		}
		_ = json.NewDecoder(r.Body).Decode(&forwarded)
		w.WriteHeader(status)
		w.Write([]byte("{}"))
	}))
	t.Cleanup(upstream.Close)
	a.authorizeURL, a.http = upstream.URL+"/authorize", upstream.Client()
	return a, forwarded
}

func TestExecutionTokenIsForwardedWithTheNode(t *testing.T) {
	a, forwarded := executionAgent(t, http.StatusOK)
	if code := presentExecution(t, a, "10.0.0.5", map[string]any{"pod_name": "runner", "pod_uid": "uid", "token": "jwt"}); code != http.StatusOK {
		t.Fatalf("answered %d", code)
	}
	if forwarded["token"] != "jwt" || forwarded["pod_name"] != "runner" || forwarded["pod_uid"] != "uid" || forwarded["node_name"] != "node" {
		t.Fatalf("server told %v", forwarded)
	}
}

func TestExecutionTokenOnlyFromItsOwnPod(t *testing.T) {
	a, forwarded := executionAgent(t, http.StatusOK)
	if code := presentExecution(t, a, "10.0.0.9", map[string]any{"pod_name": "runner", "pod_uid": "uid", "token": "jwt"}); code != http.StatusForbidden {
		t.Fatalf("another address answered %d", code)
	}
	if code := presentExecution(t, a, "10.0.0.5", map[string]any{"pod_name": "runner", "pod_uid": "uid"}); code != http.StatusBadRequest {
		t.Fatalf("missing token answered %d", code)
	}
	if len(forwarded) != 0 {
		t.Fatalf("forwarded %v", forwarded)
	}
}

func TestExecutionTokenRejectedByTheServer(t *testing.T) {
	a, _ := executionAgent(t, http.StatusForbidden)
	if code := presentExecution(t, a, "10.0.0.5", map[string]any{"pod_name": "runner", "pod_uid": "uid", "token": "jwt"}); code != http.StatusForbidden {
		t.Fatalf("answered %d", code)
	}
}
