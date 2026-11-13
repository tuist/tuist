package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
)

func runnerPod(name, uid, node, ip string, phase corev1.PodPhase) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "runners", UID: types.UID(uid), Labels: map[string]string{"tuist.dev/runner": "true"}},
		Spec:       corev1.PodSpec{NodeName: node},
		Status:     corev1.PodStatus{PodIP: ip, Phase: phase},
	}
}

func TestRunnerPodsResolveOnlyRunningRunnersOnThisNode(t *testing.T) {
	pods := &runnerPods{namespace: "runners", node: "node", kube: fake.NewSimpleClientset(
		runnerPod("runner", "uid-1", "node", "10.0.0.1", corev1.PodRunning),
		runnerPod("elsewhere", "uid-2", "other", "10.0.0.2", corev1.PodRunning),
		runnerPod("finished", "uid-3", "node", "10.0.0.3", corev1.PodSucceeded),
	)}

	caller, err := pods.caller(context.Background(), "10.0.0.1")
	if err != nil || caller != (cachevolumes.ActionsCaller{PodName: "runner", PodUID: "uid-1"}) {
		t.Fatalf("resolved %+v, %v", caller, err)
	}
	pods.listed = time.Time{}
	for _, ip := range []string{"10.0.0.2", "10.0.0.3", "10.0.0.9"} {
		pods.listed = time.Time{}
		if _, err := pods.caller(context.Background(), ip); !errors.Is(err, errUnknownCaller) {
			t.Fatalf("resolved %s: %v", ip, err)
		}
	}
}

func TestActionsIndexWaitsForTheJobThenMapsConflicts(t *testing.T) {
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
	tokenPath := filepath.Join(t.TempDir(), "token")
	os.WriteFile(tokenPath, []byte("agent-token\n"), 0o600)
	index := &actionsIndex{url: server.URL, node: "node", tokenPath: tokenPath, client: server.Client()}
	caller := cachevolumes.ActionsCaller{PodName: "pod", PodUID: "uid"}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	entry, err := index.Lookup(ctx, caller, "deps", nil, "v1")
	if err != nil || entry == nil || entry.Key != "deps" || requests.Load() != 2 {
		t.Fatalf("lookup %+v, %v after %d requests", entry, err, requests.Load())
	}
	if enabled, err := index.Enabled(ctx, caller); !enabled || err != nil {
		t.Fatalf("enabled %v, %v", enabled, err)
	}
	if enabled, err := index.Enabled(ctx, cachevolumes.ActionsCaller{PodName: "other"}); enabled || err != nil {
		t.Fatalf("enabled for another pod %v, %v", enabled, err)
	}
	if err := index.Reserve(ctx, caller, "id", "deps", "v1"); !errors.Is(err, cachevolumes.ErrConflict) {
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

func TestActionsIndexGivesUpOnAPendingJobWhenTheRequestEnds(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooEarly)
	}))
	defer server.Close()
	tokenPath := filepath.Join(t.TempDir(), "token")
	os.WriteFile(tokenPath, []byte("agent-token"), 0o600)
	index := &actionsIndex{url: server.URL, node: "node", tokenPath: tokenPath, client: server.Client()}

	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()
	if _, err := index.Lookup(ctx, cachevolumes.ActionsCaller{}, "deps", nil, "v1"); !errors.Is(err, cachevolumes.ErrExecutionPending) {
		t.Fatalf("lookup %v", err)
	}
}
