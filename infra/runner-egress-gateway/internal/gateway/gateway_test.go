package gateway

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/netdev"
	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/peers"
)

type fakeLink struct {
	err   error
	specs []netdev.LinkSpec
}

func (l *fakeLink) Ensure(spec netdev.LinkSpec) error {
	l.specs = append(l.specs, spec)
	return l.err
}

type fakeWireGuard struct {
	device    wgtypes.Device
	deviceErr error
	configErr error
	configs   []wgtypes.Config
}

func (f *fakeWireGuard) Device(string) (*wgtypes.Device, error) {
	if f.deviceErr != nil {
		return nil, f.deviceErr
	}
	device := f.device
	device.Peers = append([]wgtypes.Peer(nil), f.device.Peers...)
	return &device, nil
}

func (f *fakeWireGuard) ConfigureDevice(_ string, cfg wgtypes.Config) error {
	if f.configErr != nil {
		return f.configErr
	}
	f.configs = append(f.configs, cfg)
	if cfg.PrivateKey != nil {
		f.device.PrivateKey = *cfg.PrivateKey
		f.device.PublicKey = cfg.PrivateKey.PublicKey()
	}
	if cfg.ListenPort != nil {
		f.device.ListenPort = *cfg.ListenPort
	}
	for _, change := range cfg.Peers {
		index := -1
		for i, peer := range f.device.Peers {
			if peer.PublicKey == change.PublicKey {
				index = i
			}
		}
		switch {
		case change.Remove && index >= 0:
			f.device.Peers = append(f.device.Peers[:index], f.device.Peers[index+1:]...)
		case change.Remove:
		case index >= 0:
			f.device.Peers[index].AllowedIPs = change.AllowedIPs
		default:
			f.device.Peers = append(f.device.Peers, wgtypes.Peer{PublicKey: change.PublicKey, AllowedIPs: change.AllowedIPs})
		}
	}
	return nil
}

type fakeNFT struct {
	err      error
	rulesets []string
}

func (f *fakeNFT) Apply(_ context.Context, ruleset string) error {
	f.rulesets = append(f.rulesets, ruleset)
	return f.err
}

type fakeForwarding struct {
	enabled bool
	err     error
}

func (f fakeForwarding) Ensure() (bool, error) { return f.enabled, f.err }

type fakeNodes struct {
	nodes []*corev1.Node
	err   error
}

func (f *fakeNodes) List() ([]*corev1.Node, error) { return f.nodes, f.err }

type harness struct {
	link       *fakeLink
	wireGuard  *fakeWireGuard
	nft        *fakeNFT
	forwarding *fakeForwarding
	nodes      *fakeNodes
	key        wgtypes.Key
	registry   *prometheus.Registry
	reconciler *Reconciler
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	cfg, err := config.Parse([]string{"--gateway-name=g1", "--private-key-file=/unused"}, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	key, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	h := &harness{
		link:       &fakeLink{},
		wireGuard:  &fakeWireGuard{},
		nft:        &fakeNFT{},
		forwarding: &fakeForwarding{enabled: true},
		nodes:      &fakeNodes{},
		key:        key,
		registry:   prometheus.NewRegistry(),
	}
	h.reconciler = New(cfg, Deps{
		Link:       h.link,
		WireGuard:  h.wireGuard,
		NFT:        h.nft,
		Forwarding: h.forwarding,
		Nodes:      h.nodes,
		ReadKey:    func() (wgtypes.Key, error) { return h.key, nil },
		Metrics:    NewMetrics(h.registry),
	})
	return h
}

func macNode(t *testing.T, name, ip string) (*corev1.Node, wgtypes.Key) {
	t.Helper()
	private, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		t.Fatal(err)
	}
	public := private.PublicKey()
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name, Annotations: map[string]string{peers.PublicKeyAnnotation: public.String()}},
		Status:     corev1.NodeStatus{Addresses: []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: ip}}},
	}
	return node, public
}

