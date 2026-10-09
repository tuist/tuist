package config

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"net/netip"
	"strings"
	"time"
)

const (
	InterfaceName = "wg0"
	HealthPort    = 8080
	MTU           = 1420
)

const DefaultExcludedCIDRs = "0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16,198.18.0.0/15,224.0.0.0/4,240.0.0.0/4"

type SNATMode int

const (
	SNATMasquerade SNATMode = iota
	SNATAddress
)

type SNAT struct {
	Mode    SNATMode
	Address netip.Addr
}

func (s SNAT) String() string {
	if s.Mode == SNATAddress {
		return "address:" + s.Address.String()
	}
	return "masquerade"
}

type Config struct {
	GatewayName    string
	PrivateKeyFile string
	ListenPort     int
	TunnelAddress  netip.Prefix
	PeerCIDR       netip.Prefix
	ExcludedCIDRs  []netip.Prefix
	OutInterface   string
	SNAT           SNAT
	ProbeAddr      string
	MetricsAddr    string
	ResyncInterval time.Duration
}

// Parse reads the command-line flags and validates them.
func Parse(args []string, output io.Writer) (Config, error) {
	fs := flag.NewFlagSet("runner-egress-gateway", flag.ContinueOnError)
	fs.SetOutput(output)

	gatewayName := fs.String("gateway-name", "", "name of the gateway, exported as the constant metrics label gateway (required)")
	privateKeyFile := fs.String("private-key-file", "", "file holding the base64 WireGuard private key (required)")
	listenPort := fs.Int("listen-port", 51820, "UDP port WireGuard listens on")
	tunnelAddress := fs.String("tunnel-address", "198.18.0.1/32", "IPv4 address of wg0; /healthz is served on it")
	peerCIDR := fs.String("peer-cidr", "100.64.0.0/10", "IPv4 range of peer inner addresses, routed to wg0")
	excludedCIDRs := fs.String("excluded-cidrs", DefaultExcludedCIDRs, "comma-separated destinations wg0 traffic is never forwarded to")
	extraExcludedCIDRs := fs.String("extra-excluded-cidrs", "", "comma-separated destinations added to --excluded-cidrs, such as cluster pod and service ranges")
	outInterface := fs.String("out-interface", "eth0", "interface forwarded traffic leaves through")
	snat := fs.String("snat", "masquerade", "source NAT for forwarded traffic: masquerade or address:<ipv4>")
	probeAddr := fs.String("probe-addr", ":8081", "listen address for /readyz and /livez")
	metricsAddr := fs.String("metrics-addr", ":9090", "listen address for Prometheus metrics")
	resyncInterval := fs.Duration("resync-interval", 30*time.Second, "interval at which the link, rules and peers are re-asserted")

	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}
	if fs.NArg() > 0 {
		return Config{}, fmt.Errorf("unexpected arguments: %s", strings.Join(fs.Args(), " "))
	}

	var errs []error
	cfg := Config{
		GatewayName:    strings.TrimSpace(*gatewayName),
		PrivateKeyFile: *privateKeyFile,
		ListenPort:     *listenPort,
		OutInterface:   *outInterface,
		ProbeAddr:      *probeAddr,
		MetricsAddr:    *metricsAddr,
		ResyncInterval: *resyncInterval,
	}

	if cfg.GatewayName == "" {
		errs = append(errs, errors.New("--gateway-name is required"))
	}
	if cfg.PrivateKeyFile == "" {
		errs = append(errs, errors.New("--private-key-file is required"))
	}
	if cfg.ListenPort < 1 || cfg.ListenPort > 65535 {
		errs = append(errs, fmt.Errorf("--listen-port must be between 1 and 65535, got %d", cfg.ListenPort))
	}
	if !validInterfaceName(cfg.OutInterface) {
		errs = append(errs, fmt.Errorf("--out-interface %q is not a valid interface name", cfg.OutInterface))
	} else if cfg.OutInterface == InterfaceName {
		errs = append(errs, fmt.Errorf("--out-interface must not be %s", InterfaceName))
	}
	if cfg.ResyncInterval < time.Second || cfg.ResyncInterval > time.Hour {
		errs = append(errs, fmt.Errorf("--resync-interval must be between 1s and 1h, got %s", cfg.ResyncInterval))
	}
	if cfg.ProbeAddr == "" {
		errs = append(errs, errors.New("--probe-addr is required"))
	}
	if cfg.MetricsAddr == "" {
		errs = append(errs, errors.New("--metrics-addr is required"))
	}

	tunnel, err := parseIPv4Prefix(*tunnelAddress)
	if err != nil {
		errs = append(errs, fmt.Errorf("--tunnel-address: %w", err))
	} else {
		cfg.TunnelAddress = tunnel
	}

	peers, err := parseIPv4Prefix(*peerCIDR)
	if err != nil {
		errs = append(errs, fmt.Errorf("--peer-cidr: %w", err))
	} else {
		cfg.PeerCIDR = peers.Masked()
	}

	if cfg.TunnelAddress.IsValid() && cfg.PeerCIDR.IsValid() && cfg.PeerCIDR.Contains(cfg.TunnelAddress.Addr()) {
		errs = append(errs, fmt.Errorf("--tunnel-address %s must be outside --peer-cidr %s", cfg.TunnelAddress, cfg.PeerCIDR))
	}

	excluded, err := ParseCIDRList(*excludedCIDRs)
	if err != nil {
		errs = append(errs, fmt.Errorf("--excluded-cidrs: %w", err))
	}
	extra, err := ParseCIDRList(*extraExcludedCIDRs)
	if err != nil {
		errs = append(errs, fmt.Errorf("--extra-excluded-cidrs: %w", err))
	}
	cfg.ExcludedCIDRs = append(excluded, extra...)

	mode, err := ParseSNAT(*snat)
	if err != nil {
		errs = append(errs, fmt.Errorf("--snat: %w", err))
	} else {
		cfg.SNAT = mode
	}

	if err := errors.Join(errs...); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

