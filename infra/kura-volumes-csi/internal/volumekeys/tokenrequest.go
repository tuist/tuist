package volumekeys

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/kubeapi"
)

// tokenLifetime is the TokenRequest minimum; the admission policy rejects
// longer-lived tokens.
const tokenLifetime = 600

// PodTokenSource mints tokens for the plugin's own ServiceAccount, bound to its
// own pod so the key service can read the node from the token.
type PodTokenSource struct {
	API            *kubeapi.Client
	Namespace      string
	ServiceAccount string
	PodName        string
	PodUID         string
}

func (s PodTokenSource) Validate() error {
	if s.Namespace == "" || s.ServiceAccount == "" || s.PodName == "" || s.PodUID == "" {
		return errors.New("namespace, service account, pod name and pod UID are required to mint key-service tokens")
	}
	return nil
}

func (s PodTokenSource) Token(ctx context.Context, audience string) (string, error) {
	if err := s.Validate(); err != nil {
		return "", err
	}
	body, err := json.Marshal(map[string]any{
		"apiVersion": "authentication.k8s.io/v1",
		"kind":       "TokenRequest",
		"spec": map[string]any{
			"audiences":         []string{audience},
			"expirationSeconds": tokenLifetime,
			"boundObjectRef":    map[string]string{"apiVersion": "v1", "kind": "Pod", "name": s.PodName, "uid": s.PodUID},
		},
	})
	if err != nil {
		return "", err
	}
	path := fmt.Sprintf("/api/v1/namespaces/%s/serviceaccounts/%s/token", s.Namespace, s.ServiceAccount)
	payload, err := s.API.Do(ctx, http.MethodPost, path, "application/json", body)
	if err != nil {
		var statusErr *kubeapi.StatusError
		if errors.As(err, &statusErr) && statusErr.Code < 500 && statusErr.Code != http.StatusTooManyRequests {
			return "", fmt.Errorf("token request: %w", err)
		}
		return "", Retryable(fmt.Errorf("token request: %w", err))
	}
	var response struct {
		Status struct {
			Token string `json:"token"`
		} `json:"status"`
	}
	if err := json.Unmarshal(payload, &response); err != nil || response.Status.Token == "" {
		return "", Retryable(errors.New("token request returned no token"))
	}
	return response.Status.Token, nil
}
