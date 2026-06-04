package claims

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func testKeypair(t *testing.T) (ed25519.PrivateKey, []byte) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatalf("marshal public key: %v", err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})
	return priv, pemBytes
}

func signEdDSA(t *testing.T, priv ed25519.PrivateKey, claims jwt.MapClaims) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims)
	s, err := tok.SignedString(priv)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

func baseClaims(now time.Time) jwt.MapClaims {
	return jwt.MapClaims{
		"account_id":      float64(1111),
		"repo":            "tuist/tuist",
		"fleet":           "tuist-runners",
		"ref":             "refs/heads/main",
		"default_branch":  "refs/heads/main",
		"workflow_job_id": float64(42),
		"iat":             now.Unix(),
		"exp":             now.Add(10 * time.Minute).Unix(),
	}
}

func TestVerifyValidToken(t *testing.T) {
	priv, pemPub := testKeypair(t)
	v, err := NewEd25519Verifier(pemPub)
	if err != nil {
		t.Fatalf("new verifier: %v", err)
	}
	now := time.Unix(1_700_000_000, 0)
	v.now = func() time.Time { return now }

	tok := signEdDSA(t, priv, baseClaims(now))
	c, err := v.Verify(context.Background(), tok)
	if err != nil {
		t.Fatalf("Verify() error: %v", err)
	}
	if c.AccountID != 1111 || c.Repo != "tuist/tuist" || c.WorkflowJobID != 42 {
		t.Fatalf("unexpected claims: %+v", c)
	}
}

func TestVerifyRejectsAlgNone(t *testing.T) {
	_, pemPub := testKeypair(t)
	v, _ := NewEd25519Verifier(pemPub)
	now := time.Unix(1_700_000_000, 0)
	v.now = func() time.Time { return now }

	tok := jwt.NewWithClaims(jwt.SigningMethodNone, baseClaims(now))
	raw, err := tok.SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("sign none: %v", err)
	}
	if _, err := v.Verify(context.Background(), raw); err == nil {
		t.Fatal("Verify() accepted alg:none token")
	}
}

func TestVerifyRejectsHMACConfusion(t *testing.T) {
	// Classic confusion attack: sign with HS256 using the PUBLIC key
	// bytes as the HMAC secret. A verifier that does not pin the alg
	// would accept it. The PEM-DER public bytes stand in for the
	// attacker-known key material.
	_, pemPub := testKeypair(t)
	v, _ := NewEd25519Verifier(pemPub)
	now := time.Unix(1_700_000_000, 0)
	v.now = func() time.Time { return now }

	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, baseClaims(now))
	raw, err := tok.SignedString(pemPub)
	if err != nil {
		t.Fatalf("sign hs256: %v", err)
	}
	if _, err := v.Verify(context.Background(), raw); err == nil {
		t.Fatal("Verify() accepted HS256-with-public-key token")
	}
}

func TestVerifyRejectsExpired(t *testing.T) {
	priv, pemPub := testKeypair(t)
	v, _ := NewEd25519Verifier(pemPub)
	now := time.Unix(1_700_000_000, 0)
	v.now = func() time.Time { return now }

	claims := baseClaims(now)
	claims["iat"] = now.Add(-20 * time.Minute).Unix()
	claims["exp"] = now.Add(-10 * time.Minute).Unix()
	tok := signEdDSA(t, priv, claims)
	if _, err := v.Verify(context.Background(), tok); err == nil {
		t.Fatal("Verify() accepted expired token")
	}
}

func TestVerifyRejectsWrongSigner(t *testing.T) {
	_, pemPub := testKeypair(t)
	otherPriv, _ := testKeypair(t) // a different keypair's private key
	v, _ := NewEd25519Verifier(pemPub)
	now := time.Unix(1_700_000_000, 0)
	v.now = func() time.Time { return now }

	tok := signEdDSA(t, otherPriv, baseClaims(now))
	if _, err := v.Verify(context.Background(), tok); err == nil {
		t.Fatal("Verify() accepted a token signed by the wrong key")
	}
}

func TestVerifyRejectsGarbage(t *testing.T) {
	_, pemPub := testKeypair(t)
	v, _ := NewEd25519Verifier(pemPub)
	if _, err := v.Verify(context.Background(), "not.a.jwt"); err == nil {
		t.Fatal("Verify() accepted garbage")
	}
}
