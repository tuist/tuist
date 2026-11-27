package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestActionsServerWaitsForTheJobThenMapsConflicts(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer agent-token" {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		if body["node_name"] != "node" {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		switch r.URL.Path {
		case "/lookup":
			if requests.Add(1) == 1 {
				w.WriteHeader(http.StatusTooEarly)
				return
			}
			json.NewEncoder(w).Encode(map[string]any{"entry": map[string]any{"id": "e", "key": body["key"], "size_bytes": 3}})
		case "/enabled":
			json.NewEncoder(w).Encode(map[string]any{"enabled": body["pod_name"] == "pod"})
		case "/reserve":
			w.WriteHeader(http.StatusConflict)
		case "/upload":
			json.NewEncoder(w).Encode(map[string]any{"upload_url": "https://storage/object", "checksum": "c2hh"})
		case "/commit":
			w.WriteHeader(http.StatusNoContent)
		}
	}))
	defer server.Close()
	index := &ActionsServer{URL: server.URL, Node: "node", Token: func(context.Context) (string, error) { return "agent-token", nil }, Client: server.Client()}
	caller := ActionsCaller{PodName: "pod", PodUID: "uid"}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	entry, err := index.Lookup(ctx, caller, "deps", nil, "v1")
	if err != nil || entry == nil || entry.Key != "deps" || requests.Load() != 2 {
		t.Fatalf("lookup %+v, %v after %d requests", entry, err, requests.Load())
	}
	if enabled, err := index.Enabled(ctx, caller); !enabled || err != nil {
		t.Fatalf("enabled %v, %v", enabled, err)
	}
	if enabled, err := index.Enabled(ctx, ActionsCaller{PodName: "other"}); enabled || err != nil {
		t.Fatalf("enabled for another pod %v, %v", enabled, err)
	}
	if err := index.Reserve(ctx, caller, "id", "deps", "v1"); !errors.Is(err, ErrConflict) {
		t.Fatalf("reserve %v", err)
	}
	upload, err := index.Upload(ctx, "id", 3, "sum")
	if err != nil || upload.URL != "https://storage/object" || upload.Checksum != "c2hh" {
		t.Fatalf("upload %+v, %v", upload, err)
	}
	if err := index.Commit(ctx, "id"); err != nil {
		t.Fatalf("commit %v", err)
	}
}

func TestActionsServerGivesUpOnAPendingJobWhenTheRequestEnds(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooEarly)
	}))
	defer server.Close()
	index := &ActionsServer{URL: server.URL, Node: "node", Token: func(context.Context) (string, error) { return "agent-token", nil }, Client: server.Client()}

	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()
	if _, err := index.Lookup(ctx, ActionsCaller{}, "deps", nil, "v1"); !errors.Is(err, ErrExecutionPending) {
		t.Fatalf("lookup %v", err)
	}
}
