package rackinstall

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"sigs.k8s.io/yaml"
)

func TestSHA512CryptMatchesOpenSSL(t *testing.T) {
	for _, c := range []struct{ password, salt, want string }{
		{"Hello world!", "saltstring", "$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1"},
		{"x", "saltstring", "$6$saltstring$nk7Qohr7tOmwY2mX639VRP.Lyvj3uhcgpatqHuLC867qfSHKq1LDuKa/h7Es9Nv0aL08pbF.cnQlRqhaoKT/D."},
		{"a much longer password that crosses the sixty-four byte block boundary for sure, yes", "saltstring", "$6$saltstring$2ocw8zA.ZITqRu6Hmf5PP0JVI2HX4fe/DXKZeHUaUOZFLh1LHhIx5m5b/BclXMFIxJyEg5uHirQPGeYbipddo."},
		{"tuist", "sixteencharsalt!", "$6$sixteencharsalt!$7zK5btoqOiW8oQjlvxBNsKqeFYd6AsGF1fZ386c9FAOyDIHPVSNsgo9ZEGLZYI8g.evhUbRQk19qtJQctb2Rr."},
	} {
		if got := sha512Crypt(c.password, c.salt); got != c.want {
			t.Errorf("sha512Crypt(%q, %q) = %s, want %s", c.password, c.salt, got, c.want)
		}
	}
}

func TestHashPasswordUsesAFreshSalt(t *testing.T) {
	a, err := HashPassword("secret")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := HashPassword("secret")
	if a == b {
		t.Fatal("two hashes of one password share a salt")
	}
	m := regexp.MustCompile(`^\$6\$([./0-9A-Za-z]{16})\$[./0-9A-Za-z]{86}$`).FindStringSubmatch(a)
	if m == nil {
		t.Fatalf("hash %q is not $6$ with a 16-character salt", a)
	}
	if sha512Crypt("secret", m[1]) != a {
		t.Fatal("the hash does not verify")
	}
}

func edgeSeed() Seed {
	return Seed{
		Host:           "ber1-edge",
		Role:           "edge",
		User:           "tuist",
		PasswordHash:   "$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1",
		AuthorizedKeys: []string{"ssh-ed25519 AAAAFLEET fleet", "ssh-ed25519 AAAAHUMAN human"},
		TailnetTags:    []string{"tag:tuist-rack-edge"},
		TailnetKey:     "tskey-auth-kTEST1CNTRL-abc",
		TailnetKeyID:   "kTEST1CNTRL",
		Built:          time.Date(2026, 9, 23, 18, 0, 0, 0, time.UTC),
	}
}

type autoinstall struct {
	Autoinstall struct {
		Identity struct {
			Hostname, Username, Password string
		}
		SSH struct {
			AllowPW        bool     `json:"allow-pw"`
			AuthorizedKeys []string `json:"authorized-keys"`
		}
		Storage struct {
			Layout struct{ Name string }
		}
		Network struct {
			Ethernets map[string]struct {
				Match map[string]string
				DHCP4 bool `json:"dhcp4"`
			}
		}
		EarlyCommands []string `json:"early-commands"`
		LateCommands  []string `json:"late-commands"`
	}
}

func renderEdge(t *testing.T) (string, autoinstall) {
	t.Helper()
	out, err := UserData(edgeSeed())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(out, "#cloud-config\n") {
		t.Fatal("user-data is not a cloud-config")
	}
	var parsed autoinstall
	if err := yaml.Unmarshal([]byte(out), &parsed); err != nil {
		t.Fatalf("user-data is not YAML: %v", err)
	}
	return out, parsed
}