// ParseSNAT parses "masquerade" or "address:<ipv4>".
func ParseSNAT(value string) (SNAT, error) {
	value = strings.TrimSpace(value)
	if value == "masquerade" {
		return SNAT{Mode: SNATMasquerade}, nil
	}
	if rest, ok := strings.CutPrefix(value, "address:"); ok {
		addr, err := netip.ParseAddr(rest)
		if err != nil {
			return SNAT{}, fmt.Errorf("invalid address %q: %w", rest, err)
		}
		if !addr.Is4() || addr.IsUnspecified() {
			return SNAT{}, fmt.Errorf("address %s must be a non-zero IPv4 address", addr)
		}
		return SNAT{Mode: SNATAddress, Address: addr}, nil
	}
	return SNAT{}, fmt.Errorf("must be masquerade or address:<ipv4>, got %q", value)
}

// ParseCIDRList parses a comma-separated list of IPv4 or IPv6 prefixes,
// ignoring empty entries. Prefixes are returned masked.
func ParseCIDRList(value string) ([]netip.Prefix, error) {
	var prefixes []netip.Prefix
	var errs []error
	for _, entry := range strings.Split(value, ",") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		prefix, err := netip.ParsePrefix(entry)
		if err != nil {
			errs = append(errs, fmt.Errorf("invalid CIDR %q", entry))
			continue
		}
		prefixes = append(prefixes, prefix.Masked())
	}
	return prefixes, errors.Join(errs...)
}

func parseIPv4Prefix(value string) (netip.Prefix, error) {
	prefix, err := netip.ParsePrefix(strings.TrimSpace(value))
	if err != nil {
		return netip.Prefix{}, fmt.Errorf("invalid CIDR %q", value)
	}
	if !prefix.Addr().Is4() {
		return netip.Prefix{}, fmt.Errorf("%s is not IPv4", prefix)
	}
	return prefix, nil
}

func validInterfaceName(name string) bool {
	if name == "" || len(name) > 15 {
		return false
	}
	for _, r := range name {
		valid := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.'
		if !valid {
			return false
		}
	}
	return true
}
