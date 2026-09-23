// Package omada is a client for the TP-Link Omada SDN controller's Open API,
// limited to what the rack switch controller reads and writes.
//
// Every call outside unmeasured.go was exercised against controller 6.3.0.45
// and a real switch, and mirrors infra/rack-switch-fleet/omada.sh where that
// makes the same call. unmeasured.go holds calls whose shapes have not met
// hardware.
package omada

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

const pageSize = 100

// CredentialsFunc returns the Open API client's id and secret. It is called
// whenever a token is issued, so a rotated secret is picked up without a
// restart.
type CredentialsFunc func() (clientID, clientSecret string, err error)

// Client talks to one Omada controller. Safe for concurrent use.
type Client struct {
	baseURL     string
	credentials CredentialsFunc
	http        *http.Client
	now         func() time.Time

	mu        sync.Mutex
	omadacID  string
	token     string
	expiresAt time.Time
}

// New returns a client for the controller at baseURL, for example
// https://omada-omada-controller.omada.svc:8043.
func New(baseURL string, credentials CredentialsFunc) *Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	// The controller serves its own self-signed certificate. The connection
	// stays inside the cluster, from this controller to the Omada Service;
	// `apply` from an operator's machine reaches it over the tailnet.
	transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true} //nolint:gosec
	return &Client{
		baseURL:     strings.TrimRight(baseURL, "/"),
		credentials: credentials,
		http:        &http.Client{Timeout: 30 * time.Second, Transport: transport},
		now:         time.Now,
	}
}

// Error is a call the controller answered with a non-zero errorCode, or an
// HTTP status other than 200.
type Error struct {
	Method     string
	Path       string
	HTTPStatus int
	Code       int
	Message    string
}

func (e *Error) Error() string {
	if e.Code != 0 {
		return fmt.Sprintf("%s %s: errorCode %d: %s", e.Method, e.Path, e.Code, e.Message)
	}
	return fmt.Sprintf("%s %s: HTTP %d", e.Method, e.Path, e.HTTPStatus)
}

// Error codes the controller answers for an access token it no longer
// accepts: -44112 expired, -44113 invalid.
var tokenErrorCodes = map[int]bool{-44112: true, -44113: true}

func (e *Error) tokenRejected() bool {
	return e.HTTPStatus == http.StatusUnauthorized || tokenErrorCodes[e.Code]
}

type envelope struct {
	ErrorCode int             `json:"errorCode"`
	Msg       string          `json:"msg"`
	Result    json.RawMessage `json:"result"`
}

// ControllerID is the controller's omadacId, which every Open API path
// carries.
func (c *Client) ControllerID(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.controllerIDLocked(ctx)
}

func (c *Client) controllerIDLocked(ctx context.Context) (string, error) {
	if c.omadacID != "" {
		return c.omadacID, nil
	}
	var info struct {
		OmadacID string `json:"omadacId"`
	}
	if err := c.send(ctx, http.MethodGet, "/api/info", "", nil, &info); err != nil {
		return "", err
	}
	if info.OmadacID == "" {
		return "", fmt.Errorf("GET /api/info: no omadacId in the answer")
	}
	c.omadacID = info.OmadacID
	return c.omadacID, nil
}

func (c *Client) session(ctx context.Context) (omadacID, token string, err error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	omadacID, err = c.controllerIDLocked(ctx)
	if err != nil {
		return "", "", err
	}
	if c.token != "" && c.now().Before(c.expiresAt) {
		return omadacID, c.token, nil
	}
	clientID, clientSecret, err := c.credentials()
	if err != nil {
		return "", "", fmt.Errorf("open api credentials: %w", err)
	}
	var issued struct {
		AccessToken string `json:"accessToken"`
		ExpiresIn   int    `json:"expiresIn"`
	}
	body := map[string]string{"omadacId": omadacID, "client_id": clientID, "client_secret": clientSecret}
	if err := c.send(ctx, http.MethodPost, "/openapi/authorize/token?grant_type=client_credentials", "", body, &issued); err != nil {
		return "", "", err
	}
	if issued.AccessToken == "" {
		return "", "", fmt.Errorf("the controller issued no access token")
	}
	lifetime := time.Duration(issued.ExpiresIn) * time.Second
	if lifetime > 2*time.Minute {
		lifetime -= time.Minute
	}
	c.token = issued.AccessToken
	c.expiresAt = c.now().Add(lifetime)
	return omadacID, c.token, nil
}

func (c *Client) invalidate(token string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token == token {
		c.token = ""
	}
}

// call sends a request to path under /openapi/v1/{omadacId}, issuing a token
// first when there is none, and once more when the controller rejects the one
// it has.
func (c *Client) call(ctx context.Context, method, path string, body, out any) error {
	for attempt := 0; ; attempt++ {
		omadacID, token, err := c.session(ctx)
		if err != nil {
			return err
		}
		err = c.send(ctx, method, "/openapi/v1/"+omadacID+path, token, body, out)
		var apiErr *Error
		if attempt == 0 && errors.As(err, &apiErr) && apiErr.tokenRejected() {
			c.invalidate(token)
			continue
		}
		return err
	}
}

func (c *Client) send(ctx context.Context, method, path, token string, body, out any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("%s %s: encode: %w", method, path, err)
		}
		reader = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "AccessToken="+token)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return fmt.Errorf("%s %s: read: %w", method, path, err)
	}
	var env envelope
	if jsonErr := json.Unmarshal(raw, &env); jsonErr != nil {
		if resp.StatusCode != http.StatusOK {
			return &Error{Method: method, Path: path, HTTPStatus: resp.StatusCode}
		}
		return fmt.Errorf("%s %s: decode: %w", method, path, jsonErr)
	}
	if env.ErrorCode != 0 {
		return &Error{Method: method, Path: path, HTTPStatus: resp.StatusCode, Code: env.ErrorCode, Message: env.Msg}
	}
	if resp.StatusCode != http.StatusOK {
		return &Error{Method: method, Path: path, HTTPStatus: resp.StatusCode}
	}
	if out == nil || len(env.Result) == 0 || string(env.Result) == "null" {
		return nil
	}
	if err := json.Unmarshal(env.Result, out); err != nil {
		return fmt.Errorf("%s %s: decode result: %w", method, path, err)
	}
	return nil
}

type page[T any] struct {
	TotalRows int `json:"totalRows"`
	Data      []T `json:"data"`
}

// list reads every page of a paged result.
func list[T any](ctx context.Context, c *Client, path string) ([]T, error) {
	var all []T
	for n := 1; ; n++ {
		var p page[T]
		if err := c.call(ctx, http.MethodGet, fmt.Sprintf("%s?page=%d&pageSize=%d", path, n, pageSize), nil, &p); err != nil {
			return nil, err
		}
		all = append(all, p.Data...)
		if len(p.Data) < pageSize || (p.TotalRows > 0 && len(all) >= p.TotalRows) {
			return all, nil
		}
	}
}

func sitePath(siteID, rest string) string {
	return "/sites/" + siteID + rest
}
