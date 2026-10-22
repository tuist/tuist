package main

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestAuthorizationWaitsOnlyForVerifiedExecutionBinding(t *testing.T) {
	for _, tc := range []struct {
		name     string
		statuses []int
		timeout  time.Duration
		succeeds bool
	}{
		{"late binding", []int{425, 200}, 3 * time.Second, true},
		{"denied identity", []int{403}, time.Second, false},
		{"bounded wait", []int{425}, 20 * time.Millisecond, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body, _ := io.ReadAll(r.Body)
				if string(body) != `{"pod_uid":"u"}` || r.Header.Get("Authorization") != "Bearer agent-token" {
					t.Error("lost verified request")
				}
				index := calls
				calls++
				if index >= len(tc.statuses) {
					index = len(tc.statuses) - 1
				}
				w.WriteHeader(tc.statuses[index])
				if tc.statuses[index] == 200 {
					io.WriteString(w, `{"id":"authorized-use"}`)
				}
			}))
			defer upstream.Close()
			token := filepath.Join(t.TempDir(), "token")
			if err := os.WriteFile(token, []byte("agent-token"), 0600); err != nil {
				t.Fatal(err)
			}
			a := agent{tokenPath: token, authorizeURL: upstream.URL, http: upstream.Client()}
			ctx, cancel := context.WithTimeout(context.Background(), tc.timeout)
			defer cancel()
			identity, err := a.authorize(ctx, []byte(`{"pod_uid":"u"}`))
			if (err == nil) != tc.succeeds || (tc.succeeds && identity.ID != "authorized-use") {
				t.Fatalf("identity=%+v err=%v", identity, err)
			}
			if pending := errors.Is(err, cachevolumes.ErrExecutionPending); pending != (tc.name == "bounded wait") {
				t.Fatalf("execution pending=%v err=%v", pending, err)
			}
			if calls != len(tc.statuses) {
				t.Fatalf("got %d attempts", calls)
			}
		})
	}
}

// rollingUpstream drops the connection of its first request without a
// response, as a server pod does when a rollout replaces it, then answers.
func rollingUpstream(t *testing.T, response string) (*httptest.Server, *int) {
	t.Helper()
	calls := 0
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if body, _ := io.ReadAll(r.Body); len(body) == 0 {
			t.Error("lost the request body")
		}
		calls++
		if calls == 1 {
			conn, _, _ := w.(http.Hijacker).Hijack()
			conn.Close()
			return
		}
		io.WriteString(w, response)
	}))
	t.Cleanup(upstream.Close)
	return upstream, &calls
}

func TestServerRequestsSurviveAServerRollout(t *testing.T) {
	token := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(token, []byte("agent-token"), 0600); err != nil {
		t.Fatal(err)
	}

	t.Run("authorize", func(t *testing.T) {
		upstream, calls := rollingUpstream(t, `{"id":"authorized-use"}`)
		a := agent{tokenPath: token, authorizeURL: upstream.URL + "/authorize", http: upstream.Client()}
		ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
		defer cancel()

		identity, err := a.authorize(ctx, []byte(`{"pod_uid":"u"}`))

		if err != nil || identity.ID != "authorized-use" || *calls != 2 {
			t.Fatalf("identity=%+v err=%v calls=%d", identity, err, *calls)
		}
	})

	t.Run("report", func(t *testing.T) {
		upstream, calls := rollingUpstream(t, `{"action":"seal"}`)
		a := agent{tokenPath: token, node: "node", authorizeURL: upstream.URL + "/authorize", http: upstream.Client()}

		action, err := a.report(cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "00000000-0000-0000-0000-000000000001"}, State: "active"}, true)

		if err != nil || action != "seal" || *calls != 2 {
			t.Fatalf("action=%q err=%v calls=%d", action, err, *calls)
		}
	})
}
