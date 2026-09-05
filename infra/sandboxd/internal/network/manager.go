package network

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os/exec"
	"strings"
	"sync"
)

// Interface is what the sandbox manager and template builder need. The
// real implementation shells out to ip and iptables.
type Interface interface {
	// Setup creates (or repairs) the netns for a slot. It is idempotent.
	Setup(ctx context.Context, ns string, slot int) error
	// Teardown deletes the netns and the pod-side veth. Absence is not an
	// error.
	Teardown(ctx context.Context, ns string, slot int) error
	// Namespaces lists the sandbox netns names present in the pod.
	Namespaces(ctx context.Context) ([]string, error)
}

// Runner executes a command and returns its combined output.
type Runner func(ctx context.Context, name string, args ...string) ([]byte, error)

func ExecRunner(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	return out.Bytes(), err
}

// Manager drives ip and iptables in the pod's network namespace.
type Manager struct {
	Run Runner
	Log *slog.Logger
	// PodInterface is the pod's egress device (default eth0), resolved from
	// the default route when empty.
	PodInterface string

	natOnce sync.Once
	natErr  error
}

func NewManager(log *slog.Logger) *Manager {
	return &Manager{Run: ExecRunner, Log: log}
}

func (m *Manager) run(ctx context.Context, name string, args ...string) error {
	out, err := m.Run(ctx, name, args...)
	if err != nil {
		return fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

// runTolerant ignores failures whose output matches one of the substrings
// (used for "already exists" / "does not exist" idempotency).
func (m *Manager) runTolerant(ctx context.Context, tolerate []string, name string, args ...string) error {
	out, err := m.Run(ctx, name, args...)
	if err == nil {
		return nil
	}
	text := string(out)
	for _, needle := range tolerate {
		if strings.Contains(text, needle) {
			return nil
		}
	}
	return fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(text))
}

// ensureRule appends an iptables rule unless it is already present.
func (m *Manager) ensureRule(ctx context.Context, prefix []string, table, chain string, rule ...string) error {
	check := append(append([]string{}, prefix...), "iptables", "-w", "5", "-t", table, "-C", chain)
	check = append(check, rule...)
	if _, err := m.Run(ctx, check[0], check[1:]...); err == nil {
		return nil
	}
	add := append(append([]string{}, prefix...), "iptables", "-w", "5", "-t", table, "-A", chain)
	add = append(add, rule...)
	return m.run(ctx, add[0], add[1:]...)
}

// EnsurePodNAT installs the pod-level forwarding and MASQUERADE for the
// slot range once per process.
func (m *Manager) EnsurePodNAT(ctx context.Context) error {
	m.natOnce.Do(func() { m.natErr = m.ensurePodNAT(ctx) })
	return m.natErr
}

func (m *Manager) ensurePodNAT(ctx context.Context) error {
	dev := m.PodInterface
	if dev == "" {
		dev = m.defaultInterface(ctx)
	}
	if err := m.run(ctx, "sysctl", "-w", "net.ipv4.ip_forward=1"); err != nil {
		return err
	}
	if err := m.ensureRule(ctx, nil, "nat", "POSTROUTING", "-s", SlotNetwork, "-o", dev, "-j", "MASQUERADE"); err != nil {
		return err
	}
	if err := m.ensureRule(ctx, nil, "filter", "FORWARD", "-s", SlotNetwork, "-j", "ACCEPT"); err != nil {
		return err
	}
	if err := m.ensureRule(ctx, nil, "filter", "FORWARD", "-d", SlotNetwork, "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"); err != nil {
		return err
	}
	m.Log.Info("pod NAT ready", "interface", dev, "range", SlotNetwork)
	return nil
}

func (m *Manager) defaultInterface(ctx context.Context) string {
	out, err := m.Run(ctx, "ip", "-o", "route", "show", "default")
	if err == nil {
		fields := strings.Fields(string(out))
		for i, f := range fields {
			if f == "dev" && i+1 < len(fields) {
				return fields[i+1]
			}
		}
	}
	return "eth0"
}

func (m *Manager) Setup(ctx context.Context, ns string, slot int) error {
	addrs, err := SlotAddresses(slot)
	if err != nil {
		return err
	}
	host := VethHostName(slot)
	exists := []string{"File exists", "already exists"}
	if err := m.runTolerant(ctx, exists, "ip", "netns", "add", ns); err != nil {
		return err
	}
	in := []string{"ip", "-n", ns}
	steps := [][]string{
		append(in, "link", "set", "lo", "up"),
	}
	for _, step := range steps {
		if err := m.run(ctx, step[0], step[1:]...); err != nil {
			return err
		}
	}
	if err := m.runTolerant(ctx, exists, "ip", "-n", ns, "tuntap", "add", "name", TapName, "mode", "tap"); err != nil {
		return err
	}
	// The veth pair is recreated from scratch so its peer is guaranteed to
	// sit in this netns even after a partial teardown.
	_ = m.runTolerant(ctx, []string{"Cannot find device", "does not exist"}, "ip", "link", "del", host)
	if err := m.run(ctx, "ip", "link", "add", "name", host, "type", "veth", "peer", "name", VethNetnsName, "netns", ns); err != nil {
		return err
	}
	steps = [][]string{
		append(in, "addr", "replace", TapAddr, "dev", TapName),
		append(in, "link", "set", TapName, "up"),
		{"ip", "addr", "replace", addrs.PodCIDR(), "dev", host},
		{"ip", "link", "set", host, "up"},
		append(in, "addr", "replace", addrs.NetnsCIDR(), "dev", VethNetnsName),
		append(in, "link", "set", VethNetnsName, "up"),
		append(in, "route", "replace", "default", "via", addrs.Pod.String()),
		{"ip", "netns", "exec", ns, "sysctl", "-w", "net.ipv4.ip_forward=1"},
	}
	for _, step := range steps {
		if err := m.run(ctx, step[0], step[1:]...); err != nil {
			return err
		}
	}
	prefix := []string{"ip", "netns", "exec", ns}
	if err := m.ensureRule(ctx, prefix, "nat", "POSTROUTING", "-s", GuestNet, "-o", VethNetnsName, "-j", "MASQUERADE"); err != nil {
		return err
	}
	// The guest link is 1500 while the pod's device may be smaller (VXLAN);
	// clamping MSS keeps TCP from relying on ICMP for path MTU.
	if err := m.ensureRule(ctx, prefix, "mangle", "FORWARD", "-p", "tcp", "--tcp-flags", "SYN,RST", "SYN", "-j", "TCPMSS", "--clamp-mss-to-pmtu"); err != nil {
		return err
	}
	return nil
}

func (m *Manager) Teardown(ctx context.Context, ns string, slot int) error {
	var errs []error
	absent := []string{"No such file", "Cannot find device", "does not exist", "Cannot remove namespace"}
	if err := m.runTolerant(ctx, absent, "ip", "netns", "del", ns); err != nil {
		errs = append(errs, err)
	}
	if slot >= 0 {
		if err := m.runTolerant(ctx, absent, "ip", "link", "del", VethHostName(slot)); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

func (m *Manager) Namespaces(ctx context.Context) ([]string, error) {
	out, err := m.Run(ctx, "ip", "netns", "list")
	if err != nil {
		return nil, fmt.Errorf("ip netns list: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return ParseNamespaceList(string(out)), nil
}

// ParseNamespaceList extracts sandbox netns names from `ip netns list`
// output ("name (id: N)" per line).
func ParseNamespaceList(out string) []string {
	var names []string
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if strings.HasPrefix(fields[0], "sbx-") {
			names = append(names, fields[0])
		}
	}
	return names
}