func TestReconcileConvergesEverything(t *testing.T) {
	h := newHarness(t)
	nodeA, keyA := macNode(t, "mac-a", "100.100.0.1")
	nodeB, keyB := macNode(t, "mac-b", "100.100.0.2")
	h.nodes.nodes = []*corev1.Node{nodeA, nodeB}

	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if !h.reconciler.Status().Ready() {
		t.Fatalf("status = %+v, want ready", h.reconciler.Status())
	}

	spec := h.link.specs[0]
	if spec.Name != "wg0" || spec.MTU != 1420 || spec.Address.String() != "198.18.0.1/32" || spec.Route.String() != "100.64.0.0/10" {
		t.Fatalf("link spec = %+v", spec)
	}
	if h.wireGuard.device.PrivateKey != h.key || h.wireGuard.device.ListenPort != 51820 {
		t.Fatalf("device = %+v", h.wireGuard.device)
	}
	if len(h.wireGuard.device.Peers) != 2 {
		t.Fatalf("peers = %+v", h.wireGuard.device.Peers)
	}
	if len(h.nft.rulesets) != 1 || !strings.Contains(h.nft.rulesets[0], "table inet tuist_egress {") {
		t.Fatalf("rulesets = %v", h.nft.rulesets)
	}
	for _, cfg := range h.wireGuard.configs {
		if cfg.ReplacePeers {
			t.Fatal("peers must never be replaced wholesale")
		}
	}
	if node, ok := h.reconciler.NodeFor(keyA); !ok || node != "mac-a" {
		t.Fatalf("NodeFor(a) = %q, %v", node, ok)
	}
	if node, ok := h.reconciler.NodeFor(keyB); !ok || node != "mac-b" {
		t.Fatalf("NodeFor(b) = %q, %v", node, ok)
	}
}

func TestReconcileSteadyStateConfiguresNothing(t *testing.T) {
	h := newHarness(t)
	nodeA, _ := macNode(t, "mac-a", "100.100.0.1")
	h.nodes.nodes = []*corev1.Node{nodeA}

	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	before := len(h.wireGuard.configs)
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(h.wireGuard.configs) != before {
		t.Fatalf("second pass configured the device: %+v", h.wireGuard.configs[before:])
	}
	if len(h.nft.rulesets) != 2 {
		t.Fatalf("rules must be re-asserted on every pass, got %d applies", len(h.nft.rulesets))
	}
}

func TestReconcileRemovesPeerOfDeletedNode(t *testing.T) {
	h := newHarness(t)
	nodeA, keyA := macNode(t, "mac-a", "100.100.0.1")
	nodeB, keyB := macNode(t, "mac-b", "100.100.0.2")
	h.nodes.nodes = []*corev1.Node{nodeA, nodeB}
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}

	h.nodes.nodes = []*corev1.Node{nodeB}
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	last := h.wireGuard.configs[len(h.wireGuard.configs)-1]
	if len(last.Peers) != 1 || !last.Peers[0].Remove || last.Peers[0].PublicKey != keyA {
		t.Fatalf("last config = %+v, want only the removal of mac-a", last)
	}
	if len(h.wireGuard.device.Peers) != 1 || h.wireGuard.device.Peers[0].PublicKey != keyB {
		t.Fatalf("peers = %+v", h.wireGuard.device.Peers)
	}
	if _, ok := h.reconciler.NodeFor(keyA); ok {
		t.Fatal("removed peer is still mapped to a node")
	}
}

func TestReconcileRotatesPrivateKeyWithoutTouchingPeers(t *testing.T) {
	h := newHarness(t)
	nodeA, _ := macNode(t, "mac-a", "100.100.0.1")
	h.nodes.nodes = []*corev1.Node{nodeA}
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	rotated, _ := wgtypes.GeneratePrivateKey()
	h.key = rotated
	before := len(h.wireGuard.configs)
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	added := h.wireGuard.configs[before:]
	if len(added) != 1 || added[0].PrivateKey == nil || *added[0].PrivateKey != rotated || len(added[0].Peers) != 0 {
		t.Fatalf("configs = %+v", added)
	}
}

func TestReconcileNotReadyUntilPeersSynced(t *testing.T) {
	h := newHarness(t)
	h.nodes.err = errors.New("cache not synced")
	err := h.reconciler.Reconcile(context.Background())
	if err == nil {
		t.Fatal("expected an error")
	}
	status := h.reconciler.Status()
	if status.Ready() || status.PeersSynced || !status.Link || !status.Rules {
		t.Fatalf("status = %+v", status)
	}

	h.nodes.err = nil
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !h.reconciler.Status().Ready() {
		t.Fatalf("status = %+v", h.reconciler.Status())
	}

	h.nodes.err = errors.New("transient")
	_ = h.reconciler.Reconcile(context.Background())
	if !h.reconciler.Status().Ready() {
		t.Fatalf("a later failed peer sync must not drop readiness: %+v", h.reconciler.Status())
	}
}

