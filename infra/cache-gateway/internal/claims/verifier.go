package claims

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Verifier validates a raw bearer token and returns typed claims. It
// never returns partial claims alongside an error.
type Verifier interface {
	Verify(ctx context.Context, raw string) (*Claims, error)
}

// ErrInvalidToken is returned for any verification failure. The caller
// treats it as "not authenticated" and never as a partial success.
var ErrInvalidToken = errors.New("claims: invalid token")

// Ed25519Verifier verifies EdDSA-signed tokens with a public key only.
// The gateway holds no signing material.
type Ed25519Verifier struct {
	parser *jwt.Parser
	key    ed25519.PublicKey
	now    func() time.Time
}

// NewEd25519Verifier builds a verifier from a PEM-encoded Ed25519 public
// key. The parser is pinned to EdDSA so neither `alg: none` nor an HMAC
// algorithm (the classic public-key-as-HMAC-secret confusion attack) is
// ever accepted.
func NewEd25519Verifier(pemPublicKey []byte) (*Ed25519Verifier, error) {
	block, _ := pem.Decode(pemPublicKey)
	if block == nil {
		return nil, fmt.Errorf("claims: no PEM block in public key")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("claims: parse public key: %w", err)
	}
	pub, ok := parsed.(ed25519.PublicKey)
	if !ok {
		return nil, fmt.Errorf("claims: public key is not Ed25519 (got %T)", parsed)
	}
	v := &Ed25519Verifier{key: pub, now: time.Now}
	v.parser = jwt.NewParser(
		jwt.WithValidMethods([]string{"EdDSA"}),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(func() time.Time { return v.now() }),
	)
	return v, nil
}

type rawClaims struct {
	AccountID     uint64 `json:"account_id"`
	Repo          string `json:"repo"`
	Fleet         string `json:"fleet"`
	Ref           string `json:"ref"`
	DefaultBranch string `json:"default_branch"`
	BaseRef       string `json:"base_ref"`
	UntrustedFork bool   `json:"untrusted_fork"`
	WorkflowJobID uint64 `json:"workflow_job_id"`
	jwt.RegisteredClaims
}

// Verify parses and cryptographically validates raw, then maps it to
// typed Claims. exp/iat are enforced by the JWT library against the
// verifier's clock.
func (v *Ed25519Verifier) Verify(_ context.Context, raw string) (*Claims, error) {
	var rc rawClaims
	_, err := v.parser.ParseWithClaims(raw, &rc, func(t *jwt.Token) (any, error) {
		return v.key, nil
	})
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}

	c := &Claims{
		AccountID:     rc.AccountID,
		Repo:          rc.Repo,
		Fleet:         rc.Fleet,
		Ref:           rc.Ref,
		DefaultBranch: rc.DefaultBranch,
		BaseRef:       rc.BaseRef,
		UntrustedFork: rc.UntrustedFork,
		WorkflowJobID: rc.WorkflowJobID,
	}
	if rc.IssuedAt != nil {
		c.IssuedAt = rc.IssuedAt.Unix()
	}
	if rc.ExpiresAt != nil {
		c.ExpiresAt = rc.ExpiresAt.Unix()
	}
	if c.AccountID == 0 {
		return nil, fmt.Errorf("%w: missing account_id", ErrInvalidToken)
	}
	return c, nil
}
