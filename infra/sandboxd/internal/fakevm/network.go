package fakevm

import (
	"context"
	"fmt"
	"sync"
)

// Network records netns operations instead of running ip/iptables.
type Network struct {
	mu       sync.Mutex
	Calls    []string
	Existing []string
	// FailSetup makes the next Setup fail.
	FailSetup error
}

func (n *Network) Setup(ctx context.Context, ns string, slot int) error {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.Calls = append(n.Calls, fmt.Sprintf("setup %s %d", ns, slot))
	if n.FailSetup != nil {
		err := n.FailSetup
		n.FailSetup = nil
		return err
	}
	return nil
}

func (n *Network) Teardown(ctx context.Context, ns string, slot int) error {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.Calls = append(n.Calls, fmt.Sprintf("teardown %s %d", ns, slot))
	return nil
}

func (n *Network) Namespaces(ctx context.Context) ([]string, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	return append([]string(nil), n.Existing...), nil
}

func (n *Network) Snapshot() []string {
	n.mu.Lock()
	defer n.mu.Unlock()
	return append([]string(nil), n.Calls...)
}
