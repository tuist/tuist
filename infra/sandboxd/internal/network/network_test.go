package network

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
)

func TestSlotAddresses(t *testing.T) {
	cases := []struct {
		slot   int
		pod    string
		netns  string
		prefix string
	}{
		{0, "172.31.0.1", "172.31.0.2", "172.31.0.0/30"},
		{1, "172.31.0.5", "172.31.0.6", "172.31.0.4/30"},
		{63, "172.31.0.253", "172.31.0.254", "172.31.0.252/30"},
		{64, "172.31.1.1", "172.31.1.2", "172.31.1.0/30"},
		{MaxSlots - 1, "172.31.255.253", "172.31.255.254", "172.31.255.252/30"},
	}
	for _, c := range cases {
		got, err := SlotAddresses(c.slot)
		if err != nil {
			t.Fatalf("slot %d: %v", c.slot, err)
		}
		if got.Pod.String() != c.pod || got.Netns.String() != c.netns || got.Prefix.String() != c.prefix {
			t.Fatalf("slot %d: got %+v", c.slot, got)
		}
		if got.PodCIDR() != c.pod+"/30" {
			t.Fatalf("slot %d: pod cidr %s", c.slot, got.PodCIDR())
		}
	}
	if _, err := SlotAddresses(MaxSlots); err == nil {
		t.Fatal("expected out of range error")
	}
	if _, err := SlotAddresses(-1); err == nil {
		t.Fatal("expected out of range error")
	}
}

func TestNames(t *testing.T) {
	if got := NamespaceName("0123456789abcdef"); got != "sbx-0123456789ab" {
		t.Fatalf("got %q", got)
	}
	if got := NamespaceName("short"); got != "sbx-short" {
		t.Fatalf("got %q", got)
	}
	if got := VethHostName(7); got != "vh7" {
		t.Fatalf("got %q", got)
	}
	a := BuildNamespaceName("tmpl-default-sha-1-2x4096")
	b := BuildNamespaceName("tmpl-default-sha-1-4x8192")
	if a == b || !strings.HasPrefix(a, "sbx-tmpl-") || len(a) != len("sbx-tmpl-")+8 {
		t.Fatalf("build namespace names %q %q", a, b)
	}
}

func TestSlots(t *testing.T) {
	s := NewSlots(3)
	a, _ := s.Allocate()
	b, _ := s.Allocate()
	if a != 0 || b != 1 {
		t.Fatalf("allocated %d %d", a, b)
	}
	if err := s.Reserve(1); err == nil {
		t.Fatal("expected reserve of used slot to fail")
	}
	if err := s.Reserve(2); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Allocate(); !errors.Is(err, ErrNoFreeSlot) {
		t.Fatalf("expected no free slot, got %v", err)
	}
	s.Release(0)
	c, _ := s.Allocate()
	if c != 0 {
		t.Fatalf("expected released slot reused, got %d", c)
	}
	if s.InUse() != 3 {
		t.Fatalf("in use %d", s.InUse())
	}
}

type fakeRunner struct {
	calls  []string
	fail   map[string]string // command substring -> output (returned as failure)
	exists map[string]bool
}

func (f *fakeRunner) run(ctx context.Context, name string, args ...string) ([]byte, error) {
	line := name + " " + strings.Join(args, " ")
	f.calls = append(f.calls, line)
	for needle, out := range f.fail {
		if strings.Contains(line, needle) {
			return []byte(out), errors.New("exit status 1")
		}
	}
	// iptables -C fails until the matching -A was seen.
	if strings.Contains(line, "iptables") && strings.Contains(line, " -C ") {
		key := strings.Replace(line, " -C ", " -A ", 1)
		if !f.exists[key] {
			return []byte("iptables: Bad rule (does a matching rule exist in that chain?)."), errors.New("exit status 1")
		}
	}
	if strings.Contains(line, " -A ") {
		if f.exists == nil {
			f.exists = map[string]bool{}
		}
		f.exists[line] = true
	}
	if line == "ip -o route show default" {
		return []byte("default via 10.0.1.1 dev eth0 \n"), nil
	}
	return nil, nil
}

