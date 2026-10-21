package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func (a *agent) authorize(ctx context.Context, body []byte) (cachevolumes.Identity, error) {
	var identity cachevolumes.Identity
	err := a.allocate(ctx, a.authorizeURL, body, &identity)
	return identity, err
}

// allocate asks the server for a use and decodes it into result.
func (a *agent) allocate(ctx context.Context, url string, body []byte, result any) error {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	pending := false
	for {
		status, err := a.allocateOnce(ctx, url, body, result)
		if pending && ctx.Err() != nil && status != http.StatusOK {
			return cachevolumes.ErrExecutionPending
		}
		if err != nil || status == http.StatusOK {
			return err
		}
		// The volume is larger than this host's maximum. Retrying cannot help.
		if status == http.StatusInsufficientStorage {
			return cachevolumes.ErrCapacity
		}
		if status != http.StatusTooEarly {
			return fmt.Errorf("authorization rejected: %d", status)
		}
		// GitHub may deliver its verified execution binding after the action starts.
		// Retry only that explicit pending state, never denied provider identity.
		pending = true
		select {
		case <-ctx.Done():
			return cachevolumes.ErrExecutionPending
		case <-time.After(time.Second):
		}
	}
}

func (a *agent) allocateOnce(ctx context.Context, url string, body []byte, result any) (status int, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	token, err := os.ReadFile(a.tokenPath)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	response, err := a.http.Do(req)
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusOK {
		err = json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(result)
	}
	return response.StatusCode, err
}
