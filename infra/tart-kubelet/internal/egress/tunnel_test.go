package egress

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const testGatewayKey = "HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw="

func validTunnelConfig() TunnelConfig {
	return TunnelConfig{
		Gateway: "dedicated-1", Index: 3, Endpoint: "203.0.113.10:51820", GatewayPublicKey: testGatewayKey,
		StateDir: "/var/db/tuist-egress", StatusDir: "/var/run/tuist-egress",
	}
}

func TestTunnelConfigValidate(t *testing.T) {
	if err := validTunnelConfig().Validate(); err != nil {
		t.Fatal(err)
	}
	for name, mutate := range map[string]func(*TunnelConfig){
		"bad name":      func(c *TunnelConfig) { c.Gateway = "Bad" },
		"bad index":     func(c *TunnelConfig) { c.Index = 100 },
		"hostname":      func(c *TunnelConfig) { c.Endpoint = "gateway.example.com:51820" },
		"ipv6":          func(c *TunnelConfig) { c.Endpoint = "[2001:db8::1]:51820" },
		"no port":       func(c *TunnelConfig) { c.Endpoint = "203.0.113.10" },
		"bad key":       func(c *TunnelConfig) { c.GatewayPublicKey = "short" },
		"no state dir":  func(c *TunnelConfig) { c.StateDir = "" },
		"no status dir": func(c *TunnelConfig) { c.StatusDir = "" },
	} {
		c := validTunnelConfig()
		mutate(&c)
		if err := c.Validate(); err == nil {
			t.Fatalf("%s accepted", name)
		}
	}
}

func TestDeviceConfig(t *testing.T) {
	private, err := generatePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	config, err := deviceConfig(private, validTunnelConfig())
	if err != nil {
		t.Fatal(err)
	}
	gateway, _ := ParseKey(testGatewayKey)
	for _, line := range []string{
		"private_key=" + private.Hex(),
		"public_key=" + gateway.Hex(),
		"endpoint=203.0.113.10:51820",
		"persistent_keepalive_interval=25",
		"allowed_ip=0.0.0.0/0",
		"replace_peers=true",
	} {
		if !strings.Contains(config, line+"\n") {
			t.Fatalf("config missing %q:\n%s", line, config)
		}
	}
}

func TestTunnelAddressing(t *testing.T) {
	local, gateway := TunnelAddresses(3)
	if local != "198.18.3.2" || gateway != "198.18.3.1" || InterfaceName(3) != "utun103" {
		t.Fatalf("got %s %s %s", local, gateway, InterfaceName(3))
	}
}

func TestEnsureHostKeyIsStable(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "state")
	first, err := EnsureHostKey(dir)
	if err != nil {
		t.Fatal(err)
	}
	second, err := EnsureHostKey(dir)
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatal("host key changed between runs")
	}
	info, err := os.Stat(filepath.Join(dir, privateKeyFile))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("private key mode = %v", info.Mode().Perm())
	}
	publicData, err := os.ReadFile(filepath.Join(dir, publicKeyFile))
	if err != nil {
		t.Fatal(err)
	}
	public, err := first.PublicKey()
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(publicData)) != public.String() {
		t.Fatal("public key file doesn't match the private key")
	}
}

func TestPublicKeyKnownVector(t *testing.T) {
	// RFC 7748 section 6.1 (Alice).
	private := Key{
		0x77, 0x07, 0x6d, 0x0a, 0x73, 0x18, 0xa5, 0x7d, 0x3c, 0x16, 0xc1, 0x72, 0x51, 0xb2, 0x66, 0x45,
		0xdf, 0x4c, 0x2f, 0x87, 0xeb, 0xc0, 0x99, 0x2a, 0xb1, 0x77, 0xfb, 0xa5, 0x1d, 0xb9, 0x2c, 0x2a,
	}
	public, err := private.PublicKey()
	if err != nil {
		t.Fatal(err)
	}
	if public.Hex() != "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a" {
		t.Fatalf("public = %s", public.Hex())
	}
}

type fakeDevice struct{ uapi string }

func (d fakeDevice) IpcGet() (string, error) { return d.uapi, nil }

func TestReportStatus(t *testing.T) {
	dev := fakeDevice{uapi: "public_key=ab\nlast_handshake_time_sec=1799999990\nrx_bytes=12\ntx_bytes=34\n"}
	ok := reportStatus(context.Background(), validTunnelConfig(), dev, func(context.Context) error { return nil }, now)
	if !ok.ProbeOK || ok.LastHandshakeUnix != 1799999990 || ok.RxBytes != 12 || ok.TxBytes != 34 || ok.Interface != "utun103" || !ok.Healthy(now) {
		t.Fatalf("status = %+v", ok)
	}
	failed := reportStatus(context.Background(), validTunnelConfig(), dev, func(context.Context) error { return errors.New("timeout") }, now)
	if failed.ProbeOK || failed.ProbeError != "timeout" || failed.Healthy(now) {
		t.Fatalf("status = %+v", failed)
	}
	never := reportStatus(context.Background(), validTunnelConfig(), fakeDevice{uapi: "last_handshake_time_sec=0\n"}, func(context.Context) error { return nil }, now)
	if never.Healthy(now.Add(time.Second)) {
		t.Fatal("a tunnel that never completed a handshake reported healthy")
	}
}