func TestSetupIsIdempotentAndUsesSlotAddresses(t *testing.T) {
	f := &fakeRunner{fail: map[string]string{"ip netns add sbx-abc": "Cannot create namespace file \"/var/run/netns/sbx-abc\": File exists"}}
	m := &Manager{Run: f.run, Log: slog.Default()}
	if err := m.Setup(context.Background(), "sbx-abc", 5); err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(f.calls, "\n")
	for _, want := range []string{
		"ip -n sbx-abc tuntap add name tap0 mode tap",
		"ip -n sbx-abc addr replace 10.0.0.1/30 dev tap0",
		"ip link add name vh5 type veth peer name veth0 netns sbx-abc",
		"ip addr replace 172.31.0.21/30 dev vh5",
		"ip -n sbx-abc addr replace 172.31.0.22/30 dev veth0",
		"ip -n sbx-abc route replace default via 172.31.0.21",
		"ip netns exec sbx-abc sysctl -w net.ipv4.ip_forward=1",
		"ip netns exec sbx-abc iptables -w 5 -t nat -A POSTROUTING -s 10.0.0.0/30 -o veth0 -j MASQUERADE",
		"ip netns exec sbx-abc iptables -w 5 -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("missing %q in:\n%s", want, joined)
		}
	}
	before := len(f.calls)
	if err := m.Setup(context.Background(), "sbx-abc", 5); err != nil {
		t.Fatal(err)
	}
	second := strings.Join(f.calls[before:], "\n")
	if strings.Contains(second, "-A POSTROUTING") {
		t.Fatalf("second setup re-added nat rule:\n%s", second)
	}
}

func TestSetupSurfacesRealFailures(t *testing.T) {
	f := &fakeRunner{fail: map[string]string{"ip link add name vh0": "RTNETLINK answers: Operation not permitted"}}
	m := &Manager{Run: f.run, Log: slog.Default()}
	err := m.Setup(context.Background(), "sbx-x", 0)
	if err == nil || !strings.Contains(err.Error(), "Operation not permitted") {
		t.Fatalf("expected failure, got %v", err)
	}
}

func TestTeardownToleratesAbsence(t *testing.T) {
	f := &fakeRunner{fail: map[string]string{
		"ip netns del sbx-x": "Cannot remove namespace file \"/var/run/netns/sbx-x\": No such file or directory",
		"ip link del vh3":    "Cannot find device \"vh3\"",
	}}
	m := &Manager{Run: f.run, Log: slog.Default()}
	if err := m.Teardown(context.Background(), "sbx-x", 3); err != nil {
		t.Fatal(err)
	}
}

func TestEnsurePodNATRunsOnce(t *testing.T) {
	f := &fakeRunner{}
	m := &Manager{Run: f.run, Log: slog.Default()}
	if err := m.EnsurePodNAT(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := m.EnsurePodNAT(context.Background()); err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(f.calls, "\n")
	if strings.Count(joined, "-A POSTROUTING -s 172.31.0.0/16 -o eth0 -j MASQUERADE") != 1 {
		t.Fatalf("expected one masquerade install:\n%s", joined)
	}
	if !strings.Contains(joined, "sysctl -w net.ipv4.ip_forward=1") {
		t.Fatalf("missing ip_forward:\n%s", joined)
	}
}

func TestParseNamespaceList(t *testing.T) {
	got := ParseNamespaceList("sbx-abc123 (id: 0)\ncni-1234\nsbx-tmpl-deadbeef (id: 2)\n\n")
	if len(got) != 2 || got[0] != "sbx-abc123" || got[1] != "sbx-tmpl-deadbeef" {
		t.Fatalf("got %v", got)
	}
}
