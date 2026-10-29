package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"
)

// EndpointResolver maps pods to their host-side veth device via the local
// Cilium agent's endpoint API (unix socket). This is authoritative: Cilium is
// the component that created the interface, so there is no heuristic netlink
// walking and no pod-netns access.
type EndpointResolver struct {
	client *http.Client
}

func NewEndpointResolver(socketPath string) *EndpointResolver {
	return &EndpointResolver{
		client: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
					var dialer net.Dialer
					return dialer.DialContext(ctx, "unix", socketPath)
				},
			},
		},
	}
}

// Interfaces returns a "namespace/name" -> host interface name map for every
// local endpoint Cilium knows.
func (r *EndpointResolver) Interfaces(ctx context.Context) (map[string]string, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://localhost/v1/endpoint", nil)
	if err != nil {
		return nil, err
	}
	response, err := r.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("querying cilium endpoint api: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("cilium endpoint api: status %d", response.StatusCode)
	}

	var endpoints []struct {
		Status struct {
			ExternalIdentifiers struct {
				PodName string `json:"pod-name"`
			} `json:"external-identifiers"`
			Networking struct {
				InterfaceName string `json:"interface-name"`
			} `json:"networking"`
		} `json:"status"`
	}
	if err := json.NewDecoder(response.Body).Decode(&endpoints); err != nil {
		return nil, fmt.Errorf("decoding cilium endpoint api response: %w", err)
	}

	interfaces := make(map[string]string, len(endpoints))
	for _, endpoint := range endpoints {
		pod := endpoint.Status.ExternalIdentifiers.PodName
		device := endpoint.Status.Networking.InterfaceName
		if pod != "" && device != "" {
			interfaces[pod] = device
		}
	}
	return interfaces, nil
}
