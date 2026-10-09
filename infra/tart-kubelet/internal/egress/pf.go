package egress

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

const allTable = "egress_all"

func gatewayTable(gateway string) string {
	return "egress_" + gateway
}

// gatewayTag marks a flow routed into a gateway's tunnel. If the tunnel's utun
// is gone, pf may hand the packet back to normal routing; the tagged block
// then drops it on every other interface, so it never leaves from the host
// address.
func gatewayTag(gateway string) string {
	return "tuist_egress_" + gateway
}

// AnchorGateway is a gateway as the pf anchor needs it.
type AnchorGateway struct {
	Name  string
	Index int
}

// RenderAnchor renders the whole egress anchor. Tables holding VM addresses
// are referenced but not defined, so reloading the rules leaves their contents
// alone; only the constant exclude table is defined here.
//
// Every VM bound to a gateway is in egress_all. Its own gateway's quick pass
// routes it into the tunnel; anything that pass doesn't catch (unknown
// gateway, rule missing) reaches the backstop and is dropped, so a bound VM's
// traffic never leaves through the host's own address.
func RenderAnchor(gateways []AnchorGateway, tailnetIP string, exclude []string) string {
	sorted := append([]AnchorGateway(nil), gateways...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Name < sorted[j].Name })

	var b strings.Builder
	fmt.Fprintf(&b, "table <egress_exclude> const { %s }\n", strings.Join(exclude, ", "))
	for _, gateway := range sorted {
		fmt.Fprintf(&b, "scrub on %s all max-mss %d\n", InterfaceName(gateway.Index), MTU-40)
	}
	for _, gateway := range sorted {
		iface := InterfaceName(gateway.Index)
		fmt.Fprintf(&b, "nat on %s inet from ! %s to any -> %s\n", iface, tailnetIP, tailnetIP)
	}
	for _, gateway := range sorted {
		_, next := TunnelAddresses(gateway.Index)
		fmt.Fprintf(&b, "pass in quick route-to (%s %s) inet from <%s> to ! <egress_exclude> flags any keep state tag %s\n",
			InterfaceName(gateway.Index), next, gatewayTable(gateway.Name), gatewayTag(gateway.Name))
	}
	for _, gateway := range sorted {
		fmt.Fprintf(&b, "block drop out quick on ! %s tagged %s\n", InterfaceName(gateway.Index), gatewayTag(gateway.Name))
	}
	fmt.Fprintf(&b, "block drop in quick inet from <%s> to ! <egress_exclude>\n", allTable)
	return b.String()
}

// PF is the subset of pfctl the manager drives.
type PF interface {
	LoadAnchor(ctx context.Context, anchor, rules string) error
	ReplaceTable(ctx context.Context, anchor, table string, addresses []string) error
	TableAddresses(ctx context.Context, anchor, table string) ([]string, error)
	KillStates(ctx context.Context, address string) error
	ShowRules(ctx context.Context, anchor string) (string, error)
}

// SudoPFCtl runs pfctl through passwordless sudo, which the host bootstrap
// grants the tart-kubelet user.
type SudoPFCtl struct {
	Path string
}

func (p SudoPFCtl) run(ctx context.Context, stdin string, args ...string) (string, error) {
	path := p.Path
	if path == "" {
		path = "/sbin/pfctl"
	}
	cmd := exec.CommandContext(ctx, "sudo", append([]string{"-n", path}, args...)...)
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("pfctl %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return stdout.String(), nil
}

func (p SudoPFCtl) LoadAnchor(ctx context.Context, anchor, rules string) error {
	_, err := p.run(ctx, rules, "-a", anchor, "-f", "-")
	return err
}

// ReplaceTable creates the table when missing (pfctl marks a table it creates
// persistent, so later anchor reloads keep it) and sets its contents; an empty
// list empties it.
func (p SudoPFCtl) ReplaceTable(ctx context.Context, anchor, table string, addresses []string) error {
	_, err := p.run(ctx, "", append([]string{"-a", anchor, "-t", table, "-T", "replace"}, addresses...)...)
	return err
}

func (p SudoPFCtl) ShowRules(ctx context.Context, anchor string) (string, error) {
	return p.run(ctx, "", "-a", anchor, "-s", "rules")
}

func (p SudoPFCtl) TableAddresses(ctx context.Context, anchor, table string) ([]string, error) {
	out, err := p.run(ctx, "", "-a", anchor, "-t", table, "-T", "show")
	if err != nil {
		return nil, err
	}
	var addresses []string
	for _, line := range strings.Split(out, "\n") {
		if address := strings.TrimSpace(line); address != "" {
			addresses = append(addresses, address)
		}
	}
	return addresses, nil
}

// KillStates removes every pf state from and to an address.
func (p SudoPFCtl) KillStates(ctx context.Context, address string) error {
	if _, err := p.run(ctx, "", "-k", address); err != nil {
		return err
	}
	_, err := p.run(ctx, "", "-k", "0.0.0.0/0", "-k", address)
	return err
}
