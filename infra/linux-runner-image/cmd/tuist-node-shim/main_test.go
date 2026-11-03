package main

import (
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"
)

func TestEnvironmentPointsTheResultsServiceAtAHealthyAgent(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != healthPath {
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer agent.Close()
	env := []string{"PATH=/bin", "ACTIONS_RESULTS_URL=" + githubResultsURL + "/", "TUIST_CACHE_VOLUME_URL=" + agent.URL}

	got := environment(env, probe)
	if !slices.Contains(got, "ACTIONS_RESULTS_URL="+agent.URL+"/") || !slices.Contains(got, "PATH=/bin") {
		t.Fatalf("environment %v", got)
	}
	if env[1] != "ACTIONS_RESULTS_URL="+githubResultsURL+"/" {
		t.Fatalf("changed the caller's environment: %v", env)
	}
}

func TestEnvironmentLeavesTheRunnersValueOtherwise(t *testing.T) {
	healthy := func(string) bool { return true }
	github := "ACTIONS_RESULTS_URL=" + githubResultsURL + "/"
	agent := "TUIST_CACHE_VOLUME_URL=http://agent:8090"
	for name, env := range map[string][]string{
		"no agent":            {github},
		"another service":     {"ACTIONS_RESULTS_URL=https://ghes.example.com/", agent},
		"turned off":          {github, agent, "TUIST_ACTIONS_CACHE=false"},
		"turned off with 0":   {github, agent, "TUIST_ACTIONS_CACHE=0"},
		"not an http address": {github, "TUIST_CACHE_VOLUME_URL=/tmp/socket"},
	} {
		if got := environment(env, healthy); !slices.Equal(got, env) {
			t.Errorf("%s: environment %v", name, got)
		}
	}
	env := []string{github, agent}
	if got := environment(env, func(string) bool { return false }); !slices.Equal(got, env) {
		t.Errorf("unhealthy agent: environment %v", got)
	}
}

func TestProbeGivesUpQuickly(t *testing.T) {
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(time.Second)
	}))
	defer slow.Close()
	start := time.Now()
	if probe(slow.URL + healthPath) {
		t.Fatal("a slow agent passed")
	}
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Fatalf("probe waited %s", elapsed)
	}
}
