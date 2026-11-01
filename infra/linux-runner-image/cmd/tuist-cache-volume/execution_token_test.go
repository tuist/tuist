package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestExecutionTokenIsRequestedForTheRunnerCacheAudience(t *testing.T) {
	github := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("audience") != executionTokenAudience || r.URL.Query().Get("api-version") != "2.0" {
			t.Errorf("query = %s", r.URL.RawQuery)
		}
		if r.Header.Get("Authorization") != "bearer request-token" {
			t.Errorf("authorization = %q", r.Header.Get("Authorization"))
		}
		w.Write([]byte(`{"value":"jwt"}`))
	}))
	defer github.Close()

	token, err := requestExecutionToken(context.Background(), github.Client(), github.URL+"/idtoken?api-version=2.0", "request-token")
	if err != nil || token != "jwt" {
		t.Fatalf("token = %q, %v", token, err)
	}
}

func TestExecutionTokenNeedsTheJobsPermission(t *testing.T) {
	for _, env := range [][2]string{{"", "request-token"}, {"https://github.example/idtoken", ""}} {
		if _, err := requestExecutionToken(context.Background(), http.DefaultClient, env[0], env[1]); !errors.Is(err, errNoIDToken) {
			t.Fatalf("%v: err = %v", env, err)
		}
	}
	if _, err := requestExecutionToken(context.Background(), http.DefaultClient, "http://github.example/idtoken", "request-token"); err == nil {
		t.Fatal("token requested over plain HTTP")
	}
}

func TestExecutionTokenRejectsFailedAndOversizedAnswers(t *testing.T) {
	for name, handler := range map[string]http.HandlerFunc{
		"status": func(w http.ResponseWriter, _ *http.Request) { http.Error(w, "denied", http.StatusForbidden) },
		"empty":  func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte(`{"value":""}`)) },
		"oversized": func(w http.ResponseWriter, _ *http.Request) {
			w.Write([]byte(`{"value":"` + strings.Repeat("a", maxExecutionToken+1) + `"}`))
		},
	} {
		github := httptest.NewTLSServer(handler)
		if _, err := requestExecutionToken(context.Background(), github.Client(), github.URL, "request-token"); err == nil {
			t.Errorf("%s: token accepted", name)
		}
		github.Close()
	}
}

func TestExecutionTokenReachesTheLinuxAgentWithThePod(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]string
		data, _ := io.ReadAll(r.Body)
		if r.URL.Path != "/execution" || json.Unmarshal(data, &body) != nil {
			t.Errorf("request = %s %s", r.URL.Path, data)
		}
		if body["pod_name"] != "runner-pod" || body["pod_uid"] != "runner-uid" || body["token"] != "jwt" {
			t.Errorf("body = %v", body)
		}
		w.Write([]byte(`{}`))
	}))
	defer agent.Close()
	t.Setenv("TUIST_CACHE_VOLUME_URL", agent.URL)
	t.Setenv("TUIST_CACHE_VOLUME_POD", "runner-pod")
	t.Setenv("TUIST_CACHE_VOLUME_UID", "runner-uid")

	if err := presentExecutionLinux(context.Background(), "jwt"); err != nil {
		t.Fatal(err)
	}
}

func TestExecutionTokenReachesTheMacMailbox(t *testing.T) {
	share := t.TempDir()
	requests := make(chan string, 1)
	go func() {
		for {
			paths, _ := filepath.Glob(filepath.Join(share, "*.request"))
			if len(paths) == 1 {
				data, _ := os.ReadFile(paths[0])
				requests <- string(data)
				_ = os.WriteFile(paths[0]+".response", []byte(`{}`), 0600)
				return
			}
			time.Sleep(time.Millisecond)
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := presentExecutionMac(ctx, share, "jwt"); err != nil {
		t.Fatal(err)
	}
	if got := <-requests; got != `{"execution_token":"jwt"}` {
		t.Fatalf("request = %s", got)
	}
}

func TestExecutionTokenIsSkippedQuietlyWithoutThePermission(t *testing.T) {
	t.Setenv("ACTIONS_ID_TOKEN_REQUEST_URL", "")
	t.Setenv("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "")
	if result := proveExecution(); result != "" {
		t.Fatalf("result = %q", result)
	}
	if opts, err := parseArguments([]string{"--prove-execution"}, io.Discard); err != nil || !opts.proveExecution {
		t.Fatalf("options = %+v, %v", opts, err)
	}
}
