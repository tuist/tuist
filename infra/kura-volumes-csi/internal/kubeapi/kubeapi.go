// Package kubeapi is the minimal in-cluster Kubernetes API client the node
// plugin uses with its own ServiceAccount.
package kubeapi

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

const serviceAccountDir = "/var/run/secrets/kubernetes.io/serviceaccount"

type Client struct {
	baseURL   string
	http      *http.Client
	tokenPath string
}

func NewInCluster() (*Client, error) {
	host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" || port == "" {
		return nil, fmt.Errorf("KUBERNETES_SERVICE_HOST and KUBERNETES_SERVICE_PORT are not set")
	}
	ca, err := os.ReadFile(serviceAccountDir + "/ca.crt")
	if err != nil {
		return nil, fmt.Errorf("read cluster CA: %w", err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return nil, fmt.Errorf("cluster CA has no certificates")
	}
	return &Client{
		baseURL: "https://" + net.JoinHostPort(host, port),
		http: &http.Client{
			Timeout:   10 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}},
		},
		tokenPath: serviceAccountDir + "/token",
	}, nil
}

// New targets baseURL with the token at tokenPath; tests use it.
func New(baseURL, tokenPath string, httpClient *http.Client) *Client {
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), http: httpClient, tokenPath: tokenPath}
}

// Do sends body to path and returns the response body of a 2xx response.
func (c *Client) Do(ctx context.Context, method, path, contentType string, body []byte) ([]byte, error) {
	// The projected token rotates, so it is read per request.
	token, err := os.ReadFile(c.tokenPath)
	if err != nil {
		return nil, fmt.Errorf("read service account token: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Accept", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode/100 != 2 {
		return nil, &StatusError{Code: resp.StatusCode, Message: strings.TrimSpace(string(payload[:min(len(payload), 512)]))}
	}
	return payload, nil
}

type StatusError struct {
	Code    int
	Message string
}

func (e *StatusError) Error() string {
	return fmt.Sprintf("%d %s: %s", e.Code, http.StatusText(e.Code), e.Message)
}
