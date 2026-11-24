package cachevolumes

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"path"
	"syscall"
	"time"
)

// Every agent request to the server is idempotent: an allocation returns the
// pod's existing use, a report restates a use's state, and an image request
// reads a HEAD, signs another URL or returns the generation the use already
// published. A rolling server deploy closes kept-alive connections and its
// ingress briefly answers 502-504, so these requests are sent again.
const (
	serverAttempts   = 4
	serverRetryDelay = 250 * time.Millisecond
	serverRetryMax   = 2 * time.Second
)

// DoServer sends an idempotent agent request to the server, again on a connection
// failure or a gateway status, with jittered backoff inside the request's
// context. A retry that would outlive the context's deadline is not attempted.
// The request's body must be replayable (GetBody), as http.NewRequest sets it
// for in-memory bodies. Logs name the endpoint and a reason, never the URL.
//
// The response body is read inside the attempt, so a connection that drops
// while the body arrives is retried like one that drops before the headers.
// Otherwise the caller's decode fails on a request the server answered:
// on 2026-11-19 a canary rack host lost its connections right after the
// server answered an authorize with 200, and the job ran cold.
func DoServer(client *http.Client, req *http.Request, logger *slog.Logger) (*http.Response, error) {
	if logger == nil {
		logger = slog.Default()
	}
	ctx := req.Context()
	endpoint := path.Base(req.URL.Path)
	for attempt := 1; ; attempt++ {
		attemptReq, err := replay(req)
		if err != nil {
			return nil, err
		}
		response, err := client.Do(attemptReq)
		if err == nil {
			if err = bufferBody(response); err != nil {
				response = nil
			}
		}
		reason := retryReason(ctx, response, err)
		if reason == "" {
			if attempt > 1 && err == nil {
				logger.Info("cache server request recovered", "endpoint", endpoint, "attempts", attempt, "status", response.StatusCode)
			}
			return response, err
		}
		delay := retryDelay(attempt)
		if attempt >= serverAttempts || !fits(ctx, delay) {
			logger.Warn("cache server request failed", "endpoint", endpoint, "attempts", attempt, "reason", reason)
			return response, err
		}
		if response != nil {
			_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
			response.Body.Close()
		}
		logger.Info("cache server request retried", "endpoint", endpoint, "attempt", attempt, "reason", reason, "delay_ms", delay.Milliseconds())
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(delay):
		}
	}
}

// serverBodyLimit is the largest response body an agent reads (an image
// request's 1 MiB); a longer body keeps its unread rest on the connection.
const serverBodyLimit = 1 << 20

// bufferBody reads the response's body into memory and closes the connection's
// body unless it is longer than serverBodyLimit. On a read error it closes it.
func bufferBody(response *http.Response) error {
	body, err := io.ReadAll(io.LimitReader(response.Body, serverBodyLimit))
	if err != nil {
		response.Body.Close()
		return err
	}
	if len(body) < serverBodyLimit {
		response.Body.Close()
		response.Body = io.NopCloser(bytes.NewReader(body))
		return nil
	}
	response.Body = struct {
		io.Reader
		io.Closer
	}{io.MultiReader(bytes.NewReader(body), response.Body), response.Body}
	return nil
}

func replay(req *http.Request) (*http.Request, error) {
	attempt := req.Clone(req.Context())
	if req.Body == nil || req.Body == http.NoBody {
		return attempt, nil
	}
	if req.GetBody == nil {
		return nil, errors.New("server request body cannot be replayed")
	}
	body, err := req.GetBody()
	if err != nil {
		return nil, err
	}
	attempt.Body = body
	return attempt, nil
}

// retryReason names why an attempt is worth repeating, or "" when it is not.
func retryReason(ctx context.Context, response *http.Response, err error) string {
	if ctx.Err() != nil {
		return ""
	}
	if err != nil {
		switch {
		case errors.Is(err, io.EOF), errors.Is(err, io.ErrUnexpectedEOF):
			return "eof"
		case errors.Is(err, syscall.ECONNRESET):
			return "connection_reset"
		case errors.Is(err, syscall.ECONNREFUSED):
			return "connection_refused"
		default:
			return "transport_error"
		}
	}
	switch response.StatusCode {
	case http.StatusBadGateway:
		return "status_502"
	case http.StatusServiceUnavailable:
		return "status_503"
	case http.StatusGatewayTimeout:
		return "status_504"
	}
	return ""
}

// retryDelay doubles from serverRetryDelay up to serverRetryMax, jittered into
// its upper half so agents that lost the same server pod do not retry together.
func retryDelay(attempt int) time.Duration {
	delay := min(serverRetryDelay<<(attempt-1), serverRetryMax)
	return delay/2 + rand.N(delay/2+1)
}

func fits(ctx context.Context, delay time.Duration) bool {
	deadline, ok := ctx.Deadline()
	return !ok || time.Until(deadline) > delay
}

// ServerIdleTimeout is below the server's 15 s keep-alive timeout, so an agent
// drops an idle connection before the server closes it.
const ServerIdleTimeout = 10 * time.Second

// NewServerClient returns the client agents use for server requests: it never
// follows redirects and closes connections idle for ServerIdleTimeout.
func NewServerClient(timeout time.Duration) *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.IdleConnTimeout = ServerIdleTimeout
	return &http.Client{Timeout: timeout, Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
}
