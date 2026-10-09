package config

import (
	"io"
	"net/netip"
	"strings"
	"testing"
	"time"
)

func TestParseDefaults(t *testing.T) {
	cfg, err := Parse([]string{"--gateway-name=g1", "--private-key-file=/etc/wg/key"}, io.Discard)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if cfg.GatewayName != "g1" || cfg.PrivateKeyFile != "/etc/wg/key" {
		t.Fatalf("unexpected identity: %+v", cfg)
	}
	if cfg.ListenPort != 51820 {
		t.Errorf("ListenPort = %d", cfg.ListenPort)
	}
	if cfg.TunnelAddress != netip.MustParsePrefix("198.18.0.1/32") {
		t.Errorf("TunnelAddress = %s", cfg.TunnelAddress)
	}
	if cfg.PeerCIDR != netip.MustParsePrefix("100.64.0.0/10") {
		t.Errorf("PeerCIDR = %s", cfg.PeerCIDR)
	}
	if len(cfg.ExcludedCIDRs) != 11 {
		t.Errorf("ExcludedCIDRs = %v", cfg.ExcludedCIDRs)
	}
	if cfg.OutInterface != "eth0" {
		t.Errorf("OutInterface = %s", cfg.OutInterface)
	}
	if cfg.SNAT.Mode != SNATMasquerade {
		t.Errorf("SNAT = %s", cfg.SNAT)
	}
	if cfg.ProbeAddr != ":8081" || cfg.MetricsAddr != ":9090" {
		t.Errorf("addrs = %s %s", cfg.ProbeAddr, cfg.MetricsAddr)
	}
	if cfg.ResyncInterval != 30*time.Second {
		t.Errorf("ResyncInterval = %s", cfg.ResyncInterval)
	}
}

func TestParseOverrides(t *testing.T) {
	cfg, err := Parse([]string{
		"--gateway-name=g2",
		"--private-key-file=/k",
		"--listen-port=51900",
		"--excluded-cidrs=10.0.0.0/8",
		"--extra-excluded-cidrs=10.244.0.0/16, 10.96.0.0/12,fd00::/8",
		"--out-interface=ens3",
		"--snat=address:203.0.113.7",
	}, io.Discard)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if cfg.ListenPort != 51900 || cfg.OutInterface != "ens3" {
		t.Fatalf("unexpected: %+v", cfg)
	}
	want := []netip.Prefix{
		netip.MustParsePrefix("10.0.0.0/8"),
		netip.MustParsePrefix("10.244.0.0/16"),
		netip.MustParsePrefix("10.96.0.0/12"),
		netip.MustParsePrefix("fd00::/8"),
	}
	if len(cfg.ExcludedCIDRs) != len(want) {
		t.Fatalf("ExcludedCIDRs = %v", cfg.ExcludedCIDRs)
	}
	for i := range want {
		if cfg.ExcludedCIDRs[i] != want[i] {
			t.Errorf("ExcludedCIDRs[%d] = %s, want %s", i, cfg.ExcludedCIDRs[i], want[i])
		}
	}
	if cfg.SNAT.Mode != SNATAddress || cfg.SNAT.Address != netip.MustParseAddr("203.0.113.7") {
		t.Errorf("SNAT = %s", cfg.SNAT)
	}
}

func TestParseRejectsInvalid(t *testing.T) {
	cases := map[string]struct {
		args []string
		want string
	}{
		"missing name":        {[]string{"--private-key-file=/k"}, "--gateway-name is required"},
		"missing key":         {[]string{"--gateway-name=g"}, "--private-key-file is required"},
		"port zero":           {[]string{"--gateway-name=g", "--private-key-file=/k", "--listen-port=0"}, "--listen-port"},
		"ipv6 tunnel":         {[]string{"--gateway-name=g", "--private-key-file=/k", "--tunnel-address=fd00::1/128"}, "--tunnel-address"},
		"tunnel inside peers": {[]string{"--gateway-name=g", "--private-key-file=/k", "--tunnel-address=100.64.0.1/32"}, "outside --peer-cidr"},
		"bad excluded":        {[]string{"--gateway-name=g", "--private-key-file=/k", "--excluded-cidrs=10.0.0.0/8,nope"}, "invalid CIDR \"nope\""},
		"bad snat":            {[]string{"--gateway-name=g", "--private-key-file=/k", "--snat=snat"}, "--snat"},
		"out is wg0":          {[]string{"--gateway-name=g", "--private-key-file=/k", "--out-interface=wg0"}, "--out-interface"},
		"quoted out":          {[]string{"--gateway-name=g", "--private-key-file=/k", "--out-interface=eth0\" accept"}, "--out-interface"},
		"short resync":        {[]string{"--gateway-name=g", "--private-key-file=/k", "--resync-interval=10ms"}, "--resync-interval"},
		"positional":          {[]string{"--gateway-name=g", "--private-key-file=/k", "extra"}, "unexpected arguments"},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := Parse(tc.args, io.Discard)
			if err == nil {
				t.Fatal("expected an error")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error %q does not mention %q", err, tc.want)
			}
		})
	}
}

func TestParseSNAT(t *testing.T) {
	cases := map[string]struct {
		value   string
		want    SNAT
		wantErr bool
	}{
		"masquerade":     {value: "masquerade", want: SNAT{Mode: SNATMasquerade}},
		"address":        {value: "address:192.0.2.10", want: SNAT{Mode: SNATAddress, Address: netip.MustParseAddr("192.0.2.10")}},
		"ipv6 address":   {value: "address:2001:db8::1", wantErr: true},
		"zero address":   {value: "address:0.0.0.0", wantErr: true},
		"empty address":  {value: "address:", wantErr: true},
		"unknown":        {value: "snat", wantErr: true},
		"cased mode":     {value: "Masquerade", wantErr: true},
		"address prefix": {value: "address:192.0.2.0/24", wantErr: true},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			got, err := ParseSNAT(tc.value)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got %s", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseSNAT: %v", err)
			}
			if got != tc.want {
				t.Fatalf("got %s, want %s", got, tc.want)
			}
		})
	}
}

func TestParsePerGatewayTunnelAddress(t *testing.T) {
	cfg, err := Parse([]string{"--gateway-name=g3", "--private-key-file=/k", "--tunnel-address=198.18.3.1/32"}, io.Discard)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if cfg.TunnelAddress != netip.MustParsePrefix("198.18.3.1/32") {
		t.Fatalf("TunnelAddress = %s", cfg.TunnelAddress)
	}
}
