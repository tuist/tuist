package controllers

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"time"

	corev1 "k8s.io/api/core/v1"
)

// NodeHealthChecker tests the data-plane path independently from the
// Kubernetes NodeReady condition.
type NodeHealthChecker interface {
	Healthy(ctx context.Context, node *corev1.Node) (bool, error)
}

// DirectNodeHealthChecker connects directly to a host-network listener on the
// node. Production points this at Cilium's Prometheus listener, which proves
// both node reachability and that the Cilium agent process is accepting
// connections without coupling failover to kubelet heartbeats.
type DirectNodeHealthChecker struct {
	Port    int
	Timeout time.Duration
}

func (c DirectNodeHealthChecker) Healthy(ctx context.Context, node *corev1.Node) (bool, error) {
	addresses := nodeAddresses(node)
	if len(addresses) == 0 {
		return false, fmt.Errorf("node %q has no internal or external IP address", node.Name)
	}

	timeout := c.Timeout
	if timeout <= 0 {
		timeout = 2 * time.Second
	}
	port := c.Port
	if port == 0 {
		port = 9962
	}
	probeCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	results := make(chan error, len(addresses))
	for _, address := range addresses {
		go func(address string) {
			conn, err := (&net.Dialer{}).DialContext(
				probeCtx,
				"tcp",
				net.JoinHostPort(address, strconv.Itoa(port)),
			)
			if err == nil {
				_ = conn.Close()
			}
			results <- err
		}(address)
	}

	var lastErr error
	for range addresses {
		select {
		case err := <-results:
			if err == nil {
				return true, nil
			}
			lastErr = err
		case <-probeCtx.Done():
			return false, fmt.Errorf(
				"checking node %q on port %d: %w",
				node.Name,
				port,
				probeCtx.Err(),
			)
		}
	}
	return false, fmt.Errorf("checking node %q on port %d: %w", node.Name, port, lastErr)
}

func nodeAddresses(node *corev1.Node) []string {
	addresses := make([]string, 0, 2)
	for _, addressType := range []corev1.NodeAddressType{corev1.NodeInternalIP, corev1.NodeExternalIP} {
		for _, address := range node.Status.Addresses {
			if address.Type == addressType && address.Address != "" {
				addresses = append(addresses, address.Address)
			}
		}
	}
	return addresses
}