func TestReconcileRunsAllStepsAndReportsEachFailure(t *testing.T) {
	cases := map[string]struct {
		mutate func(*harness)
		want   string
		check  func(*testing.T, Status)
	}{
		"forwarding disabled": {
			mutate: func(h *harness) { *h.forwarding = fakeForwarding{enabled: false, err: errors.New("ip_forward is 0")} },
			want:   "ip forwarding",
			check: func(t *testing.T, s Status) {
				if s.Forwarding || !s.Link || !s.Rules || !s.PeersSynced {
					t.Fatalf("status = %+v", s)
				}
			},
		},
		"link failure": {
			mutate: func(h *harness) { h.link.err = errors.New("operation not supported") },
			want:   "link",
			check: func(t *testing.T, s Status) {
				if s.Link || s.PeersSynced || !s.Rules {
					t.Fatalf("status = %+v", s)
				}
			},
		},
		"nft failure": {
			mutate: func(h *harness) { h.nft.err = errors.New("syntax error") },
			want:   "nftables",
			check: func(t *testing.T, s Status) {
				if s.Rules || !s.Link || !s.PeersSynced {
					t.Fatalf("status = %+v", s)
				}
			},
		},
		"device failure": {
			mutate: func(h *harness) { h.wireGuard.deviceErr = errors.New("no such device") },
			want:   "wireguard device",
			check: func(t *testing.T, s Status) {
				if s.Link || s.PeersSynced || !s.Rules {
					t.Fatalf("status = %+v", s)
				}
			},
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			tc.mutate(h)
			err := h.reconciler.Reconcile(context.Background())
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %v, want it to mention %q", err, tc.want)
			}
			status := h.reconciler.Status()
			if status.Ready() {
				t.Fatal("must not be ready")
			}
			tc.check(t, status)
			if got := testutil.ToFloat64(h.reconciler.deps.Metrics.syncErrors); got != 1 {
				t.Fatalf("sync errors = %v", got)
			}
		})
	}
}

func TestReconcileLinkFailureAfterReadyDropsReadiness(t *testing.T) {
	h := newHarness(t)
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	h.link.err = errors.New("gone")
	_ = h.reconciler.Reconcile(context.Background())
	if h.reconciler.Status().Ready() {
		t.Fatal("must not be ready while the link is broken")
	}
}

