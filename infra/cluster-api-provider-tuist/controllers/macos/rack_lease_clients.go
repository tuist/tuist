package macos

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// BorrowerClients reaches the clusters this operator lends rack hosts to.
type BorrowerClients interface {
	// Borrower returns a client for env's cluster and the namespace its
	// RackHostLeases live in.
	Borrower(ctx context.Context, env string) (client.Client, string, error)
}

// SecretBorrowerClients builds each borrowing cluster's client from a Secret
// in this operator's namespace: `kubeconfig`, the borrowing chart's
// rack-lender identity, and `namespace`, where that env's operator watches
// RackHostLeases. One Secret per borrowing env is the only credential the two
// operators share; the identity can do nothing but read and write
// RackHostLeases there.
type SecretBorrowerClients struct {
	Reader    client.Reader
	Namespace string
	// Secrets maps a borrowing env to its Secret's name.
	Secrets map[string]string
	Scheme  *runtime.Scheme

	mu     sync.Mutex
	cached map[string]cachedBorrower
}

type cachedBorrower struct {
	resourceVersion string
	client          client.Client
	namespace       string
}

// borrowerRequestTimeout bounds every call to a borrowing cluster: one that is
// down must not hold a rack host's reconcile.
const borrowerRequestTimeout = 30 * time.Second

func (s *SecretBorrowerClients) Borrower(ctx context.Context, env string) (client.Client, string, error) {
	name, ok := s.Secrets[env]
	if !ok {
		envs := make([]string, 0, len(s.Secrets))
		for e := range s.Secrets {
			envs = append(envs, e)
		}
		slices.Sort(envs)
		return nil, "", fmt.Errorf("this operator lends to %q only (--rack-lease-borrower), not %q", strings.Join(envs, ", "), env)
	}
	secret := &corev1.Secret{}
	if err := s.Reader.Get(ctx, types.NamespacedName{Namespace: s.Namespace, Name: name}, secret); err != nil {
		return nil, "", fmt.Errorf("read %s's credential %s/%s: %w", env, s.Namespace, name, err)
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if cached, ok := s.cached[env]; ok && cached.resourceVersion == secret.ResourceVersion {
		return cached.client, cached.namespace, nil
	}
	namespace := strings.TrimSpace(string(secret.Data["namespace"]))
	if namespace == "" {
		return nil, "", fmt.Errorf("%s's credential %s/%s has no `namespace`", env, s.Namespace, name)
	}
	cfg, err := clientcmd.RESTConfigFromKubeConfig(secret.Data["kubeconfig"])
	if err != nil {
		return nil, "", fmt.Errorf("%s's credential %s/%s: %w", env, s.Namespace, name, err)
	}
	cfg.Timeout = borrowerRequestTimeout
	c, err := client.New(cfg, client.Options{Scheme: s.Scheme})
	if err != nil {
		return nil, "", fmt.Errorf("client for %s: %w", env, err)
	}
	if s.cached == nil {
		s.cached = map[string]cachedBorrower{}
	}
	s.cached[env] = cachedBorrower{resourceVersion: secret.ResourceVersion, client: c, namespace: namespace}
	return c, namespace, nil
}
