package orchard

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCreateVM_PostsCorrectShape(t *testing.T) {
	var seen struct {
		Method string
		Path   string
		Body   VM
		Auth   string
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen.Method = r.Method
		seen.Path = r.URL.Path
		seen.Auth = r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&seen.Body)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = io.Copy(w, strings.NewReader(`{"name":"vm-1","image":"img","status":"pending"}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "sa", "token")
	got, err := c.CreateVM(context.Background(), VM{Name: "vm-1", Image: "img", CPU: 4, Memory: 8192})
	if err != nil {
		t.Fatalf("CreateVM: %v", err)
	}
	if got.Name != "vm-1" {
		t.Fatalf("got name %q, want vm-1", got.Name)
	}
	if seen.Method != http.MethodPost || seen.Path != "/v1/vms" {
		t.Fatalf("got %s %s, want POST /v1/vms", seen.Method, seen.Path)
	}
	if seen.Body.Name != "vm-1" || seen.Body.Image != "img" {
		t.Fatalf("body roundtrip mismatch: %+v", seen.Body)
	}
	if seen.Auth == "" {
		t.Fatalf("expected basic auth header, got none")
	}
}

func TestDeleteVM_TreatsNotFoundAsSuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "sa", "token")
	if err := c.DeleteVM(context.Background(), "missing"); err != nil {
		t.Fatalf("DeleteVM should swallow 404, got %v", err)
	}
}

func TestGetVM_NotFoundSurfaces(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "sa", "token")
	_, err := c.GetVM(context.Background(), "missing")
	if err != ErrNotFound {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestListVMs_DecodesArray(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/vms" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.Copy(w, strings.NewReader(`[{"name":"a"},{"name":"b"}]`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "sa", "token")
	vms, err := c.ListVMs(context.Background())
	if err != nil {
		t.Fatalf("ListVMs: %v", err)
	}
	if len(vms) != 2 || vms[0].Name != "a" || vms[1].Name != "b" {
		t.Fatalf("unexpected list: %+v", vms)
	}
}

func TestListWorkers_SumCapacity(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/workers" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.Copy(w, strings.NewReader(`[{"name":"m1","cpu":8,"memory":16384,"status":"online"},{"name":"m2","cpu":8,"memory":16384,"status":"online"}]`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "sa", "token")
	workers, err := c.ListWorkers(context.Background())
	if err != nil {
		t.Fatalf("ListWorkers: %v", err)
	}
	if len(workers) != 2 {
		t.Fatalf("expected 2 workers, got %d", len(workers))
	}
	totalCPU := workers[0].CPU + workers[1].CPU
	if totalCPU != 16 {
		t.Fatalf("expected 16 total CPU, got %d", totalCPU)
	}
}
