// Package hcloud wraps the Hetzner Cloud SDK to implement the reconciler's
// FloatingIPManager interface.
package hcloud

import (
	"context"
	"fmt"

	"github.com/hetznercloud/hcloud-go/v2/hcloud"
)

// Manager assigns a Hetzner Cloud Floating IP via the Cloud API.
type Manager struct {
	client *hcloud.Client
}

func New(token string) *Manager {
	return &Manager{client: hcloud.NewClient(hcloud.WithToken(token))}
}

func (m *Manager) CurrentServerID(ctx context.Context, floatingIPName string) (int64, error) {
	fip, err := m.lookup(ctx, floatingIPName)
	if err != nil {
		return 0, err
	}
	if fip.Server == nil {
		return 0, nil
	}
	return fip.Server.ID, nil
}

func (m *Manager) Assign(ctx context.Context, floatingIPName string, serverID int64) error {
	fip, err := m.lookup(ctx, floatingIPName)
	if err != nil {
		return err
	}
	action, _, err := m.client.FloatingIP.Assign(ctx, fip, &hcloud.Server{ID: serverID})
	if err != nil {
		return fmt.Errorf("assign action: %w", err)
	}
	if err := m.client.Action.WaitFor(ctx, action); err != nil {
		return fmt.Errorf("waiting for assign action %d: %w", action.ID, err)
	}
	return nil
}

func (m *Manager) lookup(ctx context.Context, name string) (*hcloud.FloatingIP, error) {
	fip, _, err := m.client.FloatingIP.GetByName(ctx, name)
	if err != nil {
		return nil, fmt.Errorf("looking up Floating IP %q: %w", name, err)
	}
	if fip == nil {
		return nil, fmt.Errorf("Floating IP %q not found in the project", name)
	}
	return fip, nil
}
