// Package nodecapacity advertises the room a node's volume group has for Kura
// volumes as the tuist.dev/kura-disk extended resource, so the scheduler and
// the server's capacity admission place Kura pods against it the way they
// place them against ephemeral-storage on nodes that keep volumes on /data.
package nodecapacity

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// Resource is the extended resource Kura pods on a volume group request.
const Resource = "tuist.dev/kura-disk"

const serviceAccountDir = "/var/run/secrets/kubernetes.io/serviceaccount"

// Measure returns the bytes the node's volume group holds for Kura volumes,
// and false when the node has no volume group.
type Measure func(ctx context.Context) (int64, bool, error)

// Patcher applies a JSON merge patch to the node's status.
type Patcher interface {
	PatchNodeStatus(ctx context.Context, node string, patch []byte) error
}

type Advertiser struct {
	Node     string
	Measure  Measure
	Patcher  Patcher
	Interval time.Duration
	Logger   *slog.Logger
}

// Run advertises once and then on every interval, because a kubelet that
// re-registers its node resets status and drops the resource.
func (a *Advertiser) Run(ctx context.Context) {
	ticker := time.NewTicker(a.Interval)
	defer ticker.Stop()
	for {
		if err := a.Once(ctx); err != nil && ctx.Err() == nil {
			a.Logger.Warn("advertising Kura disk capacity failed", "resource", Resource, "error", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// Once sets the resource to the measured capacity, or removes it from a node
// without a volume group so nothing is scheduled there against stale room.
func (a *Advertiser) Once(ctx context.Context) error {
	capacity, ok, err := a.Measure(ctx)
	if err != nil {
		return err
	}
	var value any
	if ok {
		value = strconv.FormatInt(capacity, 10)
	}
	patch, err := json.Marshal(map[string]any{"status": map[string]any{"capacity": map[string]any{Resource: value}}})
	if err != nil {
		return err
	}
	return a.Patcher.PatchNodeStatus(ctx, a.Node, patch)
}

// InClusterPatcher talks to the API server with the pod's ServiceAccount.
type InClusterPatcher struct {
	baseURL   string
	client    *http.Client
	tokenPath string
}

func NewInClusterPatcher() (*InClusterPatcher, error) {
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
	return &InClusterPatcher{
		baseURL: "https://" + net.JoinHostPort(host, port),
		client: &http.Client{
			Timeout:   10 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}},
		},
		tokenPath: serviceAccountDir + "/token",
	}, nil
}

func (p *InClusterPatcher) PatchNodeStatus(ctx context.Context, node string, patch []byte) error {
	// The projected token rotates, so it is read per request.
	token, err := os.ReadFile(p.tokenPath)
	if err != nil {
		return fmt.Errorf("read service account token: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, p.baseURL+"/api/v1/nodes/"+node+"/status", bytes.NewReader(patch))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/merge-patch+json")
	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("patch node %s status: %s: %s", node, resp.Status, strings.TrimSpace(string(body)))
	}
	return nil
}