func TestUserDataInstallsTheHostWithTheFleetKey(t *testing.T) {
	_, seed := renderEdge(t)
	a := seed.Autoinstall
	if a.Identity.Hostname != "ber1-edge" || a.Identity.Username != "tuist" || !strings.HasPrefix(a.Identity.Password, "$6$") {
		t.Fatalf("identity %+v", a.Identity)
	}
	if a.SSH.AllowPW || len(a.SSH.AuthorizedKeys) != 2 || a.Storage.Layout.Name != "direct" {
		t.Fatalf("ssh %+v storage %+v", a.SSH, a.Storage)
	}
	if len(a.Network.Ethernets) != 1 || a.Network.Ethernets["uplinks"].Match["driver"] != "i40e" || !a.Network.Ethernets["uplinks"].DHCP4 {
		t.Fatalf("network %+v; only the SFP+ uplinks may be configured", a.Network)
	}
	late := strings.Join(a.LateCommands, "\n")
	for _, want := range []string{
		"NOPASSWD:ALL",
		"printf 'TAILNET_TAGS=%s\\n' 'tag:tuist-rack-edge'",
		"printf '%s\\n' 'tskey-auth-kTEST1CNTRL-abc' > /target/etc/tuist/tailnet-auth-key",
		"tailscale up --auth-key=\"file:$key\"",
		"systemctl enable tuist-tailnet-join.service",
		"'ber1-edge' 'edge' '2026-09-23T18:00:00Z' 'kTEST1CNTRL' > /target/etc/tuist-rack-node",
	} {
		if !strings.Contains(late, want) {
			t.Errorf("late-commands lack %q", want)
		}
	}
	early := strings.Join(a.EarlyCommands, "\n")
	for _, want := range []string{"grep -qx 'tailnet_key=kTEST1CNTRL' /run/tuist-prev/etc/tuist-rack-node", `efibootmgr -q -n "$entry"`, "reboot -f"} {
		if !strings.Contains(early, want) {
			t.Errorf("early-commands lack %q", want)
		}
	}
}

func TestUserDataCommandsAreValidShell(t *testing.T) {
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	_, seed := renderEdge(t)
	commands := append(append([]string{}, seed.Autoinstall.EarlyCommands...), seed.Autoinstall.LateCommands...)
	for i, command := range commands {
		path := filepath.Join(t.TempDir(), "command.sh")
		if err := os.WriteFile(path, []byte(command), 0o600); err != nil {
			t.Fatal(err)
		}
		if out, err := exec.Command(sh, "-n", path).CombinedOutput(); err != nil {
			t.Errorf("command %d: %v\n%s\n%s", i, err, out, command)
		}
	}
	join := seed.Autoinstall.LateCommands[3]
	script := join[strings.Index(join, "#!/usr/bin/env bash"):strings.Index(join, "TUIST_EOF\nchmod")]
	path := filepath.Join(t.TempDir(), "join.sh")
	if err := os.WriteFile(path, []byte(script), 0o600); err != nil {
		t.Fatal(err)
	}
	if bash, err := exec.LookPath("bash"); err == nil {
		if out, err := exec.Command(bash, "-n", path).CombinedOutput(); err != nil {
			t.Errorf("the first-boot join script: %v\n%s", err, out)
		}
	}
}

func TestUserDataRefusesWhatItCannotInstall(t *testing.T) {
	for name, mutate := range map[string]func(*Seed){
		"storage role":      func(s *Seed) { s.Role = "storage" },
		"unknown role":      func(s *Seed) { s.Role = "db" },
		"no tags":           func(s *Seed) { s.TailnetTags = nil },
		"client secret":     func(s *Seed) { s.TailnetKey = "tskey-client-oops" },
		"plaintext":         func(s *Seed) { s.PasswordHash = "hunter2" },
		"private key":       func(s *Seed) { s.AuthorizedKeys = []string{"-----BEGIN OPENSSH PRIVATE KEY-----"} },
		"no keys":           func(s *Seed) { s.AuthorizedKeys = nil },
		"quote in hostname": func(s *Seed) { s.Host = "ber1'edge" },
	} {
		s := edgeSeed()
		mutate(&s)
		if _, err := UserData(s); err == nil {
			t.Errorf("%s: rendered", name)
		}
	}
}

func TestGRUBConfig(t *testing.T) {
	got := GRUBConfig("http://192.168.50.1:8480/", "38:05:25:38:B5:B5", "ber1-svc")
	for _, want := range []string{
		"set timeout=0\n",
		`menuentry "Install ber1-svc" {`,
		`linux /ubuntu/vmlinuz ip=dhcp BOOTIF=01-38-05-25-38-b5-b5 url=http://192.168.50.1:8480/ubuntu/ubuntu.iso cloud-config-url=/dev/null autoinstall ds=nocloud-net\;s=http://192.168.50.1:8480/hosts/38-05-25-38-b5-b5/ ---`,
		"initrd /ubuntu/initrd\n}",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("script lacks %q:\n%s", want, got)
		}
	}
	if MetaData(edgeSeed()) != "instance-id: ber1-edge-ktest1cntrl\nlocal-hostname: ber1-edge\n" {
		t.Errorf("meta-data %q", MetaData(edgeSeed()))
	}
}
