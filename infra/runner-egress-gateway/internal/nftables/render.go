package nftables

import (
	"fmt"
	"net/netip"
	"sort"
	"strings"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
)

const Table = "tuist_egress"

type Options struct {
	TunnelInterface string
	OutInterface    string
	TunnelAddress   netip.Addr
	HealthPort      int
	PeerCIDR        netip.Prefix
	ExcludedCIDRs   []netip.Prefix
	SNAT            config.SNAT
}

// Render returns a ruleset that atomically replaces the inet tuist_egress
// table when piped to `nft -f -`. The leading empty table declaration makes
// the delete succeed when the table does not exist yet.
func Render(opts Options) string {
	excluded := normalizeExcluded(opts)
	tun := quote(opts.TunnelInterface)
	out := quote(opts.OutInterface)

	var b strings.Builder
	fmt.Fprintf(&b, "table inet %s\n", Table)
	fmt.Fprintf(&b, "delete table inet %s\n", Table)
	b.WriteString("\n")
	fmt.Fprintf(&b, "table inet %s {\n", Table)

	b.WriteString("\tset excluded_v4 {\n")
	b.WriteString("\t\ttype ipv4_addr\n")
	b.WriteString("\t\tflags interval\n")
	elements := make([]string, len(excluded))
	for i, prefix := range excluded {
		elements[i] = prefix.String()
	}
	fmt.Fprintf(&b, "\t\telements = { %s }\n", strings.Join(elements, ", "))
	b.WriteString("\t}\n\n")

	b.WriteString("\tchain input {\n")
	b.WriteString("\t\ttype filter hook input priority filter; policy accept;\n")
	fmt.Fprintf(&b, "\t\tiifname %s ct state established,related accept\n", tun)
	fmt.Fprintf(&b, "\t\tiifname %s ip saddr %s ip daddr %s tcp dport %d accept\n", tun, opts.PeerCIDR, opts.TunnelAddress, opts.HealthPort)
	fmt.Fprintf(&b, "\t\tiifname %s drop\n", tun)
	b.WriteString("\t}\n\n")

	b.WriteString("\tchain forward {\n")
	b.WriteString("\t\ttype filter hook forward priority filter; policy accept;\n")
	fmt.Fprintf(&b, "\t\tiifname %s meta nfproto ipv6 drop\n", tun)
	fmt.Fprintf(&b, "\t\toifname %s iifname %s ct state established,related accept\n", tun, out)
	fmt.Fprintf(&b, "\t\toifname %s drop\n", tun)
	fmt.Fprintf(&b, "\t\tiifname %s oifname %s ip saddr %s ip daddr != @excluded_v4 accept\n", tun, out, opts.PeerCIDR)
	fmt.Fprintf(&b, "\t\tiifname %s drop\n", tun)
	b.WriteString("\t}\n\n")

	b.WriteString("\tchain postrouting {\n")
	b.WriteString("\t\ttype nat hook postrouting priority srcnat; policy accept;\n")
	switch opts.SNAT.Mode {
	case config.SNATAddress:
		fmt.Fprintf(&b, "\t\toifname %s ip saddr %s snat ip to %s\n", out, opts.PeerCIDR, opts.SNAT.Address)
	default:
		fmt.Fprintf(&b, "\t\toifname %s ip saddr %s masquerade\n", out, opts.PeerCIDR)
	}
	b.WriteString("\t}\n")

	b.WriteString("}\n")
	return b.String()
}

// normalizeExcluded returns the IPv4 excluded prefixes plus the peer range and
// the tunnel address, sorted and with prefixes covered by another one removed,
// since an interval set rejects overlapping elements. IPv6 prefixes are
// dropped: all IPv6 forwarding from the tunnel is rejected.
func normalizeExcluded(opts Options) []netip.Prefix {
	all := []netip.Prefix{opts.PeerCIDR.Masked()}
	if opts.TunnelAddress.Is4() {
		all = append(all, netip.PrefixFrom(opts.TunnelAddress, 32))
	}
	for _, prefix := range opts.ExcludedCIDRs {
		if prefix.IsValid() && prefix.Addr().Is4() {
			all = append(all, prefix.Masked())
		}
	}

	sort.Slice(all, func(i, j int) bool {
		if c := all[i].Addr().Compare(all[j].Addr()); c != 0 {
			return c < 0
		}
		return all[i].Bits() < all[j].Bits()
	})

	var result []netip.Prefix
	for _, prefix := range all {
		if len(result) > 0 {
			last := result[len(result)-1]
			if last.Bits() <= prefix.Bits() && last.Contains(prefix.Addr()) {
				continue
			}
		}
		result = append(result, prefix)
	}
	return result
}

func quote(name string) string {
	return `"` + name + `"`
}
