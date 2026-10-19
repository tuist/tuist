package sysconfig

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseCmdline(t *testing.T) {
	values := ParseCmdline("console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw sbx.dns=10.128.0.10,10.128.0.11 sbx.hostname=sbx-abc")
	if values["root"] != "/dev/vda" || values["rw"] != "" {
		t.Fatalf("unexpected parse: %+v", values)
	}
	if HostnameFromCmdline(values) != "sbx-abc" {
		t.Fatalf("unexpected hostname: %q", HostnameFromCmdline(values))
	}
	if got := DNSFromCmdline(values); !reflect.DeepEqual(got, []string{"10.128.0.10", "10.128.0.11"}) {
		t.Fatalf("unexpected dns: %v", got)
	}
}

func TestCmdlineDefaults(t *testing.T) {
	values := ParseCmdline("console=ttyS0 sbx.dns=")
	if HostnameFromCmdline(values) != DefaultHostname {
		t.Fatalf("expected default hostname, got %q", HostnameFromCmdline(values))
	}
	if got := DNSFromCmdline(values); !reflect.DeepEqual(got, FallbackDNS) {
		t.Fatalf("expected fallback dns, got %v", got)
	}
}

func TestWritesReplaceSymlinks(t *testing.T) {
	root := t.TempDir()
	etc := filepath.Join(root, "etc")
	if err := os.MkdirAll(etc, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/nonexistent/resolv.conf", filepath.Join(etc, "resolv.conf")); err != nil {
		t.Fatal(err)
	}

	if err := WriteResolvConf(root, []string{"10.0.0.1", "1.1.1.1"}); err != nil {
		t.Fatal(err)
	}
	if err := WriteHostname(root, "sbx-1"); err != nil {
		t.Fatal(err)
	}
	if err := WriteHosts(root, "sbx-1"); err != nil {
		t.Fatal(err)
	}

	resolv, err := os.ReadFile(filepath.Join(etc, "resolv.conf"))
	if err != nil {
		t.Fatal(err)
	}
	if string(resolv) != "nameserver 10.0.0.1\nnameserver 1.1.1.1\noptions edns0 trust-ad\n" {
		t.Fatalf("unexpected resolv.conf: %q", resolv)
	}
	if info, err := os.Lstat(filepath.Join(etc, "resolv.conf")); err != nil || info.Mode()&os.ModeSymlink != 0 {
		t.Fatalf("resolv.conf should be a regular file now (%v)", err)
	}
	hostname, _ := os.ReadFile(filepath.Join(etc, "hostname"))
	if string(hostname) != "sbx-1\n" {
		t.Fatalf("unexpected hostname file: %q", hostname)
	}
	hosts, _ := os.ReadFile(filepath.Join(etc, "hosts"))
	if string(hosts) != "127.0.0.1\tlocalhost\n127.0.1.1\tsbx-1\n::1\tlocalhost ip6-localhost ip6-loopback\n" {
		t.Fatalf("unexpected hosts file: %q", hosts)
	}
}
