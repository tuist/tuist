package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"runtime"
	"time"
)

// executionTokenAudience is the audience the Tuist server accepts for a job's
// execution token, distinct from Tuist's own CI login.
const executionTokenAudience = "tuist-runner-cache"

// The server refuses larger tokens.
const maxExecutionToken = 16384

// errNoIDToken means the workflow did not grant the job `id-token: write`.
var errNoIDToken = errors.New("the job may not request an OIDC token")

// proveExecution hands the host a GitHub OIDC token minted for this job, so the
// Tuist server learns which job this runner runs without waiting for GitHub's
// webhook. It runs in the job-started hook, before the checkout and Docker
// attaches. It never fails the job: without a token the server waits for
// GitHub's report as before. An empty result means there was nothing to do.
func proveExecution() string {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	token, err := requestExecutionToken(ctx, &http.Client{Timeout: 5 * time.Second},
		os.Getenv("ACTIONS_ID_TOKEN_REQUEST_URL"), os.Getenv("ACTIONS_ID_TOKEN_REQUEST_TOKEN"))
	if errors.Is(err, errNoIDToken) {
		return ""
	}
	if err != nil {
		return "unavailable (token)"
	}
	if runtime.GOOS == "darwin" {
		err = presentExecutionMac(ctx, macShare, token)
	} else {
		err = presentExecutionLinux(ctx, token)
	}
	if err != nil {
		return "unavailable (host)"
	}
	return "presented"
}

// requestExecutionToken asks GitHub's job token service for an OIDC token for
// the Tuist server's audience.
func requestExecutionToken(ctx context.Context, client *http.Client, endpoint, bearer string) (string, error) {
	if endpoint == "" || bearer == "" {
		return "", errNoIDToken
	}
	target, err := url.Parse(endpoint)
	if err != nil || target.Scheme != "https" {
		return "", errors.New("invalid token endpoint")
	}
	query := target.Query()
	query.Set("audience", executionTokenAudience)
	target.RawQuery = query.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target.String(), nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "bearer "+bearer)
	req.Header.Set("Accept", "application/json")
	response, err := client.Do(req)
	if err != nil {
		return "", errors.New("token request failed")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", errors.New("token request rejected")
	}
	var result struct {
		Value string `json:"value"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 2*maxExecutionToken)).Decode(&result); err != nil {
		return "", errors.New("invalid token response")
	}
	if result.Value == "" || len(result.Value) > maxExecutionToken {
		return "", errors.New("invalid token")
	}
	return result.Value, nil
}

func presentExecutionLinux(ctx context.Context, token string) error {
	endpoint := os.Getenv("TUIST_CACHE_VOLUME_URL")
	if endpoint == "" {
		return errors.New("cache volumes disabled")
	}
	client, err := newCacheHTTPClient(10 * time.Second)
	if err != nil {
		return err
	}
	defer client.CloseIdleConnections()
	body, _ := json.Marshal(map[string]any{
		"pod_name": os.Getenv("TUIST_CACHE_VOLUME_POD"), "pod_uid": os.Getenv("TUIST_CACHE_VOLUME_UID"), "token": token,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/execution", bytes.NewReader(body))
	if err != nil {
		return cacheRequestError{err}
	}
	req.Header.Set("Content-Type", "application/json")
	var result struct{}
	return requestJSON(client, req, &result)
}

func presentExecutionMac(ctx context.Context, share, token string) error {
	response, err := exchangeMac(ctx, share, map[string]any{"execution_token": token})
	if err != nil {
		return err
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	return nil
}
