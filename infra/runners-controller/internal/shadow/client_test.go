package shadow

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestClientRotatesTokenAndRejectsBadResponses(t *testing.T) {
	path := filepath.Join(t.TempDir(), "token")
	expected := "first"
	status := 200
	body := `{"version":1,"complete":true,"captured_at":"2026-09-22T12:00:00Z","demand":[],"accounts":[],"claims":[]}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.Header.Get("Authorization") != "Bearer "+expected {
			t.Errorf("wrong request method or token")
		}
		w.WriteHeader(status)
		fmt.Fprint(w, body)
	}))
	defer server.Close()
	c := NewClient(server.URL)
	c.TokenPath = path
	for _, token := range []string{"first", "rotated"} {
		expected = token
		if err := os.WriteFile(path, []byte(token+"\n"), 0600); err != nil {
			t.Fatal(err)
		}
		if s, err := c.Snapshot(context.Background()); err != nil || !s.Complete {
			t.Fatalf("%+v %v", s, err)
		}
	}
	status = 403
	if _, err := c.Snapshot(context.Background()); err == nil {
		t.Fatal("accepted denied request")
	}
	status = 200
	body = `{"complete":`
	if _, err := c.Snapshot(context.Background()); err == nil {
		t.Fatal("accepted malformed response")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := c.Snapshot(ctx); err == nil {
		t.Fatal("ignored cancellation")
	}
}
