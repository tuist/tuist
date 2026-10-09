//go:build linux

package gateway

import (
	"context"
	"io"
	"os"
	"os/exec"
	"strings"
	"testing"

	"golang.zx2c4.com/wireguard/wgctrl"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	corev1 "k8s.io/api/core/v1"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/netdev"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/nftables"
)

// TestReconcileInNetworkNamespace drives the real netlink, wgctrl and nft
// implementations. It changes the network namespace it runs in, so it only
// runs when RUNNER_EGRESS_GATEWAY_NETNS_TEST=1, for example in a throwaway
// container with NET_ADMIN.
func TestReconcileInNetworkNamespace(t *testing.T) {
	if os.Getenv("RUNNER_EGRESS_GATEWAY_NETNS_TEST") != "1" {
		t.Skip("set RUNNER_EGRESS_GATEWAY_NETNS_TEST=1 in a disposable network namespace")
	}
	client, err := wgctrl.New()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	cfg, err := config.Parse([]string{"--gateway-name=it", "--private-key-file=/unused", "--tunnel-address=198.18.3.1/32"}, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	key, _ := wgtypes.GeneratePrivateKey()
	nodeA, keyA := macNode(t, "mac-a", "100.100.0.1")
	nodeB, keyB := macNode(t, "mac-b", "100.100.0.2")
	nodes := &fakeNodes{nodes: []*corev1.Node{nodeA, nodeB}}

	r := New(cfg, Deps{
		Link:       netdev.NewLink(),
		WireGuard:  client,
		NFT:        nftables.Exec{},
		Forwarding: netdev.Forwarding{},
		Nodes:      nodes,
		ReadKey:    func() (wgtypes.Key, error) { return key, nil },
	})

	for pass := 0; pass < 2; pass++ {
		if err := r.Reconcile(context.Background()); err != nil {
			t.Fatalf("pass %d: %v", pass, err)
		}
	}
	if !r.Status().Ready() {
		t.Fatalf("status = %+v", r.Status())
	}

	device, err := client.Device(config.InterfaceName)
	if err != nil {
		t.Fatal(err)
	}
	if device.PrivateKey != key || device.ListenPort != 51820 || len(device.Peers) != 2 {
		t.Fatalf("device = %+v", device)
	}

	out := run(t, "ip", "-4", "addr", "show", "dev", "wg0")
	if !strings.Contains(out, "198.18.3.1/32") || !strings.Contains(out, "mtu 1420") || !strings.Contains(out, "UP") {
		t.Fatalf("wg0:\n%s", out)
	}
	if out := run(t, "ip", "route", "show", "100.64.0.0/10"); !strings.Contains(out, "dev wg0") {
		t.Fatalf("route: %s", out)
	}
	if out := run(t, "nft", "list", "table", "inet", "tuist_egress"); !strings.Contains(out, "masquerade") {
		t.Fatalf("table:\n%s", out)
	}

	run(t, "ip", "addr", "flush", "dev", "wg0")
	run(t, "nft", "delete", "table", "inet", "tuist_egress")
	nodes.nodes = []*corev1.Node{nodeB}
	if err := r.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if out := run(t, "ip", "-4", "addr", "show", "dev", "wg0"); !strings.Contains(out, "198.18.3.1/32") {
		t.Fatalf("address not restored:\n%s", out)
	}
	run(t, "nft", "list", "table", "inet", "tuist_egress")
	device, err = client.Device(config.InterfaceName)
	if err != nil {
		t.Fatal(err)
	}
	if len(device.Peers) != 1 || device.Peers[0].PublicKey != keyB {
		t.Fatalf("peers = %+v, want only %s (removed %s)", device.Peers, keyB, keyA)
	}
}

func run(t *testing.T, name string, args ...string) string {
	t.Helper()
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s: %v\n%s", name, strings.Join(args, " "), err, out)
	}
	return string(out)
}
