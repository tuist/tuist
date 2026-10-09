package nftables

import (
	"context"
	"flag"
	"net/netip"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
)

var update = flag.Bool("update", false, "rewrite golden files")

func defaultOptions(t *testing.T) Options {
	t.Helper()
	excluded, err := config.ParseCIDRList(config.DefaultExcludedCIDRs)
	if err != nil {
		t.Fatal(err)
	}
	return Options{
		TunnelInterface: config.InterfaceName,
		OutInterface:    "eth0",
		TunnelAddress:   netip.MustParseAddr("198.18.0.1"),
		HealthPort:      config.HealthPort,
		PeerCIDR:        netip.MustParsePrefix("100.64.0.0/10"),
		ExcludedCIDRs:   excluded,
		SNAT:            config.SNAT{Mode: config.SNATMasquerade},
	}
}

func assertGolden(t *testing.T, name, got string) {
	t.Helper()
	path := filepath.Join("testdata", name)
	if *update {
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read golden (run go test ./internal/nftables -update to create it): %v", err)
	}
	if got != string(want) {
		t.Fatalf("ruleset differs from %s:\n--- got ---\n%s\n--- want ---\n%s", path, got, want)
	}
}

func TestRenderMasquerade(t *testing.T) {
	assertGolden(t, "masquerade.nft", Render(defaultOptions(t)))
}

func TestRenderAddress(t *testing.T) {
	opts := defaultOptions(t)
	opts.OutInterface = "ens3"
	opts.SNAT = config.SNAT{Mode: config.SNATAddress, Address: netip.MustParseAddr("203.0.113.7")}
	opts.ExcludedCIDRs = append(opts.ExcludedCIDRs,
		netip.MustParsePrefix("10.244.0.0/16"),
		netip.MustParsePrefix("198.51.100.0/24"),
		netip.MustParsePrefix("fd00::/8"),
	)
	assertGolden(t, "address.nft", Render(opts))
}

func TestNormalizeExcludedAlwaysCoversPeersAndTunnel(t *testing.T) {
	opts := defaultOptions(t)
	opts.ExcludedCIDRs = []netip.Prefix{netip.MustParsePrefix("192.168.0.0/16")}
	got := normalizeExcluded(opts)
	want := []netip.Prefix{
		netip.MustParsePrefix("100.64.0.0/10"),
		netip.MustParsePrefix("192.168.0.0/16"),
		netip.MustParsePrefix("198.18.0.1/32"),
	}
	if len(got) != len(want) {
		t.Fatalf("normalizeExcluded = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("normalizeExcluded = %v, want %v", got, want)
		}
	}
}

func TestNormalizeExcludedRemovesCoveredPrefixes(t *testing.T) {
	opts := defaultOptions(t)
	opts.ExcludedCIDRs = []netip.Prefix{
		netip.MustParsePrefix("10.96.0.0/12"),
		netip.MustParsePrefix("10.0.0.0/8"),
		netip.MustParsePrefix("10.0.0.0/8"),
		netip.MustParsePrefix("10.244.1.0/24"),
		netip.MustParsePrefix("11.0.0.0/8"),
	}
	got := normalizeExcluded(opts)
	for _, prefix := range got {
		if prefix.String() == "10.96.0.0/12" || prefix.String() == "10.244.1.0/24" {
			t.Fatalf("covered prefix %s kept: %v", prefix, got)
		}
	}
	count := 0
	for _, prefix := range got {
		if prefix.String() == "10.0.0.0/8" {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("10.0.0.0/8 appears %d times: %v", count, got)
	}
}

func TestRenderNeverForwardsBetweenPeers(t *testing.T) {
	ruleset := Render(defaultOptions(t))
	if !strings.Contains(ruleset, "oifname \"wg0\" drop") {
		t.Fatalf("ruleset does not drop new traffic into wg0:\n%s", ruleset)
	}
	if strings.Contains(ruleset, "flush ruleset") {
		t.Fatalf("ruleset must only touch its own table")
	}
}

func TestExecApply(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell script stub")
	}
	dir := t.TempDir()
	captured := filepath.Join(dir, "captured")
	stub := filepath.Join(dir, "nft")
	script := "#!/bin/sh\n[ \"$1\" = \"-f\" ] && [ \"$2\" = \"-" + "\" ] || exit 3\ncat > " + captured + "\n"
	if err := os.WriteFile(stub, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := (Exec{Binary: stub}).Apply(context.Background(), "table inet x\n"); err != nil {
		t.Fatalf("Apply: %v", err)
	}
	got, err := os.ReadFile(captured)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "table inet x\n" {
		t.Fatalf("stdin = %q", got)
	}

	failing := filepath.Join(dir, "nft-fail")
	if err := os.WriteFile(failing, []byte("#!/bin/sh\necho 'Error: syntax error' >&2\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	err = (Exec{Binary: failing}).Apply(context.Background(), "x")
	if err == nil || !strings.Contains(err.Error(), "syntax error") {
		t.Fatalf("Apply error = %v", err)
	}
}
