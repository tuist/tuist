package tailnet

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type fakeAPI struct {
	tokens   atomic.Int32
	requests []string
	devices  []Device
	renamed  map[string]string
	deleted  []string
}

func (f *fakeAPI) server(t *testing.T) *httptest.Server {
	t.Helper()
	f.renamed = map[string]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/v2/oauth/token" {
			if err := r.ParseForm(); err != nil {
				t.Fatalf("parse form: %v", err)
			}
			if r.Form.Get("client_id") != "id" || r.Form.Get("client_secret") != "secret" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			f.tokens.Add(1)
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "tok", "expires_in": 3600})
			return
		}
		if r.Header.Get("Authorization") != "Bearer tok" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		f.requests = append(f.requests, r.Method+" "+r.URL.RequestURI())
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/api/v2/tailnet/-/devices":
			_ = json.NewEncoder(w).Encode(map[string]any{"devices": f.devices})
		case r.Method == http.MethodDelete && strings.HasPrefix(r.URL.Path, "/api/v2/device/"):
			f.deleted = append(f.deleted, strings.TrimPrefix(r.URL.Path, "/api/v2/device/"))
		case r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, "/name"):
			body, _ := io.ReadAll(r.Body)
			var req map[string]string
			_ = json.Unmarshal(body, &req)
			id := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/api/v2/device/"), "/name")
			f.renamed[id] = req["name"]
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestClientListsDevicesAndReusesItsToken(t *testing.T) {
	api := &fakeAPI{devices: []Device{{
		NodeID:    "n1",
		Name:      "ber1-edge.example.ts.net",
		Hostname:  "ber1-edge",
		Addresses: []string{"fd7a:115c:a1e0::1", "100.64.0.9"},
		Tags:      []string{"tag:tuist-rack-edge"},
		Created:   "2026-09-23T10:00:00Z",
		LastSeen:  "2026-09-23T10:05:00.1Z",
	}}}
	srv := api.server(t)
	c := &Client{ClientID: "id", ClientSecret: "secret", BaseURL: srv.URL}

	for range 2 {
		devices, err := c.Devices(context.Background())
		if err != nil {
			t.Fatalf("Devices: %v", err)
		}
		if len(devices) != 1 {
			t.Fatalf("got %d devices, want 1", len(devices))
		}
		d := devices[0]
		if d.IPv4() != "100.64.0.9" || d.ShortName() != "ber1-edge" {
			t.Fatalf("got IPv4 %q short name %q", d.IPv4(), d.ShortName())
		}
		if !d.CreatedAt().Equal(time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)) {
			t.Fatalf("created %v", d.CreatedAt())
		}
		if d.LastSeenAt().IsZero() {
			t.Fatal("fractional lastSeen did not parse")
		}
	}
	if got := api.tokens.Load(); got != 1 {
		t.Fatalf("exchanged the client for a token %d times, want 1", got)
	}
	if api.requests[0] != "GET /api/v2/tailnet/-/devices?fields=all" {
		t.Fatalf("request %q", api.requests[0])
	}
}

func TestClientDeletesAndRenames(t *testing.T) {
	api := &fakeAPI{}
	srv := api.server(t)
	c := &Client{ClientID: "id", ClientSecret: "secret", BaseURL: srv.URL}

	if err := c.DeleteDevice(context.Background(), "old"); err != nil {
		t.Fatalf("DeleteDevice: %v", err)
	}
	if err := c.RenameDevice(context.Background(), "new", "ber1-edge"); err != nil {
		t.Fatalf("RenameDevice: %v", err)
	}
	if len(api.deleted) != 1 || api.deleted[0] != "old" {
		t.Fatalf("deleted %v", api.deleted)
	}
	if api.renamed["new"] != "ber1-edge" {
		t.Fatalf("renamed %v", api.renamed)
	}
}

func TestClientFailsWithoutCredentials(t *testing.T) {
	c := &Client{BaseURL: "http://127.0.0.1:1"}
	if _, err := c.Devices(context.Background()); err == nil || !strings.Contains(err.Error(), "no Tailscale OAuth client") {
		t.Fatalf("got %v", err)
	}
}

func TestClientReportsRejectedCredentials(t *testing.T) {
	api := &fakeAPI{}
	srv := api.server(t)
	c := &Client{ClientID: "id", ClientSecret: "wrong", BaseURL: srv.URL}
	if _, err := c.Devices(context.Background()); err == nil || !strings.Contains(err.Error(), "HTTP 401") {
		t.Fatalf("got %v", err)
	}
}

func TestDeviceHasTags(t *testing.T) {
	d := Device{Tags: []string{"tag:a", "tag:b"}}
	if !d.HasTags([]string{"tag:a"}) || !d.HasTags(nil) {
		t.Fatal("subset not matched")
	}
	if d.HasTags([]string{"tag:a", "tag:c"}) {
		t.Fatal("missing tag matched")
	}
}