func TestKeyFileReader(t *testing.T) {
	dir := t.TempDir()
	key, _ := wgtypes.GeneratePrivateKey()
	path := filepath.Join(dir, "private.key")
	if err := os.WriteFile(path, []byte(key.String()+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := KeyFileReader(path)()
	if err != nil || got != key {
		t.Fatalf("KeyFileReader = %v, %v", got, err)
	}

	if err := os.WriteFile(path, []byte("garbage"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := KeyFileReader(path)(); err == nil {
		t.Fatal("expected a parse error")
	}
	if err := os.WriteFile(path, []byte(wgtypes.Key{}.String()), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := KeyFileReader(path)(); err == nil {
		t.Fatal("expected an all-zero key error")
	}
}

func TestHandlers(t *testing.T) {
	h := newHarness(t)
	now := time.Unix(1_000_000, 0)
	clock := func() time.Time { return now }
	h.reconciler.deps.Now = clock
	tunnel := TunnelHealthHandler(h.reconciler)
	probes := ProbeHandler(h.reconciler, now, 90*time.Second, clock)

	get := func(handler http.Handler, path string) int {
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, path, nil))
		return recorder.Code
	}

	if code := get(tunnel, "/healthz"); code != http.StatusServiceUnavailable {
		t.Fatalf("/healthz before reconcile = %d", code)
	}
	if code := get(probes, "/readyz"); code != http.StatusServiceUnavailable {
		t.Fatalf("/readyz before reconcile = %d", code)
	}
	if code := get(probes, "/livez"); code != http.StatusOK {
		t.Fatalf("/livez before reconcile = %d", code)
	}

	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if code := get(tunnel, "/healthz"); code != http.StatusOK {
		t.Fatalf("/healthz = %d", code)
	}
	if code := get(probes, "/readyz"); code != http.StatusOK {
		t.Fatalf("/readyz = %d", code)
	}
	if code := get(tunnel, "/readyz"); code != http.StatusNotFound {
		t.Fatalf("tunnel listener must only serve /healthz, /readyz = %d", code)
	}

	now = now.Add(91 * time.Second)
	if code := get(probes, "/livez"); code != http.StatusServiceUnavailable {
		t.Fatalf("/livez with a stale loop = %d", code)
	}
}

func TestPeerCollector(t *testing.T) {
	h := newHarness(t)
	nodeA, _ := macNode(t, "mac-a", "100.100.0.1")
	h.nodes.nodes = []*corev1.Node{nodeA}
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	stranger, _ := wgtypes.GeneratePrivateKey()
	h.wireGuard.device.Peers[0].LastHandshakeTime = time.Unix(1_700_000_000, 0)
	h.wireGuard.device.Peers[0].ReceiveBytes = 10
	h.wireGuard.device.Peers[0].TransmitBytes = 20
	h.wireGuard.device.Peers = append(h.wireGuard.device.Peers, wgtypes.Peer{
		PublicKey:  stranger.PublicKey(),
		AllowedIPs: []net.IPNet{{IP: net.IPv4(100, 100, 0, 9).To4(), Mask: net.CIDRMask(32, 32)}},
	})
	registry := prometheus.NewRegistry()
	wrapped := prometheus.WrapRegistererWith(prometheus.Labels{"gateway": "g1"}, registry)
	wrapped.MustRegister(NewPeerCollector(h.wireGuard, h.reconciler.NodeFor))

	expected := `
# HELP tuist_runner_egress_gateway_peer_last_handshake_seconds Unix time of the peer's latest handshake, 0 if it never completed one.
# TYPE tuist_runner_egress_gateway_peer_last_handshake_seconds gauge
tuist_runner_egress_gateway_peer_last_handshake_seconds{gateway="g1",node="mac-a"} 1.7e+09
# HELP tuist_runner_egress_gateway_peer_rx_bytes_total Bytes received from the peer.
# TYPE tuist_runner_egress_gateway_peer_rx_bytes_total counter
tuist_runner_egress_gateway_peer_rx_bytes_total{gateway="g1",node="mac-a"} 10
# HELP tuist_runner_egress_gateway_peer_tx_bytes_total Bytes sent to the peer.
# TYPE tuist_runner_egress_gateway_peer_tx_bytes_total counter
tuist_runner_egress_gateway_peer_tx_bytes_total{gateway="g1",node="mac-a"} 20
# HELP tuist_runner_egress_gateway_peers WireGuard peers configured on the tunnel interface.
# TYPE tuist_runner_egress_gateway_peers gauge
tuist_runner_egress_gateway_peers{gateway="g1"} 2
`
	if err := testutil.GatherAndCompare(registry, strings.NewReader(expected)); err != nil {
		t.Fatal(err)
	}

	h.wireGuard.deviceErr = errors.New("gone")
	if count, err := testutil.GatherAndCount(registry); err != nil || count != 0 {
		t.Fatalf("collector must emit nothing when the device is unreadable: %d, %v", count, err)
	}
}

func TestReadyWithZeroPeers(t *testing.T) {
	h := newHarness(t)
	h.nodes.nodes = nil
	if err := h.reconciler.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !h.reconciler.Status().Ready() {
		t.Fatalf("an empty peer set must still be ready: %+v", h.reconciler.Status())
	}
	if len(h.wireGuard.device.Peers) != 0 {
		t.Fatalf("peers = %+v", h.wireGuard.device.Peers)
	}
}

func TestPerGatewayTunnelAddress(t *testing.T) {
	cfg, err := config.Parse([]string{"--gateway-name=g3", "--private-key-file=/k", "--tunnel-address=198.18.3.1/32"}, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if got := TunnelHealthAddress(cfg); got != "198.18.3.1:8080" {
		t.Fatalf("TunnelHealthAddress = %s", got)
	}
	r := New(cfg, Deps{})
	if !strings.Contains(r.Ruleset(), "ip daddr 198.18.3.1 tcp dport 8080 accept") {
		t.Fatalf("ruleset does not open the health port on the tunnel address:\n%s", r.Ruleset())
	}
}
