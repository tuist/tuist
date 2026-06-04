// Package mitm loads the baked CA and mints short-lived leaf certificates
// on the fly for the GitHub-Actions-cache hostnames the proxy intercepts.
// The CA private key lives only on the host (never in the guest), and
// only its public certificate is baked into the runner images' trust
// stores, so the guest accepts the leaves the proxy presents.
package mitm

import (
	"crypto"
	"crypto/x509"
	"encoding/pem"
	"fmt"
)

// CA is the loaded MITM signing authority.
type CA struct {
	cert *x509.Certificate
	key  crypto.Signer
}

// LoadCA parses a PEM CA certificate and private key.
func LoadCA(certPEM, keyPEM []byte) (*CA, error) {
	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil {
		return nil, fmt.Errorf("mitm: no PEM block in CA certificate")
	}
	cert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("mitm: parse CA certificate: %w", err)
	}
	if !cert.IsCA {
		return nil, fmt.Errorf("mitm: certificate is not a CA")
	}

	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil {
		return nil, fmt.Errorf("mitm: no PEM block in CA key")
	}
	key, err := parsePrivateKey(keyBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("mitm: parse CA key: %w", err)
	}
	return &CA{cert: cert, key: key}, nil
}

func parsePrivateKey(der []byte) (crypto.Signer, error) {
	if k, err := x509.ParsePKCS8PrivateKey(der); err == nil {
		if signer, ok := k.(crypto.Signer); ok {
			return signer, nil
		}
		return nil, fmt.Errorf("mitm: PKCS8 key is not a signer")
	}
	if k, err := x509.ParseECPrivateKey(der); err == nil {
		return k, nil
	}
	if k, err := x509.ParsePKCS1PrivateKey(der); err == nil {
		return k, nil
	}
	return nil, fmt.Errorf("mitm: unsupported private key format")
}

// CertPEM returns the CA certificate in PEM form (for building a pool).
func (c *CA) CertPEM() []byte {
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: c.cert.Raw})
}

// Pool returns an x509 pool trusting this CA.
func (c *CA) Pool() *x509.CertPool {
	p := x509.NewCertPool()
	p.AddCert(c.cert)
	return p
}
