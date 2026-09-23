package linux

import (
	"context"
	"fmt"
	"sync"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

// SecretTailnetAPI is a TailnetAPI whose OAuth client comes from a Secret with
// `client-id` and `client-secret`, read on each call so an ESO sync or a
// rotation takes effect without a restart.
type SecretTailnetAPI struct {
	Reader    client.Reader
	Namespace string
	Name      string

	mu     sync.Mutex
	client *tailnet.Client
}

func (s *SecretTailnetAPI) current(ctx context.Context) (*tailnet.Client, error) {
	secret := &corev1.Secret{}
	if err := s.Reader.Get(ctx, types.NamespacedName{Namespace: s.Namespace, Name: s.Name}, secret); err != nil {
		return nil, fmt.Errorf("read Tailscale OAuth client Secret %s/%s: %w", s.Namespace, s.Name, err)
	}
	id, secretValue := string(secret.Data["client-id"]), string(secret.Data["client-secret"])
	if id == "" || secretValue == "" {
		return nil, fmt.Errorf("Secret %s/%s lacks client-id or client-secret", s.Namespace, s.Name)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.client == nil || s.client.ClientID != id || s.client.ClientSecret != secretValue {
		s.client = &tailnet.Client{ClientID: id, ClientSecret: secretValue}
	}
	return s.client, nil
}

func (s *SecretTailnetAPI) Devices(ctx context.Context) ([]tailnet.Device, error) {
	c, err := s.current(ctx)
	if err != nil {
		return nil, err
	}
	return c.Devices(ctx)
}

func (s *SecretTailnetAPI) DeleteDevice(ctx context.Context, nodeID string) error {
	c, err := s.current(ctx)
	if err != nil {
		return err
	}
	return c.DeleteDevice(ctx, nodeID)
}

func (s *SecretTailnetAPI) RenameDevice(ctx context.Context, nodeID, name string) error {
	c, err := s.current(ctx)
	if err != nil {
		return err
	}
	return c.RenameDevice(ctx, nodeID, name)
}
