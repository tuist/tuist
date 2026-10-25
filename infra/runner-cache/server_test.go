package cachevolumes

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// rollingServer answers each attempt with the next behavior: "close" drops the
// connection without a response, like a server pod shutting down, and a status
// code answers with it.
type rollingServer struct {
	*httptest.Server
	mu     sync.Mutex
	bodies []string
}

func newRollingServer(t *testing.T, behaviors ...string) *rollingServer {
	t.Helper()
	s := &rollingServer{}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		s.mu.Lock()
		s.bodies = append(s.bodies, string(body))
		behavior := behaviors[min(len(s.bodies), len(behaviors))-1]
		s.mu.Unlock()
		switch behavior {
		case "close":
			conn, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error(err)
				return
			}
			conn.Close()
		case "200":
			io.WriteString(w, `{"generation":7}`)
		default:
			status, _ := strconv.Atoi(behavior)
			w.WriteHeader(status)
		}
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *rollingServer) attempts() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.bodies...)
}

func post(t *testing.T, ctx context.Context, url string) *http.Request {
	t.Helper()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url+"/api/internal/runners/cache-volumes/authorize", bytes.NewReader([]byte(`{"pod_uid":"u"}`)))
	if err != nil {
		t.Fatal(err)
	}
	return req
}

func TestServerRequestSurvivesAConnectionTheServerClosed(t *testing.T) {
	s := newRollingServer(t, "close", "200")

	response, err := DoServer(s.Client(), post(t, context.Background(), s.URL), nil)

	if err != nil {
		t.Fatal("a closed connection failed the request:", err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode != 200 || string(body) != `{"generation":7}` {
		t.Fatal(response.StatusCode, string(body))
	}
	if attempts := s.attempts(); len(attempts) != 2 || attempts[1] != `{"pod_uid":"u"}` {
		t.Fatalf("attempts %q; the retry did not resend the body", attempts)
	}
}

func TestServerRequestRetriesGatewayStatuses(t *testing.T) {
	s := newRollingServer(t, "502", "503", "504", "200")

	response, err := DoServer(s.Client(), post(t, context.Background(), s.URL), nil)

	if err != nil || response.StatusCode != 200 {
		t.Fatal(response, err)
	}
	response.Body.Close()
	if len(s.attempts()) != 4 {
		t.Fatal(s.attempts())
	}
}

func TestServerRequestReturnsTheServersDecisions(t *testing.T) {
	for _, status := range []string{"403", "409", "425"} {
		t.Run(status, func(t *testing.T) {
			s := newRollingServer(t, status, "200")

			response, err := DoServer(s.Client(), post(t, context.Background(), s.URL), nil)

			if err != nil || response.StatusCode == 200 {
				t.Fatal("retried a decision the server made:", response, err)
			}
			response.Body.Close()
			if len(s.attempts()) != 1 {
				t.Fatal(s.attempts())
			}
		})
	}
}

func TestServerRequestGivesUpAfterItsAttempts(t *testing.T) {
	s := newRollingServer(t, "503")

	response, err := DoServer(s.Client(), post(t, context.Background(), s.URL), nil)

	if err != nil || response.StatusCode != 503 {
		t.Fatal(response, err)
	}
	response.Body.Close()
	if len(s.attempts()) != serverAttempts {
		t.Fatal(s.attempts())
	}
}

func TestServerRequestDoesNotRetryPastItsDeadline(t *testing.T) {
	s := newRollingServer(t, "close")
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	start := time.Now()

	_, err := DoServer(s.Client(), post(t, ctx, s.URL), nil)

	if err == nil {
		t.Fatal("a server that kept closing the connection succeeded")
	}
	if elapsed := time.Since(start); elapsed > 100*time.Millisecond {
		t.Fatal("outlived the request deadline:", elapsed)
	}
	if len(s.attempts()) >= serverAttempts {
		t.Fatal("retried although the next attempt could not fit:", s.attempts())
	}
}

func TestImageMetadataSurvivesAServerRollout(t *testing.T) {
	s := newRollingServer(t, "close", "200")
	transfer := &HTTPTransfer{URL: s.URL + "/image", Node: "node", Client: s.Client(), Token: func(context.Context) (string, error) { return "token", nil }}

	head, err := transfer.Head(Slot{Identity: identity(first)})

	if err != nil || head.BaseGeneration != 7 {
		t.Fatal(head, err)
	}
	if attempts := s.attempts(); len(attempts) != 2 || !strings.Contains(attempts[1], `"operation":"retain"`) {
		t.Fatalf("attempts %q", attempts)
	}
}
