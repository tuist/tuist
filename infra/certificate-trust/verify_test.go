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
	"reflect"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"testing"
)

func command(t *testing.T, wantSuccess bool, name string, args ...string) []byte {
	t.Helper()
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
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

func TestPolicyEvidenceAndOTPSynchronization(t *testing.T) {
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
	for _, path := range []string{
		"../../cli/Sources/TuistHTTP/CertificateTrust.swift",
		"../../swifterpm/Sources/swifterpm/CertificateTrust.swift",
		"../../cas-plugin/src/certificate_trust.rs",
		"../../atlas-native/auth/src/certificate_trust.rs",
		"../../atlas-native/ios/Sources/AtlasCertificateTrust.swift",
		"../../atlas-native/android/src/dev/tuist/atlas/AtlasCertificateTrust.kt",
		"../../gradle/src/main/kotlin/dev/tuist/gradle/CertificateTrust.kt",
		"../../android/app/src/main/java/dev/tuist/app/data/network/CertificateTrust.kt",
	} {
		module := read(t, path)
		actual := map[string]bool{}
		for _, hash := range regexp.MustCompile(`"([a-f0-9]{64})"`).FindAllSubmatch(module, -1) {
			if actual[string(hash[1])] {
				t.Fatalf("duplicated client policy key in %s", path)
			}
			actual[string(hash[1])] = true
		}
		if !reflect.DeepEqual(expected, actual) {
			t.Fatalf("client deny list differs from policy.json in %s", path)
		}
	}
	for _, path := range []string{
		"../../server/lib/tuist/application/certificate_trust.ex",
		"../../tuist_ex/lib/tuist_ex/certificate_trust.ex",
	} {
		module := read(t, path)
		block := regexp.MustCompile(`(?s)@blocked\s+MapSet\.new\(\s*~w\((.*?)\)\s*\)`).FindSubmatch(module)
		if len(block) != 2 {
			t.Fatalf("cannot establish OTP deny list in %s", path)
		}
		actual := map[string]bool{}
		for _, hash := range strings.Fields(string(block[1])) {
			if actual[hash] {
				t.Fatalf("duplicated OTP key in %s", path)
			}
			actual[hash] = true
		}
		if !reflect.DeepEqual(expected, actual) {
			t.Fatalf("OTP deny list differs from policy.json in %s", path)
		}
	}
}

func TestRustClientPolicyAndFactoryWiring(t *testing.T) {
	var policy struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil {
		t.Fatal(err)
	}
	marker := regexp.MustCompile(`(?m)^pub const POLICY_ID: &str = "([^"]+)";`).FindSubmatch(read(t, "../../cas-plugin/src/certificate_trust.rs"))
	if policy.ID == "" || len(marker) != 2 || string(marker[1]) != policy.ID {
		t.Fatal("proxy startup policy marker differs from policy.json")
	}
	if !bytes.Equal(read(t, "../../cas-plugin/src/certificate_trust.rs"), read(t, "../../atlas-native/auth/src/certificate_trust.rs")) {
		t.Fatal("independently embedded Rust verifiers must stay synchronized")
	}
	paths, err := filepath.Glob("../../atlas-native/auth/src/*.rs")
	if err != nil {
		t.Fatal(err)
	}
	builders := regexp.MustCompile(`Client::builder\(\)`)
	protected := regexp.MustCompile(`Client::builder\(\)\s*\.use_preconfigured_tls\(config\)`)
	count := 0
	for _, path := range paths {
		if strings.HasSuffix(path, "_tests.rs") {
			continue
		}
		production := bytes.SplitN(read(t, path), []byte("#[cfg(test)]"), 2)[0]
		actual := len(builders.FindAll(production, -1))
		if actual != len(protected.FindAll(production, -1)) || bytes.Contains(production, []byte("Client::new(")) {
			t.Fatalf("unprotected Atlas HTTP factory in %s", path)
		}
		count += actual
		for _, forbidden := range []string{"connect_async(", "connect_async_with_config(", "danger_accept_invalid_"} {
			if bytes.Contains(production, []byte(forbidden)) {
				t.Fatalf("unprotected Rust TLS path %s in %s", forbidden, path)
			}
		}
	}
	if count != 1 {
		t.Fatal("review newly added/removed independent Atlas HTTP factories")
	}
	presence := read(t, "../../atlas-native/auth/src/presence.rs")
	if !bytes.Contains(presence, []byte("Some(tls)")) {
		t.Fatal("presence must supply the protected TLS connector")
	}
	for _, root := range []string{"../../atlas-native/ios/Sources", "../../atlas-native/android/src"} {
		err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() || (!strings.HasSuffix(path, ".swift") && !strings.HasSuffix(path, ".kt")) {
				return nil
			}
			if entry.Name() == "AtlasCertificateTrust.swift" || entry.Name() == "AtlasCertificateTrust.kt" {
				return nil
			}
			production := bytes.ReplaceAll(read(t, path), []byte("AtlasCertificateTrust.openConnection("), nil)
			if regexp.MustCompile(`URLSession\.shared|URLSession\s*\(|AsyncImage\s*\(|\.openConnection\s*\(|OkHttpClient|\bSocket\s*\(|\b(?:WK)?WebView\s*\(|\bNWConnection\s*\(|\b(?:Data|String)\s*\(\s*contentsOf\s*:|\.openStream\s*\(|\.readBytes\s*\(`).Match(production) {
				t.Fatalf("independent unprotected native transport in %s", path)
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func TestPinnedSDKsRequireQualification(t *testing.T) {
	// An explicitly qualified allowlist, not an ordering comparison. In particular,
	// Go 1.27.1 accepts a compromised intermediate. Qualify replacements first.
	qualified := map[string]bool{"1.26.10": true}
	expected := os.Getenv("TRUST_EXPECTED_GO_SDK")
	if expected == "" {
		expected = runtime.Version()
	}
	if len(qualified) != 1 || !qualified[strings.TrimPrefix(expected, "go")] {
		t.Fatal("the allowlist must match the behaviorally probed CI SDK")
	}
	patch := regexp.MustCompile(`^([0-9]+\.[0-9]+\.[0-9]+)(?:$|-)`)
	mise := regexp.MustCompile(`(?m)^\s*["']?go["']?\s*=\s*["']([^"']+)["']`)
	arg := regexp.MustCompile(`(?m)^ARG GO_VERSION=(\S+)\s*$`)
	image := regexp.MustCompile(`(?m)^FROM[^\n]*?golang:([^\s@]+)`)
	found := 0
	list := exec.Command("git", "ls-files", "-co", "--exclude-standard", "-z")
	list.Dir = "../.."
	files, err := list.Output()
	if err != nil {
		t.Fatal(err)
	}
	for _, relative := range strings.Split(string(files), "\x00") {
		if relative == "" {
			continue
		}
		path := filepath.Join("../..", relative)
		var pins []string
		name := strings.ToLower(filepath.Base(path))
		if name == "go.mod" || name == "go.work" {
			for _, match := range regexp.MustCompile(`(?m)^(go\s+|toolchain go)(\S+)`).FindAllSubmatch(read(t, path), -1) {
				// The benchmark keeps its language defaults, not an old SDK.
				if relative == "kura/test/e2e/grpc-upload-throughput/client/go.mod" && string(match[1]) == "go " && string(match[2]) == "1.25.0" {
					continue
				}
				pins = append(pins, string(match[2]))
			}
		} else if strings.HasPrefix(relative, ".github/workflows/") && (strings.HasSuffix(name, ".yml") || strings.HasSuffix(name, ".yaml")) {
			data := read(t, path)
			for _, match := range regexp.MustCompile(`(?m)^\s+go-version:\s*['"]?([^'"\s]+)`).FindAllSubmatch(data, -1) {
				pins = append(pins, string(match[1]))
			}
			for _, match := range regexp.MustCompile(`(?m)^\s+go-version-file:\s*['"]?([^'"\s]+)`).FindAllSubmatch(data, -1) {
				module := read(t, filepath.Join("../..", string(match[1])))
				directive := regexp.MustCompile(`(?m)^go (\S+)`).FindSubmatch(module)
				if len(directive) != 2 || !qualified[string(directive[1])] {
					t.Errorf("unqualified go-version-file in %s", path)
				}
			}
		} else if name == "mise.toml" || name == ".mise.toml" {
			data := read(t, path)
			matches := mise.FindAllSubmatch(data, -1)
			if len(regexp.MustCompile(`(?m)^\s*["']?go["']?\s*=`).FindAll(data, -1)) != len(matches) {
				t.Errorf("Go SDK needs an explicit patch pin in %s", path)
			}
			for _, match := range matches {
				pin := string(match[1])
				pins = append(pins, pin)
				lockPath := filepath.Join(filepath.Dir(path), "mise.lock")
				lock, err := os.ReadFile(lockPath)
				if os.IsNotExist(err) {
					continue
				}
				if err != nil {
					t.Fatal(err)
				}
				section := regexp.MustCompile(`(?ms)^\[\[tools\.go\]\]\s*\n(.*?)(?:^\[\[tools\.|\z)`).FindSubmatch(lock)
				if len(section) != 2 || !bytes.Contains(section[1], []byte(`version = "`+pin+`"`)) {
					t.Errorf("Go SDK lock does not match %s in %s", pin, lockPath)
				}
				if len(section) == 2 {
					for _, entry := range regexp.MustCompile(`(?m)^url = "https://dl\.google\.com/go/go([^"/]+)\.(?:linux|darwin|windows)-`).FindAllSubmatch(section[1], -1) {
						if string(entry[1]) != pin {
							t.Errorf("Go SDK download does not match %s in %s", pin, lockPath)
						}
					}
				}
			}
		} else if strings.HasPrefix(name, "dockerfile") && !strings.HasSuffix(name, "dockerignore") {
			data := read(t, path)
			args := arg.FindAllSubmatch(data, -1)
			for _, match := range args {
				pin := string(match[1])
				if filepath.ToSlash(path) == "../../grafana-datasource/.config/Dockerfile" {
					// The generated harness must not be hand-edited. Its supported
					// Compose entrypoint overrides the old generator default.
					compose := read(t, "../../grafana-datasource/docker-compose.yaml")
					override := regexp.MustCompile(`(?m)^\s+GO_VERSION: ['"]?([0-9]+\.[0-9]+\.[0-9]+)['"]?\s*$`).FindSubmatch(compose)
					if len(override) != 2 || !bytes.Contains(compose, []byte(".config/docker-compose-base.yaml")) {
						t.Fatal("generated Grafana harness needs a qualified Compose SDK override")
					}
					pin = string(override[1])
				}
				pins = append(pins, pin)
			}
			for _, match := range image.FindAllSubmatch(data, -1) {
				if strings.HasPrefix(string(match[1]), "${GO_VERSION}-") && len(args) == 1 {
					continue
				}
				pins = append(pins, string(match[1]))
			}
		}
		for _, pin := range pins {
			match := patch.FindStringSubmatch(pin)
			if len(match) != 2 || !qualified[match[1]] {
				t.Errorf("unqualified/floating Go SDK %q in %s", pin, path)
			}
			found++
		}
	}
	if found == 0 {
		t.Fatal("no SDK pins checked")
	}
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
	write(t, source, append(append([]byte{}, bad...), good...))
	command(t, false, "bash", "pem-store.sh", "check", source)
	command(t, true, "bash", "pem-store.sh", "filter", source, destination)
	command(t, true, "bash", "pem-store.sh", "check", destination)
	if !bytes.Equal(read(t, destination), good) {
		t.Fatal("filter changed the unrelated positive root")
	}
	write(t, source, bad)
	command(t, false, "bash", "pem-store.sh", "filter", source, destination)
	if !bytes.Equal(read(t, destination), good) {
		t.Fatal("failed filter replaced destination")
	}
	for _, invalid := range [][]byte{[]byte("not a store"), append(bad, []byte("-----BEGIN PRIVATE KEY-----\nidentity\n-----END PRIVATE KEY-----\n")...), bytes.ReplaceAll(bad, []byte("CERTIFICATE"), []byte("TRUSTED CERTIFICATE"))} {
		write(t, source, invalid)
		command(t, false, "bash", "pem-store.sh", "filter", source, destination)
		if !bytes.Equal(read(t, destination), good) {
			t.Fatal("failed filter replaced destination")
		}
	}
}

func TestPublicJavaStoreFiltering(t *testing.T) {
	good, bad := fixtures(t)
	work := t.TempDir()
	store := filepath.Join(work, "cacerts")
	for alias, data := range map[string][]byte{"positive root": good, "blocked root": bad} {
		file := filepath.Join(work, alias+".pem")
		write(t, file, data)
		command(t, true, "keytool", "-importcert", "-noprompt", "-storetype", "JKS", "-keystore", store, "-storepass", "changeit", "-alias", alias, "-file", file)
	}
	command(t, false, "bash", "java-store.sh", "check", store)
	command(t, true, "bash", "java-store.sh", "filter", store)
	command(t, true, "bash", "java-store.sh", "check", store)
	command(t, true, "keytool", "-list", "-keystore", store, "-storepass", "changeit", "-alias", "positive root")
	command(t, false, "keytool", "-list", "-keystore", store, "-storepass", "changeit", "-alias", "blocked root")
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
	home := os.Getenv("JAVA_HOME")
	if home == "" {
		properties := command(t, true, "java", "-XshowSettings:properties", "-version")
		match := regexp.MustCompile(`(?m)^\s*java.home = (.+)$`).FindSubmatch(properties)
		if len(match) != 2 {
			t.Fatal("cannot establish the SDK cacerts path")
		}
		home = string(match[1])
	}
	work := t.TempDir()
	source, store := filepath.Join(work, "sdk-cacerts"), filepath.Join(work, "cacerts.p12")
	write(t, source, read(t, filepath.Join(home, "lib/security/cacerts")))
	// Exercise the production passwordless PKCS12 contract even on SDKs whose
	// installed source store still uses JKS. All input certificates are public.
	command(t, true, "keytool", "-J-Dkeystore.pkcs12.certProtectionAlgorithm=NONE", "-J-Dkeystore.pkcs12.macAlgorithm=NONE", "-importkeystore", "-noprompt", "-srckeystore", source, "-srcstorepass", "changeit", "-destkeystore", store, "-deststoretype", "PKCS12", "-deststorepass", "changeit")
	_, bad := fixtures(t)
	file := filepath.Join(work, "blocked.pem")
	write(t, file, bad)
	command(t, true, "keytool", "-importcert", "-noprompt", "-keystore", store, "-storepass", "changeit", "-alias", "tuist-blocked-control", "-file", file)
	all := command(t, true, "keytool", "-list", "-rfc", "-keystore", store, "-storepass", "changeit")
	var policy struct {
		Hashes []string `json:"distrusted_spki_sha256"`
	}
	if err := json.Unmarshal(policyJSON, &policy); err != nil {
		t.Fatal(err)
	}
	blocked := map[string]bool{}
	for _, hash := range policy.Hashes {
		blocked[hash] = true
	}
	kept := 0
	for block, rest := pem.Decode(all); block != nil; block, rest = pem.Decode(rest) {
		certificate, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			t.Fatal(err)
		}
		if !blocked[spki(certificate)] {
			kept++
		}
	}
	if kept == 0 {
		t.Fatal("missing unrelated positive SDK anchors")
	}
	command(t, true, "bash", "java-store.sh", "filter", store)
	// No -storepass and nil stdin: the default JSSE load must still see anchors.
	listing := command(t, true, "keytool", "-J-Duser.language=en", "-J-Duser.country=US", "-list", "-keystore", store)
	count := regexp.MustCompile(`Your keystore contains ([0-9]+) entr`).FindSubmatch(listing)
	if len(count) != 2 {
		t.Fatalf("cannot establish passwordless entry count: %s", listing)
	}
	actual, err := strconv.Atoi(string(count[1]))
	if err != nil || actual != kept || !bytes.Contains(listing, []byte("PKCS12")) {
		t.Fatalf("passwordless PKCS12 lost anchors: got %d, want %d", actual, kept)
	}
}

func TestJavaPrivateIdentityIsNeverRewritten(t *testing.T) {
	store := filepath.Join(t.TempDir(), "identity.p12")
	command(t, true, "keytool", "-genkeypair", "-keyalg", "EC", "-groupname", "secp256r1", "-dname", "CN=test", "-validity", "1", "-keystore", store, "-storepass", "changeit", "-keypass", "changeit", "-alias", "client")
	before := read(t, store)
	command(t, false, "bash", "java-store.sh", "filter", store)
	if !bytes.Equal(before, read(t, store)) {
		t.Fatal("private identity store was changed")
	}
}

func TestReplacementGuard(t *testing.T) {
	if _, err := exec.LookPath("jq"); err != nil {
		t.Fatal("jq is required for the deployment guard")
	}
	work := t.TempDir()
	kubectl := filepath.Join(work, "kubectl")
	write(t, kubectl, []byte("#!/bin/sh\nprintf '%s' \"$GUARD_FIXTURE\"\nexit \"${GUARD_EXIT:-0}\"\n"))
	if err := os.Chmod(kubectl, 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", work+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, component := range []string{"management-tailscale", "hccm"} {
		t.Run(component, func(t *testing.T) {
			t.Setenv("GUARD_FIXTURE", "")
			command(t, true, "bash", "guard.sh", component)
			manifest, pattern := "../../infra/k8s/mgmt/tailscale.yaml", `(?m)^\s+image: (\S+)\s*$`
			if component == "hccm" {
				manifest, pattern = "../../infra/k8s/mgmt/bootstrap/hccm-values.yaml", `(?m)^  tag: (\S+)\s*$`
			}
			match := regexp.MustCompile(pattern).FindAllSubmatch(read(t, manifest), -1)
			if len(match) != 1 {
				t.Fatal("cannot establish desired image")
			}
			desired := string(match[0][1])
			if component == "hccm" {
				desired = "docker.io/hetznercloud/hcloud-cloud-controller-manager:" + desired
			}
			t.Setenv("GUARD_FIXTURE", fmt.Sprintf(`{"spec":{"template":{"spec":{"containers":[{"image":%q}]}}}}`, desired))
			command(t, true, "bash", "guard.sh", component)
			t.Setenv("GUARD_FIXTURE", fmt.Sprintf(`{"spec":{"template":{"spec":{"containers":[{"image":%q},{"image":"sidecar"}]}}}}`, desired))
			command(t, false, "bash", "guard.sh", component)
			command(t, true, "bash", "guard.sh", component, "--acknowledged")
			t.Setenv("GUARD_FIXTURE", `{"spec":{"template":{"spec":{"containers":[{"image":"old-image"}]}}}}`)
			command(t, false, "bash", "guard.sh", component)
			command(t, true, "bash", "guard.sh", component, "--acknowledged")
			t.Setenv("GUARD_FIXTURE", `{"invalid":"deployment"}`)
			command(t, false, "bash", "guard.sh", component, "--acknowledged")
			t.Setenv("GUARD_EXIT", "1")
			command(t, false, "bash", "guard.sh", component, "--acknowledged")
		})
	}
}
