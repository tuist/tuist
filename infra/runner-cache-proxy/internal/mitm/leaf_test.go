package mitm

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"testing"
	"time"
)

func genTestCA(t *testing.T) (certPEM, keyPEM []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "Tuist Runner Cache CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, key.Public(), key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	certPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM = pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	return certPEM, keyPEM
}

func TestLeafChainsToCA(t *testing.T) {
	certPEM, keyPEM := genTestCA(t)
	ca, err := LoadCA(certPEM, keyPEM)
	if err != nil {
		t.Fatalf("LoadCA: %v", err)
	}
	lc, err := NewLeafCache(ca)
	if err != nil {
		t.Fatalf("NewLeafCache: %v", err)
	}

	const host = "results-receiver.actions.githubusercontent.com"
	cert, err := lc.For(host)
	if err != nil {
		t.Fatalf("For: %v", err)
	}
	leaf, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		t.Fatal(err)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		DNSName:     host,
		Roots:       ca.Pool(),
		CurrentTime: time.Now(),
	}); err != nil {
		t.Fatalf("leaf does not verify against CA for %s: %v", host, err)
	}
}

func TestLeafCacheReturnsSameCert(t *testing.T) {
	certPEM, keyPEM := genTestCA(t)
	ca, _ := LoadCA(certPEM, keyPEM)
	lc, _ := NewLeafCache(ca)

	a, _ := lc.For("host.example")
	b, _ := lc.For("host.example")
	if a != b {
		t.Fatal("expected the same cached *tls.Certificate for repeated SNI")
	}
	c, _ := lc.For("other.example")
	if a == c {
		t.Fatal("distinct SNIs should get distinct leaves")
	}
}

func TestLoadCARejectsNonCA(t *testing.T) {
	// A self-signed leaf (IsCA=false) must be rejected.
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "leaf"}, NotAfter: time.Now().Add(time.Hour)}
	der, _ := x509.CreateCertificate(rand.Reader, tmpl, tmpl, key.Public(), key)
	keyDER, _ := x509.MarshalPKCS8PrivateKey(key)
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
	if _, err := LoadCA(certPEM, keyPEM); err == nil {
		t.Fatal("LoadCA accepted a non-CA certificate")
	}
}
