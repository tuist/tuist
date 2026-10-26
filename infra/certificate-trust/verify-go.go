// Run this with each proposed SDK; never infer protection from version ordering.
// It probes eight incident certificates directly and six public TLS chains.
// The two code-signing keys have no non-leaf witness in this fixture set.
package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"runtime"
	"time"
)

//go:embed policy.json
var policyJSON []byte

//go:embed controls/issuer-roots.pem
var issuerPEM []byte

//go:embed controls/distrusted-intermediates.pem
var intermediatePEM []byte

//go:embed controls/positive-isrg-root-x1.pem
var positivePEM []byte

//go:embed controls/positive-isrg-r11.pem
var positiveIntermediatePEM []byte

func certificates(data []byte) ([]*x509.Certificate, error) {
	var result []*x509.Certificate
	begin, end := []byte("-----BEGIN CERTIFICATE-----"), []byte("-----END CERTIFICATE-----")
	for data = bytes.TrimSpace(data); len(data) > 0; data = bytes.TrimSpace(data) {
		last := bytes.Index(data, end)
		if !bytes.HasPrefix(data, begin) || last < 0 {
			return nil, errors.New("invalid public control fixture")
		}
		last += len(end)
		encoded := data[:last]
		block, rest := pem.Decode(encoded)
		if block == nil || block.Type != "CERTIFICATE" || len(block.Headers) != 0 || len(rest) != 0 || bytes.Count(encoded, begin) != 1 {
			return nil, errors.New("invalid public control fixture")
		}
		certificate, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, err
		}
		result = append(result, certificate)
		data = data[last:]
	}
	if len(result) == 0 {
		return nil, errors.New("empty public control fixture")
	}
	return result, nil
}

func spki(certificate *x509.Certificate) string {
	return fmt.Sprintf("%x", sha256.Sum256(certificate.RawSubjectPublicKeyInfo))
}

func check() error {
	expectedSDK := os.Getenv("TRUST_EXPECTED_GO_SDK")
	if expectedSDK == "" {
		return errors.New("TRUST_EXPECTED_GO_SDK must explicitly select the SDK being evaluated")
	}
	if runtime.Version() != expectedSDK {
		return fmt.Errorf("requested %s but compiled with %s", expectedSDK, runtime.Version())
	}
	var policy struct {
		Hashes []string `json:"distrusted_spki_sha256"`
		Count  int      `json:"key_count"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil {
		return err
	}
	expected := make(map[string]bool)
	for _, hash := range policy.Hashes {
		expected[hash] = true
	}
	if len(expected) != policy.Count || len(policy.Hashes) != policy.Count {
		return errors.New("inconsistent distrust policy")
	}
	roots, err := certificates(issuerPEM)
	if err != nil {
		return err
	}
	intermediates, err := certificates(intermediatePEM)
	if err != nil {
		return err
	}
	pool := x509.NewCertPool()
	for _, root := range roots {
		if !expected[spki(root)] {
			return errors.New("root fixture is absent from policy or duplicated")
		}
		delete(expected, spki(root))
		pool.AddCert(root)
	}
	for _, intermediate := range intermediates {
		if !expected[spki(intermediate)] {
			return errors.New("intermediate fixture is absent from policy or duplicated")
		}
		delete(expected, spki(intermediate))
		var issuer *x509.Certificate
		for _, root := range roots {
			if bytes.Equal(intermediate.RawIssuer, root.RawSubject) && intermediate.CheckSignatureFrom(root) == nil {
				issuer = root
				break
			}
		}
		if issuer == nil {
			return errors.New("negative control has no cryptographically valid issuer")
		}
		when := intermediate.NotBefore
		if issuer.NotBefore.After(when) {
			when = issuer.NotBefore
		}
		when = when.Add(time.Hour)
		if !when.Before(intermediate.NotAfter) || !when.Before(issuer.NotAfter) {
			return errors.New("negative control has no valid time window")
		}
		_, err := intermediate.Verify(x509.VerifyOptions{
			Roots: pool, CurrentTime: when, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
		})
		var invalid x509.CertificateInvalidError
		if !errors.As(err, &invalid) || invalid.Reason != x509.NoValidChains || invalid.Detail != "" {
			return fmt.Errorf("%s did not enforce the intermediate-key deny for %s: %v", runtime.Version(), spki(intermediate), err)
		}
	}
	if len(expected) != 0 {
		return errors.New("control fixtures do not cover the complete policy")
	}
	if err := checkTLSWitnesses(roots, intermediates); err != nil {
		return err
	}
	positive, err := certificates(positivePEM)
	if err != nil || len(positive) != 1 {
		return errors.New("missing positive control")
	}
	healthy, err := certificates(positiveIntermediatePEM)
	if err != nil || len(healthy) != 1 || healthy[0].CheckSignatureFrom(positive[0]) != nil {
		return errors.New("positive intermediate has no valid issuer")
	}
	for _, hash := range policy.Hashes {
		if hash == spki(healthy[0]) || hash == spki(positive[0]) {
			return errors.New("positive control is distrusted by the policy")
		}
	}
	allowed := x509.NewCertPool()
	allowed.AddCert(positive[0])
	if _, err := healthy[0].Verify(x509.VerifyOptions{
		Roots: allowed, CurrentTime: healthy[0].NotBefore.Add(time.Hour), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return fmt.Errorf("positive control failed: %w", err)
	}
	fmt.Printf("Verifier probe passed: %s, %d direct intermediate controls, 6 public TLS chains, unrelated positive control\n", runtime.Version(), len(intermediates))
	return nil
}

func main() {
	if err := check(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
