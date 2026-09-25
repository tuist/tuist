package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// RunnerHostAudience is the audience of the token a host presents to list the
// masters to prefetch. Must match `Tuist.Kubernetes.Client.runner_host_audience/0`.
// It differs from the dispatch audience so no token a guest holds is accepted:
// the list carries download URLs for every account on the fleet.
const RunnerHostAudience = "tuist-runner-host"

const (
	runnerDispatchURLEnv = "TUIST_RUNNER_DISPATCH_URL"
	runnerDispatchPath   = "/api/internal/runners/dispatch"
	cacheMastersPath     = "/api/internal/runners/cache-masters"
	serviceAccountPrefix = "system:serviceaccount:"
	// hostTokenSeconds is the host token's lifetime, the TokenRequest minimum.
	hostTokenSeconds = 600
	// prefetchRequestTimeout bounds one listing, token mint included.
	prefetchRequestTimeout = 30 * time.Second
	// prefetchResponseMaxBytes bounds the list, a handful of entries each
	// carrying one presigned URL.
	prefetchResponseMaxBytes = 1 << 20
)

// errPrefetchUnavailable: the host has not run a runner Pod yet, so it does not
// know where the server is.
var errPrefetchUnavailable = errors.New("cache master prefetch endpoint unknown")

// PrefetchMaster is one HEAD the server wants this host to hold.
type PrefetchMaster struct {
	AccountID     int64  `json:"account_id"`
	Volume        string `json:"volume"`
	Generation    int    `json:"generation"`
	Digest        string `json:"digest"`
	ContentDigest string `json:"content_digest"`
	DownloadURL   string `json:"download_url"`
}

// PrefetchSource lists the masters the server wants this host to hold, most
// wanted first.
type PrefetchSource interface {
	CacheMasters(ctx context.Context) ([]PrefetchMaster, error)
}

// ServerPrefetch asks the Tuist server which masters this host's fleet needs.
//
// The host authenticates as itself: its kubeconfig identity is the per-machine
// `tart-kubelet-<machine>` ServiceAccount, for which it mints a short-lived
// token bound to RunnerHostAudience. The server reviews that token and derives
// the Node from the ServiceAccount's name, so a host can only ask about its own
// fleet. The list cannot travel through a guest the way a job's own HEAD does,
// since it carries download URLs for accounts other than the job's.
type ServerPrefetch struct {
	Client kubernetes.Interface
	HTTP   *http.Client

	// mu guards endpoint, which the reconcile loop writes. tokenMu guards the
	// identity and token, held across apiserver calls, so a slow apiserver never
	// blocks a reconcile.
	mu          sync.Mutex
	endpoint    string
	tokenMu     sync.Mutex
	namespace   string
	name        string
	token       string
	tokenExpiry time.Time
}

// ObservePod records the server's cache-masters endpoint from a runner Pod's
// dispatch URL. The runners-controller writes that URL into the Pod spec; the
// guest never sees the spec, so it cannot redirect the host.
func (s *ServerPrefetch) ObservePod(pod *corev1.Pod) {
	if s == nil || pod == nil {
		return
	}
	for _, container := range pod.Spec.Containers {
		for _, env := range container.Env {
			if env.Name != runnerDispatchURLEnv || !strings.HasSuffix(env.Value, runnerDispatchPath) {
				continue
			}
			endpoint := strings.TrimSuffix(env.Value, runnerDispatchPath) + cacheMastersPath
			s.mu.Lock()
			s.endpoint = endpoint
			s.mu.Unlock()
			return
		}
	}
}

// CacheMasters implements PrefetchSource.
func (s *ServerPrefetch) CacheMasters(ctx context.Context) ([]PrefetchMaster, error) {
	s.mu.Lock()
	endpoint := s.endpoint
	s.mu.Unlock()
	if endpoint == "" {
		return nil, errPrefetchUnavailable
	}
	ctx, cancel := context.WithTimeout(ctx, prefetchRequestTimeout)
	defer cancel()
	token, err := s.hostToken(ctx)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	client := s.HTTP
	if client == nil {
		client = prefetchHTTPClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("list cache masters: HTTP %d", resp.StatusCode)
	}
	var body struct {
		Masters []PrefetchMaster `json:"masters"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, prefetchResponseMaxBytes)).Decode(&body); err != nil {
		return nil, fmt.Errorf("decode cache masters: %w", err)
	}
	return body.Masters, nil
}

var prefetchHTTPClient = &http.Client{
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

// hostToken returns a RunnerHostAudience token for this host's own
// ServiceAccount, minting a new one shortly before the last expires.
func (s *ServerPrefetch) hostToken(ctx context.Context) (string, error) {
	if s.Client == nil {
		return "", errPrefetchUnavailable
	}
	s.tokenMu.Lock()
	defer s.tokenMu.Unlock()
	if s.token != "" && time.Until(s.tokenExpiry) > time.Minute {
		return s.token, nil
	}
	if s.name == "" {
		review, err := s.Client.AuthenticationV1().SelfSubjectReviews().Create(ctx, &authenticationv1.SelfSubjectReview{}, metav1.CreateOptions{})
		if err != nil {
			return "", fmt.Errorf("look up the host's identity: %w", err)
		}
		namespace, name, ok := serviceAccountFromUsername(review.Status.UserInfo.Username)
		if !ok {
			return "", fmt.Errorf("host identity %q is not a ServiceAccount", review.Status.UserInfo.Username)
		}
		s.namespace, s.name = namespace, name
	}
	seconds := int64(hostTokenSeconds)
	resp, err := s.Client.CoreV1().ServiceAccounts(s.namespace).CreateToken(ctx, s.name, &authenticationv1.TokenRequest{
		Spec: authenticationv1.TokenRequestSpec{
			Audiences:         []string{RunnerHostAudience},
			ExpirationSeconds: &seconds,
		},
	}, metav1.CreateOptions{})
	if err != nil {
		return "", fmt.Errorf("mint host token: %w", err)
	}
	s.token = resp.Status.Token
	s.tokenExpiry = resp.Status.ExpirationTimestamp.Time
	return s.token, nil
}

func serviceAccountFromUsername(username string) (namespace, name string, ok bool) {
	rest, found := strings.CutPrefix(username, serviceAccountPrefix)
	if !found {
		return "", "", false
	}
	namespace, name, found = strings.Cut(rest, ":")
	if !found || namespace == "" || name == "" {
		return "", "", false
	}
	return namespace, name, true
}
