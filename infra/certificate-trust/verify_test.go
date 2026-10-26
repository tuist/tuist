package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"testing"
)

func TestVerifier(t *testing.T) {
	if err := check(); err != nil {
		t.Fatal(err)
	}
}

func TestPolicyEvidence(t *testing.T) {
	var policy struct {
		ID     string            `json:"id"`
		Hashes []string          `json:"distrusted_spki_sha256"`
		DER    map[string]string `json:"spki_der_base64"`
		Count  int               `json:"key_count"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil {
		t.Fatal(err)
	}
	if policy.ID != "emudhra-2026-10-19-v2" || policy.Count != 12 || len(policy.Hashes) != 12 || len(policy.DER) != 12 {
		t.Fatal("expected the twelve-key eMudhra policy")
	}
	expected := make(map[string][]byte)
	for _, hash := range policy.Hashes {
		der, err := base64.StdEncoding.Strict().DecodeString(policy.DER[hash])
		if err != nil {
			t.Fatal(err)
		}
		if _, err := x509.ParsePKIXPublicKey(der); err != nil {
			t.Fatal(err)
		}
		if fmt.Sprintf("%x", sha256.Sum256(der)) != hash || expected[hash] != nil {
			t.Fatal("inconsistent or duplicated policy evidence")
		}
		expected[hash] = der
	}
	for _, fixture := range []struct {
		name  string
		data  []byte
		count int
		root  bool
	}{
		{"issuer roots", issuerPEM, 4, true},
		{"intermediates", intermediatePEM, 8, false},
	} {
		certs, err := certificates(fixture.data)
		if err != nil || len(certs) != fixture.count {
			t.Fatalf("%s: expected %d certificates, got %d: %v", fixture.name, fixture.count, len(certs), err)
		}
		for _, cert := range certs {
			// Native trust anchors need not have acceptable self-signature
			// algorithms (the public AAA root uses SHA-1). Do not relax the
			// verifier to validate an otherwise irrelevant self-signature.
			if !cert.IsCA || bytes.Equal(cert.RawIssuer, cert.RawSubject) != fixture.root {
				t.Fatalf("%s: incorrect certificate role", fixture.name)
			}
			hash := spki(cert)
			if !bytes.Equal(expected[hash], cert.RawSubjectPublicKeyInfo) {
				t.Fatalf("%s: fixture is absent, duplicated or differs from policy DER", fixture.name)
			}
			delete(expected, hash)
		}
	}
	if len(expected) != 0 {
		t.Fatal("public fixtures do not cover every policy key exactly once")
	}
}

func TestPositiveFixtureEvidence(t *testing.T) {
	roots, err := certificates(positivePEM)
	if err != nil || len(roots) != 1 {
		t.Fatalf("expected one positive root: %v", err)
	}
	intermediates, err := certificates(positiveIntermediatePEM)
	if err != nil || len(intermediates) != 1 {
		t.Fatalf("expected one positive intermediate: %v", err)
	}
	if err := roots[0].CheckSignatureFrom(roots[0]); err != nil {
		t.Fatalf("positive root is not self-signed: %v", err)
	}
	if err := intermediates[0].CheckSignatureFrom(roots[0]); err != nil {
		t.Fatalf("positive intermediate has no valid issuer: %v", err)
	}
}

func TestCertificatesRejectMalformedFixtures(t *testing.T) {
	certs, err := certificates(positivePEM)
	if err != nil || len(certs) != 1 {
		t.Fatal("invalid positive fixture")
	}
	for name, data := range map[string][]byte{
		"invalid base64":   []byte("-----BEGIN CERTIFICATE-----\ninvalid\n-----END CERTIFICATE-----\n"),
		"truncated block":  []byte("-----BEGIN CERTIFICATE-----\n"),
		"invalid DER":      pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: []byte{0}}),
		"private material": pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: []byte{0}}),
		"wrong block type": pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: certs[0].RawSubjectPublicKeyInfo}),
		"trailing garbage": append(bytes.Clone(positivePEM), []byte("invalid")...),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := certificates(data); err == nil {
				t.Fatal("accepted malformed or non-certificate fixture")
			}
		})
	}
}
