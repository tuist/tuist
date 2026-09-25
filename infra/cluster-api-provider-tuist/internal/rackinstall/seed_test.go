package rackinstall

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
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

func TestIPXEScript(t *testing.T) {
	got := IPXEScript("http://192.168.50.1:8480/", "38:05:25:38:B5:B5")
	for _, want := range []string{
		"#!ipxe\n",
		"kernel http://192.168.50.1:8480/ubuntu/vmlinuz initrd=initrd ip=dhcp BOOTIF=01-38-05-25-38-b5-b5 url=http://192.168.50.1:8480/ubuntu/ubuntu.iso cloud-config-url=/dev/null autoinstall ds=nocloud-net;s=http://192.168.50.1:8480/hosts/38-05-25-38-b5-b5/ ---\n",
		"initrd --name initrd http://192.168.50.1:8480/ubuntu/initrd\nshim http://192.168.50.1:8480/ubuntu/shimx64.efi\nboot\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("script lacks %q:\n%s", want, got)
		}
	}
	if MetaData(edgeSeed()) != "instance-id: ber1-edge-ktest1cntrl\nlocal-hostname: ber1-edge\n" {
		t.Errorf("meta-data %q", MetaData(edgeSeed()))
	}
}

// The MS-01's Bluetooth driver dereferences NULL on a warm boot of the 6.8
// kernel, and a node's panic_on_oops turns that into a reboot loop, so an
// install keeps the driver out from its first boot.
func TestUserDataKeepsTheBluetoothDriverOut(t *testing.T) {
	_, seed := renderEdge(t)
	late := strings.Join(seed.Autoinstall.LateCommands, "\n")
	if !strings.Contains(late, "cat > /target/etc/modprobe.d/tuist-rack.conf <<'TUIST_EOF'\nblacklist btusb\nTUIST_EOF") {
		t.Fatalf("late-commands do not keep btusb out:\n%s", late)
	}
}

// An install gives the host the SSH host key the operator generated for it,
// and only that one, so the operator trusts the new install by its key rather
// than by whatever answers first.
func TestUserDataGivesTheHostTheOperatorsHostKey(t *testing.T) {
	key, err := NewHostKey()
	if err != nil {
		t.Fatal(err)
	}
	s := edgeSeed()
	s.HostKey = key
	out, err := UserData(s)
	if err != nil {
		t.Fatal(err)
	}
	var seed autoinstall
	if err := yaml.Unmarshal([]byte(out), &seed); err != nil {
		t.Fatal(err)
	}
	var command string
	for _, c := range seed.Autoinstall.LateCommands {
		if strings.Contains(c, "ssh_host_ed25519_key") {
			command = c
		}
	}
	if command == "" {
		t.Fatalf("no late-command writes the host key:\n%s", out)
	}

	target := t.TempDir()
	for _, dir := range []string{"etc/ssh", "etc/cloud/cloud.cfg.d"} {
		if err := os.MkdirAll(filepath.Join(target, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, generated := range []string{"ssh_host_rsa_key", "ssh_host_ecdsa_key.pub", "ssh_host_ed25519_key"} {
		if err := os.WriteFile(filepath.Join(target, "etc/ssh", generated), []byte("generated by the package\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	script := strings.ReplaceAll(command, "/target/", target+"/")
	if out, err := exec.Command("sh", "-euc", script).CombinedOutput(); err != nil {
		t.Fatalf("%v\n%s", err, out)
	}

	entries, _ := os.ReadDir(filepath.Join(target, "etc/ssh"))
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if strings.Join(names, " ") != "ssh_host_ed25519_key ssh_host_ed25519_key.pub" {
		t.Fatalf("host keys %v, want the operator's alone", names)
	}
	private, _ := os.ReadFile(filepath.Join(target, "etc/ssh/ssh_host_ed25519_key"))
	signer, err := ssh.ParsePrivateKey(private)
	if err != nil {
		t.Fatalf("the written host key does not parse: %v", err)
	}
	if got := ssh.FingerprintSHA256(signer.PublicKey()); got != key.Fingerprint {
		t.Fatalf("the written host key is %s, want %s", got, key.Fingerprint)
	}
	if info, _ := os.Stat(filepath.Join(target, "etc/ssh/ssh_host_ed25519_key")); info.Mode().Perm() != 0o600 {
		t.Fatalf("the private host key is %v", info.Mode().Perm())
	}
	public, _ := os.ReadFile(filepath.Join(target, "etc/ssh/ssh_host_ed25519_key.pub"))
	if strings.TrimSpace(string(public)) != key.Public {
		t.Fatalf("the public host key is %q", public)
	}
	cfg, _ := os.ReadFile(filepath.Join(target, "etc/cloud/cloud.cfg.d/99-tuist-ssh-host-key.cfg"))
	if string(cfg) != "ssh_deletekeys: false\nssh_genkeytypes: []\n" {
		t.Fatalf("cloud-init may replace the host key on first boot: %q", cfg)
	}
}

func TestUserDataRefusesAHostKeyThatIsNotOne(t *testing.T) {
	key, err := NewHostKey()
	if err != nil {
		t.Fatal(err)
	}
	for name, mutate := range map[string]func(*HostKey){
		"no public half":    func(k *HostKey) { k.Public = "" },
		"not a private key": func(k *HostKey) { k.Private = "ssh-ed25519 AAAA\n" },
		"quote":             func(k *HostKey) { k.Public = "ssh-ed25519 AAAA'" },
	} {
		s := edgeSeed()
		k := key
		mutate(&k)
		s.HostKey = k
		if _, err := UserData(s); err == nil {
			t.Errorf("%s: rendered", name)
		}
	}
}
