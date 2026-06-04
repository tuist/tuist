package mitm

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"fmt"
	"math/big"
	"sync"
	"time"
)

// LeafCache mints and caches leaf certificates per SNI, all signed by the
// baked CA and sharing one freshly generated leaf key.
type LeafCache struct {
	ca      *CA
	leafKey *ecdsa.PrivateKey

	mu    sync.Mutex
	cache map[string]*tls.Certificate

	now      func() time.Time
	validity time.Duration
}

// NewLeafCache builds a leaf cache over a CA.
func NewLeafCache(ca *CA) (*LeafCache, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("mitm: generate leaf key: %w", err)
	}
	return &LeafCache{
		ca:       ca,
		leafKey:  key,
		cache:    map[string]*tls.Certificate{},
		now:      time.Now,
		validity: 24 * time.Hour,
	}, nil
}

// For returns a leaf certificate for the given SNI, minting and caching it
// on a miss. The returned chain is leaf + CA so the guest (which trusts
// the baked CA) validates it.
func (l *LeafCache) For(sni string) (*tls.Certificate, error) {
	if sni == "" {
		return nil, fmt.Errorf("mitm: empty SNI")
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	if c, ok := l.cache[sni]; ok {
		return c, nil
	}

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("mitm: serial: %w", err)
	}
	now := l.now()
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: sni},
		DNSNames:     []string{sni},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.Add(l.validity),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, l.ca.cert, l.leafKey.Public(), l.ca.key)
	if err != nil {
		return nil, fmt.Errorf("mitm: create leaf: %w", err)
	}
	cert := &tls.Certificate{
		Certificate: [][]byte{der, l.ca.cert.Raw},
		PrivateKey:  l.leafKey,
	}
	l.cache[sni] = cert
	return cert, nil
}

// TLSConfig returns a server TLS config that mints leaves per ClientHello
// SNI. Used to terminate the MITM connection toward the guest.
func (l *LeafCache) TLSConfig() *tls.Config {
	return &tls.Config{
		GetCertificate: func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
			return l.For(hello.ServerName)
		},
		MinVersion: tls.VersionTLS12,
	}
}
