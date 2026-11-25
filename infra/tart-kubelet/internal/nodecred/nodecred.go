// Package nodecred keeps the host's API token fresh.
//
// The operator puts a TokenRequest token for the host's ServiceAccount in
// the kubeconfig it pushes, inline, and names TokenFile beside it as
// `tokenFile`. client-go re-reads that file every minute and prefers it to
// the inline token once it exists, so the host can replace its own token
// without restarting: Rotator mints a new token for its own account once a
// day, long before the current one expires, and writes it there. No token
// on the host outlives its expiry, and deleting the host's ServiceAccount
// revokes every one of them.
package nodecred

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	// CredentialLabel is set on the Node while the host runs from a token
	// it rotates, which tells the operator the host's long-lived token Secret
	// can go. Must match the operator's credentials.KubeletCredentialLabel.
	CredentialLabel = "tuist.dev/kubelet-credential"
	CredentialToken = "token-request"

	// DefaultLifetime is what a token the host mints for itself asks for.
	DefaultLifetime = 7 * 24 * time.Hour
	// maxAge is how old a token may get before it is replaced, so a host
	// can be cut off for most of a token's lifetime and still come back.
	maxAge = 24 * time.Hour

	serviceAccountPrefix = "system:serviceaccount:"
)

// Seed makes tokenFile hold the newest of the kubeconfig's inline token and
// the file's own. The operator pushes a fresh inline token with every
// kubeconfig, which must win over an older file a previous run wrote. A file
// token of another identity (issuer or subject), such as the lender
// cluster's on a rack host this cluster took over, never wins, however new:
// iat from two API servers says nothing about which token is current. It
// returns the file's path, or "" when the kubeconfig names none (a
// kubeconfig from an operator that predates rotation).
func Seed(kubeconfigPath string) (string, error) {
	cfg, err := clientcmd.LoadFromFile(kubeconfigPath)
	if err != nil {
		return "", err
	}
	ctx := cfg.Contexts[cfg.CurrentContext]
	if ctx == nil {
		return "", fmt.Errorf("kubeconfig %s has no current context", kubeconfigPath)
	}
	auth := cfg.AuthInfos[ctx.AuthInfo]
	if auth == nil || auth.TokenFile == "" {
		return "", nil
	}
	inline := auth.Token
	if inline == "" {
		return auth.TokenFile, nil
	}
	current, err := os.ReadFile(auth.TokenFile)
	if err == nil {
		inlineClaims, inlineErr := parseClaims(inline)
		fileClaims, fileErr := parseClaims(strings.TrimSpace(string(current)))
		sameIdentity := inlineErr == nil && fileErr == nil &&
			inlineClaims.Issuer == fileClaims.Issuer && inlineClaims.Subject == fileClaims.Subject
		if fileErr == nil && (inlineErr != nil || sameIdentity && !inlineClaims.IssuedAt.After(fileClaims.IssuedAt)) {
			return auth.TokenFile, nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	return auth.TokenFile, writeAtomic(auth.TokenFile, inline)
}

// Rotator replaces the token in File before it ages past maxAge.
type Rotator struct {
	Client kubernetes.Interface
	File   string
	// Lifetime is what a new token asks for when the current one's can't be
	// read. Zero means DefaultLifetime. Otherwise a new token asks for the
	// current one's lifetime, which the operator chose (its
	// --node-credential-ttl).
	Lifetime time.Duration
	// Interval is how often the token's age is checked. Zero means an hour.
	Interval time.Duration
	Now      func() time.Time
}

func (r *Rotator) Start(ctx context.Context) error {
	interval := r.Interval
	if interval <= 0 {
		interval = time.Hour
	}
	logger := log.FromContext(ctx).WithName("node-credential")
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		if rotated, err := r.RotateIfDue(ctx); err != nil {
			logger.Error(err, "replace the host's API token; keeping the current one")
		} else if rotated {
			logger.Info("replaced the host's API token", "file", r.File)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
		}
	}
}

// NeedLeaderElection is false: every host keeps its own token.
func (r *Rotator) NeedLeaderElection() bool { return false }

// RotateIfDue mints and writes a new token when the current one is older
// than maxAge or past half its lifetime.
func (r *Rotator) RotateIfDue(ctx context.Context) (bool, error) {
	now := time.Now
	if r.Now != nil {
		now = r.Now
	}
	raw, err := os.ReadFile(r.File)
	if err != nil {
		return false, err
	}
	claims, claimsErr := parseClaims(strings.TrimSpace(string(raw)))
	if claimsErr == nil && !claims.dueAt().Before(now()) {
		return false, nil
	}
	review, err := r.Client.AuthenticationV1().SelfSubjectReviews().Create(ctx, &authenticationv1.SelfSubjectReview{}, metav1.CreateOptions{})
	if err != nil {
		return false, fmt.Errorf("look up the host's identity: %w", err)
	}
	namespace, name, ok := strings.Cut(strings.TrimPrefix(review.Status.UserInfo.Username, serviceAccountPrefix), ":")
	if !strings.HasPrefix(review.Status.UserInfo.Username, serviceAccountPrefix) || !ok {
		return false, fmt.Errorf("host identity %q is not a ServiceAccount", review.Status.UserInfo.Username)
	}
	lifetime := r.Lifetime
	if claimsErr == nil {
		lifetime = claims.ExpiresAt.Sub(claims.IssuedAt)
	} else if lifetime <= 0 {
		lifetime = DefaultLifetime
	}
	seconds := int64(lifetime / time.Second)
	resp, err := r.Client.CoreV1().ServiceAccounts(namespace).CreateToken(ctx, name, &authenticationv1.TokenRequest{
		Spec: authenticationv1.TokenRequestSpec{ExpirationSeconds: &seconds},
	}, metav1.CreateOptions{})
	if err != nil {
		return false, fmt.Errorf("mint a token for %s/%s: %w", namespace, name, err)
	}
	if resp.Status.Token == "" {
		return false, errors.New("token request returned no token")
	}
	return true, writeAtomic(r.File, resp.Status.Token)
}

type claims struct {
	Issuer, Subject string
	IssuedAt        time.Time
	ExpiresAt       time.Time
}

// dueAt is when the token is replaced: maxAge after it was issued, or half
// way through its lifetime when that is sooner (an API server that caps
// token lifetimes).
func (c claims) dueAt() time.Time {
	due := c.IssuedAt.Add(maxAge)
	if half := c.IssuedAt.Add(c.ExpiresAt.Sub(c.IssuedAt) / 2); half.Before(due) {
		due = half
	}
	return due
}

// parseClaims reads a JWT's iat and exp without verifying it: the host only
// decides when to ask for a new one, and the API server judges the token.
func parseClaims(token string) (claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return claims{}, errors.New("not a JWT")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return claims{}, err
	}
	var c struct {
		Iss string `json:"iss"`
		Sub string `json:"sub"`
		Iat int64  `json:"iat"`
		Exp int64  `json:"exp"`
	}
	if err := json.Unmarshal(payload, &c); err != nil {
		return claims{}, err
	}
	if c.Iat == 0 || c.Exp <= c.Iat {
		return claims{}, errors.New("token carries no lifetime")
	}
	return claims{Issuer: c.Iss, Subject: c.Sub, IssuedAt: time.Unix(c.Iat, 0), ExpiresAt: time.Unix(c.Exp, 0)}, nil
}

// writeAtomic replaces path with a 0600 file holding token, so client-go
// never reads a partial token.
func writeAtomic(path, token string) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".token-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if err := f.Chmod(0o600); err != nil {
		f.Close()
		return err
	}
	if _, err := f.WriteString(token); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}
