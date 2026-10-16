package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
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
			if calls != len(tc.statuses) {
				t.Fatalf("got %d attempts", calls)
			}
		})
	}
}
