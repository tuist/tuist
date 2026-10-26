package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"runtime"
	"time"
)

//go:embed controls/tls-leaves.pem
var tlsLeavesPEM []byte

//go:embed controls/tls-leaves.json
var tlsLeavesJSON []byte

type tlsWitness struct {
	Host       string `json:"host"`
	SHA256     string `json:"certificate_sha256"`
	IssuerSPKI string `json:"issuer_spki_sha256"`
}

func witnesses(data, metadata []byte) ([]*x509.Certificate, []tlsWitness, error) {
	leaves, err := certificates(data)
	if err != nil {
		return nil, nil, err
	}
	var manifest struct {
		Certificates []tlsWitness `json:"certificates"`
	}
	if err := json.Unmarshal(metadata, &manifest); err != nil {
		return nil, nil, err
	}
	if len(leaves) != 6 || len(manifest.Certificates) != len(leaves) {
		return nil, nil, errors.New("expected six public TLS leaf witnesses")
	}
	seen := make(map[string]bool)
	for index, leaf := range leaves {
		witness := manifest.Certificates[index]
		if leaf.IsCA || fmt.Sprintf("%x", sha256.Sum256(leaf.Raw)) != witness.SHA256 || seen[witness.IssuerSPKI] {
			return nil, nil, errors.New("invalid, duplicated or mismatched public TLS witness")
		}
		if witness.Host == "" || leaf.VerifyHostname(witness.Host) != nil {
			return nil, nil, errors.New("public TLS witness does not match its recorded hostname")
		}
		seen[witness.IssuerSPKI] = true
	}
	return leaves, manifest.Certificates, nil
}

func witnessPath(leaf *x509.Certificate, witness tlsWitness, roots, intermediates []*x509.Certificate) ([]*x509.Certificate, error) {
	for _, intermediate := range intermediates {
		if spki(intermediate) != witness.IssuerSPKI || !bytes.Equal(leaf.RawIssuer, intermediate.RawSubject) || leaf.CheckSignatureFrom(intermediate) != nil {
			continue
		}
		for _, root := range roots {
			if bytes.Equal(intermediate.RawIssuer, root.RawSubject) && intermediate.CheckSignatureFrom(root) == nil {
				return []*x509.Certificate{leaf, intermediate, root}, nil
			}
		}
	}
	return nil, errors.New("public TLS witness has no cryptographically valid incident issuer path")
}

func witnessOptions(path []*x509.Certificate, host string) (x509.VerifyOptions, error) {
	when, until := path[0].NotBefore, path[0].NotAfter
	for _, certificate := range path[1:] {
		if certificate.NotBefore.After(when) {
			when = certificate.NotBefore
		}
		if certificate.NotAfter.Before(until) {
			until = certificate.NotAfter
		}
	}
	when = when.Add(time.Hour)
	if !when.Before(until) {
		return x509.VerifyOptions{}, errors.New("public TLS witness has no shared validity window")
	}
	roots, intermediates := x509.NewCertPool(), x509.NewCertPool()
	roots.AddCert(path[2])
	intermediates.AddCert(path[1])
	return x509.VerifyOptions{
		Roots: roots, Intermediates: intermediates, CurrentTime: when,
		DNSName: host, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}, nil
}

func checkTLSWitnesses(roots, intermediates []*x509.Certificate) error {
	leaves, manifest, err := witnesses(tlsLeavesPEM, tlsLeavesJSON)
	if err != nil {
		return err
	}
	for index, leaf := range leaves {
		path, err := witnessPath(leaf, manifest[index], roots, intermediates)
		if err != nil {
			return err
		}
		options, err := witnessOptions(path, manifest[index].Host)
		if err != nil {
			return err
		}
		_, err = leaf.Verify(options)
		var invalid x509.CertificateInvalidError
		if !errors.As(err, &invalid) || invalid.Reason != x509.NoValidChains || invalid.Detail != "" {
			return fmt.Errorf("%s did not enforce the non-leaf intermediate-key deny for %s: %v", runtime.Version(), manifest[index].IssuerSPKI, err)
		}
	}
	return nil
}
