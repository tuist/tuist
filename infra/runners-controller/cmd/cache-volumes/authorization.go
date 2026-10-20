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
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	pending := false
	for {
		identity, status, err := a.authorizeOnce(ctx, body)
		if pending && ctx.Err() != nil && status != http.StatusOK {
			return identity, cachevolumes.ErrExecutionPending
		}
		if err != nil || status == http.StatusOK {
			return identity, err
		}
		// The volume is larger than this host's maximum. Retrying cannot help.
		if status == http.StatusInsufficientStorage {
			return identity, cachevolumes.ErrCapacity
		}
		if status != http.StatusTooEarly {
			return identity, fmt.Errorf("authorization rejected: %d", status)
		}
		// GitHub may deliver its verified execution binding after the action starts.
		// Retry only that explicit pending state, never denied provider identity.
		pending = true
		select {
		case <-ctx.Done():
			return identity, cachevolumes.ErrExecutionPending
		case <-time.After(time.Second):
		}
	}
}

func (a *agent) authorizeOnce(ctx context.Context, body []byte) (identity cachevolumes.Identity, status int, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.authorizeURL, bytes.NewReader(body))
	if err != nil {
		return identity, 0, err
	}
	token, err := os.ReadFile(a.tokenPath)
	if err != nil {
		return identity, 0, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	response, err := a.http.Do(req)
	if err != nil {
		return identity, 0, err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusOK {
		err = json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&identity)
	}
	return identity, response.StatusCode, err
}
