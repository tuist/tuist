package gateway

import (
	"github.com/prometheus/client_golang/prometheus"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"

	"github.com/tuist/tuist/infra/runner-egress-gateway/internal/config"
)

const metricPrefix = "tuist_runner_egress_gateway_"

type Metrics struct {
	syncErrors prometheus.Counter
}

// NewMetrics registers the gateway metrics on reg, which is expected to carry
// the constant gateway label.
func NewMetrics(reg prometheus.Registerer) *Metrics {
	m := &Metrics{
		syncErrors: prometheus.NewCounter(prometheus.CounterOpts{
			Name: metricPrefix + "sync_errors_total",
			Help: "Reconcile passes that failed to converge the link, rules or peers.",
		}),
	}
	reg.MustRegister(m.syncErrors)
	return m
}

func (m *Metrics) ObserveReconcile(_ Status, err error) {
	if err != nil {
		m.syncErrors.Inc()
	}
}

// PeerCollector reads the WireGuard device at scrape time.
type PeerCollector struct {
	wireGuard WireGuard
	nodeFor   func(wgtypes.Key) (string, bool)

	peers     *prometheus.Desc
	handshake *prometheus.Desc
	rx        *prometheus.Desc
	tx        *prometheus.Desc
}

func NewPeerCollector(wireGuard WireGuard, nodeFor func(wgtypes.Key) (string, bool)) *PeerCollector {
	return &PeerCollector{
		wireGuard: wireGuard,
		nodeFor:   nodeFor,
		peers: prometheus.NewDesc(metricPrefix+"peers",
			"WireGuard peers configured on the tunnel interface.", nil, nil),
		handshake: prometheus.NewDesc(metricPrefix+"peer_last_handshake_seconds",
			"Unix time of the peer's latest handshake, 0 if it never completed one.", []string{"node"}, nil),
		rx: prometheus.NewDesc(metricPrefix+"peer_rx_bytes_total",
			"Bytes received from the peer.", []string{"node"}, nil),
		tx: prometheus.NewDesc(metricPrefix+"peer_tx_bytes_total",
			"Bytes sent to the peer.", []string{"node"}, nil),
	}
}

func (c *PeerCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.peers
	ch <- c.handshake
	ch <- c.rx
	ch <- c.tx
}

func (c *PeerCollector) Collect(ch chan<- prometheus.Metric) {
	device, err := c.wireGuard.Device(config.InterfaceName)
	if err != nil {
		return
	}
	ch <- prometheus.MustNewConstMetric(c.peers, prometheus.GaugeValue, float64(len(device.Peers)))
	for _, peer := range device.Peers {
		node, ok := c.nodeFor(peer.PublicKey)
		if !ok {
			continue
		}
		handshake := 0.0
		if !peer.LastHandshakeTime.IsZero() {
			handshake = float64(peer.LastHandshakeTime.UnixNano()) / 1e9
		}
		ch <- prometheus.MustNewConstMetric(c.handshake, prometheus.GaugeValue, handshake, node)
		ch <- prometheus.MustNewConstMetric(c.rx, prometheus.CounterValue, float64(peer.ReceiveBytes), node)
		ch <- prometheus.MustNewConstMetric(c.tx, prometheus.CounterValue, float64(peer.TransmitBytes), node)
	}
}
