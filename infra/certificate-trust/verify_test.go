package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"testing"
)

func command(t *testing.T, wantSuccess bool, name string, args ...string) []byte {
	t.Helper()
	output, err := exec.Command(name, args...).CombinedOutput()
	if (err == nil) != wantSuccess {
		t.Fatalf("%s %v: %v\n%s", name, args, err, output)
	}
	return output
}

func write(t *testing.T, name string, data []byte) {
	t.Helper()
	if err := os.WriteFile(name, data, 0600); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(name)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestVerifier(t *testing.T) {
	if err := check(); err != nil {
		t.Fatal(err)
	}
}

func TestPolicyEvidence(t *testing.T) {
	var policy struct {
		Hashes []string          `json:"distrusted_spki_sha256"`
		DER    map[string]string `json:"spki_der_base64"`
		Count  int               `json:"key_count"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil {
		t.Fatal(err)
	}
	if policy.Count != 12 || len(policy.Hashes) != 12 || len(policy.DER) != 12 {
		t.Fatal("expected four root keys and eight intermediate keys")
	}
	expected := map[string]bool{}
	for _, hash := range policy.Hashes {
		der, err := base64.StdEncoding.Strict().DecodeString(policy.DER[hash])
		if err != nil {
			t.Fatal(err)
		}
		if _, err := x509.ParsePKIXPublicKey(der); err != nil {
			t.Fatal(err)
		}
		if fmt.Sprintf("%x", sha256.Sum256(der)) != hash || expected[hash] {
			t.Fatal("inconsistent or duplicated policy evidence")
		}
		expected[hash] = true
	}
	for _, fixture := range []struct {
		path  string
		count int
	}{
		{"controls/issuer-roots.pem", 4},
		{"controls/distrusted-intermediates.pem", 8},
	} {
		certs, err := certificates(read(t, fixture.path))
		if err != nil || len(certs) != fixture.count {
			t.Fatalf("unexpected fixture %s: %v", fixture.path, err)
		}
		for _, cert := range certs {
			if !expected[spki(cert)] {
				t.Fatal("duplicate or unknown fixture key")
			}
			delete(expected, spki(cert))
		}
	}
	if len(expected) != 0 {
		t.Fatal("missing real certificate evidence")
	}
	// A different certificate carrying the same key must also be identified.
	cross, err := certificates(read(t, "controls/aaa-cross-signed-intermediate.pem"))
	if err != nil || len(cross) != 1 {
		t.Fatalf("missing cross-sign: %v", err)
	}
	intermediates, err := certificates(intermediatePEM)
	if err != nil {
		t.Fatal(err)
	}
	for _, cert := range intermediates {
		if spki(cert) == spki(cross[0]) && !bytes.Equal(cert.Raw, cross[0].Raw) {
			return
		}
	}
	t.Fatal("cross-sign must be a distinct certificate with an affected key")
}

func fixtures(t *testing.T) (good, bad []byte) {
	t.Helper()
	roots, err := certificates(issuerPEM)
	if err != nil {
		t.Fatal(err)
	}
	return positivePEM, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: roots[0].Raw})
}

func TestPEMChecksAndFiltering(t *testing.T) {
	good, bad := fixtures(t)
	work := t.TempDir()
	source, destination := filepath.Join(work, "source.pem"), filepath.Join(work, "filtered.pem")
	// Keep an unrelated private CA and its AUX restrictions byte-for-byte.
	private := filepath.Join(work, "enterprise.pem")
	command(t, true, "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-subj", "/CN=Private Enterprise CA", "-keyout", filepath.Join(work, "key.pem"), "-out", private, "-days", "1")
	trusted := command(t, true, "openssl", "x509", "-in", private, "-addreject", "clientAuth", "-trustout")
	kept := append(append([]byte{}, good...), trusted...)
	blocked := append(append(append([]byte{}, issuerPEM...), intermediatePEM...), read(t, "controls/aaa-cross-signed-intermediate.pem")...)
	write(t, source, append(append([]byte{}, blocked...), kept...))
	command(t, false, "bash", "pem-store.sh", "check", source)
	command(t, true, "bash", "pem-store.sh", "filter", source, destination)
	command(t, true, "bash", "pem-store.sh", "check", destination)
	if !bytes.Equal(read(t, destination), kept) {
		t.Fatal("filter changed unrelated public/private trust or AUX restrictions")
	}
	command(t, true, "bash", "pem-store.sh", "extract-blocked", source, filepath.Join(work, "blocked"))
	files, err := filepath.Glob(filepath.Join(work, "blocked", "*.pem"))
	if err != nil || len(files) != 12 {
		t.Fatalf("expected twelve extracted keys, got %d: %v", len(files), err)
	}
	for _, file := range files {
		certs, err := certificates(read(t, file))
		if err != nil || len(certs) != 1 || filepath.Base(file) != spki(certs[0])+".pem" {
			t.Fatalf("incorrect extracted key %s: %v", file, err)
		}
	}
	command(t, false, "bash", "pem-store.sh", "filter", source, source)
	command(t, false, "bash", "pem-store.sh", "check", destination, source)
	command(t, false, "bash", "pem-store.sh", "check", filepath.Join(work, "missing"))
	for _, invalid := range [][]byte{
		bad, []byte("not a store"),
		append(append([]byte{}, kept...), read(t, filepath.Join(work, "key.pem"))...),
		append(append([]byte{}, kept...), []byte("-----BEGIN CERTIFICATE-----\nbroken\n")...),
		append(append([]byte{}, kept...), bytes.ReplaceAll(bad, []byte("CERTIFICATE"), []byte("TRUSTED CERTIFICATE"))...),
	} {
		write(t, source, invalid)
		command(t, false, "bash", "pem-store.sh", "filter", source, destination)
		if !bytes.Equal(read(t, destination), kept) {
			t.Fatal("failed filter replaced destination")
		}
	}
}

func TestPublicJavaStoreFiltering(t *testing.T) {
	good, bad := fixtures(t)
	work := t.TempDir()
	store := filepath.Join(work, "cacerts")
	private := filepath.Join(work, "enterprise.pem")
	command(t, true, "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-subj", "/CN=Private Enterprise CA", "-keyout", filepath.Join(work, "key.pem"), "-out", private, "-days", "1")
	entries := map[string][]byte{"positive root": good, "blocked root": bad, "private enterprise root": read(t, private)}
	for alias, data := range entries {
		file := filepath.Join(work, alias+".pem")
		write(t, file, data)
		command(t, true, "keytool", "-importcert", "-noprompt", "-storetype", "JKS", "-keystore", store, "-storepass", "changeit", "-alias", alias, "-file", file)
	}
	link := store + ".symlink"
	if err := os.Symlink(store, link); err != nil {
		t.Fatal(err)
	}
	command(t, false, "bash", "java-store.sh", "check", link)
	command(t, true, "bash", "java-store.sh", "filter", link)
	command(t, true, "bash", "java-store.sh", "check", store)
	for _, alias := range []string{"positive root", "private enterprise root"} {
		exported := command(t, true, "keytool", "-exportcert", "-rfc", "-keystore", store, "-storepass", "changeit", "-alias", alias)
		actual, _ := pem.Decode(exported)
		expected, _ := pem.Decode(entries[alias])
		if actual == nil || expected == nil || !bytes.Equal(actual.Bytes, expected.Bytes) {
			t.Fatalf("changed unrelated Java anchor %s", alias)
		}
	}
	command(t, false, "keytool", "-list", "-keystore", store, "-storepass", "changeit", "-alias", "blocked root")
	if _, err := os.Readlink(link); err != nil {
		t.Fatal("replaced Java store symlink")
	}
	before := read(t, store)
	if err := os.Link(store, store+".hardlink"); err != nil {
		t.Fatal(err)
	}
	command(t, false, "bash", "java-store.sh", "filter", store)
	if !bytes.Equal(before, read(t, store)) || !bytes.Equal(before, read(t, store+".hardlink")) {
		t.Fatal("hardlinked store was modified")
	}
}

func TestPasswordlessPKCS12RemainsReadableWithoutPassword(t *testing.T) {
	work := t.TempDir()
	store := filepath.Join(work, "cacerts.p12")
	good, bad := fixtures(t)
	for alias, data := range map[string][]byte{"positive": good, "blocked": bad} {
		file := filepath.Join(work, alias+".pem")
		write(t, file, data)
		command(t, true, "keytool", "-J-Dkeystore.pkcs12.certProtectionAlgorithm=NONE", "-J-Dkeystore.pkcs12.macAlgorithm=NONE", "-importcert", "-noprompt", "-storetype", "PKCS12", "-keystore", store, "-storepass", "changeit", "-alias", alias, "-file", file)
	}
	command(t, true, "bash", "java-store.sh", "filter", store)
	// No password and nil stdin: the default JSSE load must still see anchors.
	listing := command(t, true, "keytool", "-J-Duser.language=en", "-J-Duser.country=US", "-list", "-keystore", store)
	count := regexp.MustCompile(`Your keystore contains ([0-9]+) entr`).FindSubmatch(listing)
	if len(count) != 2 {
		t.Fatalf("cannot establish passwordless entry count: %s", listing)
	}
	actual, err := strconv.Atoi(string(count[1]))
	if err != nil || actual != 1 || !bytes.Contains(listing, []byte("PKCS12")) || !bytes.Contains(listing, []byte("positive")) {
		t.Fatalf("passwordless PKCS12 lost anchors: %s", listing)
	}
}

func TestJavaPrivateIdentityIsNeverRewritten(t *testing.T) {
	work := t.TempDir()
	store := filepath.Join(work, "identity.p12")
	command(t, true, "keytool", "-genkeypair", "-keyalg", "EC", "-groupname", "secp256r1", "-dname", "CN=test", "-validity", "1", "-keystore", store, "-storepass", "changeit", "-keypass", "changeit", "-alias", "client")
	// Include an affected trust entry: filtering must refuse the whole mixed store.
	_, bad := fixtures(t)
	file := filepath.Join(work, "blocked.pem")
	write(t, file, bad)
	command(t, true, "keytool", "-importcert", "-noprompt", "-keystore", store, "-storepass", "changeit", "-alias", "blocked", "-file", file)
	before := read(t, store)
	command(t, false, "bash", "java-store.sh", "check", store)
	command(t, false, "bash", "java-store.sh", "filter", store)
	if !bytes.Equal(before, read(t, store)) {
		t.Fatal("private identity store was changed")
	}
}
