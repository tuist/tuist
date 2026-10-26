package main

import (
	"bytes"
	"crypto/x509"
	"encoding/json"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestTLSWitnessPaths(t *testing.T) {
	leaves, manifest, err := witnesses(tlsLeavesPEM, tlsLeavesJSON)
	if err != nil {
		t.Fatal(err)
	}
	roots, err := certificates(issuerPEM)
	if err != nil {
		t.Fatal(err)
	}
	intermediates, err := certificates(intermediatePEM)
	if err != nil {
		t.Fatal(err)
	}
	for index, leaf := range leaves {
		witness := manifest[index]
		path, err := witnessPath(leaf, witness, roots, intermediates)
		if err != nil {
			t.Fatal(err)
		}
		if len(path) != 3 || spki(path[1]) != witness.IssuerSPKI {
			t.Fatal("incident key must be below the leaf and above the trust anchor")
		}
		options, err := witnessOptions(path, witness.Host)
		if err != nil || options.DNSName != witness.Host || len(options.KeyUsages) != 1 || options.KeyUsages[0] != x509.ExtKeyUsageServerAuth {
			t.Fatalf("missing TLS verification context: %v", err)
		}
		for _, certificate := range path {
			if options.CurrentTime.Before(certificate.NotBefore) || !options.CurrentTime.Before(certificate.NotAfter) {
				t.Fatal("verification outside shared validity window")
			}
		}
		if _, err := witnessPath(leaf, witness, nil, intermediates); err == nil {
			t.Fatal("accepted missing issuer root")
		}
		wrongIssuer := witness
		wrongIssuer.IssuerSPKI = strings.Repeat("0", 64)
		if _, err := witnessPath(leaf, wrongIssuer, roots, intermediates); err == nil {
			t.Fatal("accepted an unrecorded issuer")
		}
		corrupt := *leaf
		corrupt.Signature = bytes.Clone(leaf.Signature)
		corrupt.Signature[0] ^= 1
		if _, err := witnessPath(&corrupt, witness, roots, intermediates); err == nil {
			t.Fatal("accepted an invalid leaf signature")
		}
		expired := *leaf
		expired.NotAfter = expired.NotBefore
		if _, err := witnessOptions([]*x509.Certificate{&expired, path[1], path[2]}, witness.Host); err == nil {
			t.Fatal("accepted no shared validity window")
		}
	}
}

func TestTLSWitnessManifestRejectsTampering(t *testing.T) {
	_, original, err := witnesses(tlsLeavesPEM, tlsLeavesJSON)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"missing", "hash", "hostname", "duplicate issuer"} {
		t.Run(name, func(t *testing.T) {
			manifest := append([]tlsWitness{}, original...)
			switch name {
			case "missing":
				manifest = manifest[1:]
			case "hash":
				manifest[0].SHA256 = strings.Repeat("0", 64)
			case "hostname":
				manifest[0].Host = "not-the-recorded-host.invalid"
			case "duplicate issuer":
				manifest[1].IssuerSPKI = manifest[0].IssuerSPKI
			}
			metadata, err := json.Marshal(struct {
				Certificates []tlsWitness `json:"certificates"`
			}{manifest})
			if err != nil {
				t.Fatal(err)
			}
			if _, _, err := witnesses(tlsLeavesPEM, metadata); err == nil {
				t.Fatal("accepted altered public witness manifest")
			}
		})
	}
}

func TestSDKSelectionIsExplicitAndExact(t *testing.T) {
	for _, expected := range []string{"", "go0.0.0"} {
		cmd := exec.Command(os.Args[0], "-test.run=^TestVerifier$")
		for _, entry := range os.Environ() {
			if !strings.HasPrefix(entry, "TRUST_EXPECTED_GO_SDK=") {
				cmd.Env = append(cmd.Env, entry)
			}
		}
		if expected != "" {
			cmd.Env = append(cmd.Env, "TRUST_EXPECTED_GO_SDK="+expected)
		}
		output, err := cmd.CombinedOutput()
		if err == nil {
			t.Fatal("accepted an unset or mismatched expected SDK")
		}
		message := "TRUST_EXPECTED_GO_SDK must explicitly select"
		if expected != "" {
			message = "requested go0.0.0 but compiled with"
		}
		if !bytes.Contains(output, []byte(message)) {
			t.Fatalf("failed for the wrong reason: %s", output)
		}
	}
}
