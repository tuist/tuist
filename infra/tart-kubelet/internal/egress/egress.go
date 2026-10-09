// Package egress routes the traffic of runner VMs bound to an account with a
// dedicated egress address through a WireGuard tunnel to that account's
// gateway. See infra/runner-egress-gateway/DESIGN.md.
package egress

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	// PodLabel is stamped by the server on a runner Pod bound to an account
	// with a dedicated gateway. Its value is the gateway name.
	PodLabel = "tuist.dev/runner-egress-gateway"
	// ReadyCondition is set on the Pod once the VM's route is enforced. The
	// server returns the job credential only after it reads True.
	ReadyCondition = "tuist.dev/RunnerEgressReady"
	// PublicKeyAnnotation carries the host's WireGuard public key. Gateways
	// build their peer list from it.
	PublicKeyAnnotation = "tuist.dev/runner-egress-public-key"
	// ReadyGatewaysAnnotation lists the gateways whose tunnel is healthy on
	// this host. The server only dispatches a gateway's account here when the
	// gateway is listed.
	ReadyGatewaysAnnotation = "tuist.dev/runner-egress-ready-gateways"
	// AnnotationPrefix is the prefix of every Node annotation this package
	// owns.
	AnnotationPrefix = "tuist.dev/runner-egress-"

	// Anchor sorts ahead of every other com.apple/* sub-anchor, including
	// tuist.sshguard, whose quick pass for VM SSH would otherwise send a
	// routed VM's git-over-SSH out of the host's own address.
	Anchor = "com.apple/0.tuist.egress"

	MTU             = 1420
	HealthPort      = 8080
	interfaceOffset = 100
	maxIndex        = 99

	statusFreshness    = 20 * time.Second
	handshakeFreshness = 180 * time.Second
)

// DefaultExcludeCIDRs are the destinations that never enter a tunnel: private,
// shared and special-use space. Runner-cache carve-outs are appended by the
// host configuration.
var DefaultExcludeCIDRs = []string{
	"0.0.0.0/8",
	"10.0.0.0/8",
	"100.64.0.0/10",
	"127.0.0.0/8",
	"169.254.0.0/16",
	"172.16.0.0/12",
	"192.0.0.0/24",
	"192.168.0.0/16",
	"198.18.0.0/15",
	"224.0.0.0/4",
	"240.0.0.0/4",
}

var gatewayNamePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$`)

// ValidateGatewayName keeps names usable as pf table names, label values and
// launchd labels.
func ValidateGatewayName(name string) error {
	if !gatewayNamePattern.MatchString(name) {
		return fmt.Errorf("gateway name %q must be a lowercase DNS label of at most 24 characters", name)
	}
	return nil
}

// ValidateIndex bounds the per-gateway index that selects the utun unit and
// the tunnel addresses.
func ValidateIndex(index int) error {
	if index < 0 || index > maxIndex {
		return fmt.Errorf("gateway index %d must be between 0 and %d", index, maxIndex)
	}
	return nil
}

// InterfaceName is the fixed utun the tunnel for a gateway uses, so the pf
// rules keep pointing at the right device across daemon restarts.
func InterfaceName(index int) string {
	return fmt.Sprintf("utun%d", interfaceOffset+index)
}

// TunnelAddresses returns the host and gateway ends of a gateway's
// point-to-point tunnel. Each gateway gets its own /24 so several tunnels on
// one host never install conflicting host routes.
func TunnelAddresses(index int) (local, gateway string) {
	return fmt.Sprintf("198.18.%d.2", index), fmt.Sprintf("198.18.%d.1", index)
}

// Status is what a tunnel daemon reports about its gateway. tart-kubelet reads
// it to render the pf anchor and to decide whether a VM may be armed.
type Status struct {
	Gateway           string `json:"gateway"`
	Index             int    `json:"index"`
	Interface         string `json:"interface"`
	Endpoint          string `json:"endpoint"`
	LastHandshakeUnix int64  `json:"last_handshake_unix"`
	RxBytes           uint64 `json:"rx_bytes"`
	TxBytes           uint64 `json:"tx_bytes"`
	ProbeOK           bool   `json:"probe_ok"`
	ProbeError        string `json:"probe_error,omitempty"`
	UpdatedUnix       int64  `json:"updated_unix"`
}

// Healthy reports whether the tunnel can carry a newly armed VM: the report is
// recent, the gateway answered its health check through the tunnel and the
// WireGuard session is current.
func (s Status) Healthy(now time.Time) bool {
	if !s.ProbeOK || s.UpdatedUnix == 0 || s.LastHandshakeUnix == 0 {
		return false
	}
	if now.Sub(time.Unix(s.UpdatedUnix, 0)) > statusFreshness {
		return false
	}
	return now.Sub(time.Unix(s.LastHandshakeUnix, 0)) <= handshakeFreshness
}

func statusPath(dir, gateway string) string {
	return filepath.Join(dir, gateway+".json")
}

// WriteStatus replaces a gateway's status file atomically.
func WriteStatus(dir string, status Status) error {
	data, err := json.Marshal(status)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "."+status.Gateway+".*.json")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(0o644); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), statusPath(dir, status.Gateway))
}

// ReadStatuses returns every gateway status file in dir, keyed by gateway. A
// missing directory means no gateways. Files that fail to parse or whose
// gateway/index are invalid are skipped.
func ReadStatuses(dir string) (map[string]Status, error) {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return map[string]Status{}, nil
	}
	if err != nil {
		return nil, err
	}
	statuses := map[string]Status{}
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || strings.HasPrefix(name, ".") || !strings.HasSuffix(name, ".json") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		var status Status
		if err := json.Unmarshal(data, &status); err != nil {
			continue
		}
		if status.Gateway != strings.TrimSuffix(name, ".json") ||
			ValidateGatewayName(status.Gateway) != nil ||
			ValidateIndex(status.Index) != nil ||
			status.Interface != InterfaceName(status.Index) {
			continue
		}
		statuses[status.Gateway] = status
	}
	return statuses, nil
}

// ParseCIDRs validates a list of IPv4 CIDRs or addresses and returns them
// sorted and de-duplicated in canonical form.
func ParseCIDRs(values []string) ([]string, error) {
	seen := map[string]bool{}
	for _, raw := range values {
		value := strings.TrimSpace(raw)
		if value == "" {
			continue
		}
		if !strings.Contains(value, "/") {
			value += "/32"
		}
		ip, network, err := net.ParseCIDR(value)
		if err != nil || ip.To4() == nil {
			return nil, fmt.Errorf("%q is not an IPv4 CIDR", raw)
		}
		seen[network.String()] = true
	}
	out := make([]string, 0, len(seen))
	for value := range seen {
		out = append(out, value)
	}
	sort.Strings(out)
	return out, nil
}

// IsTailnetIPv4 reports whether address is a Tailscale CGNAT address. The
// gateway accepts a host only from its tailnet address.
func IsTailnetIPv4(address string) bool {
	ip := net.ParseIP(address).To4()
	if ip == nil {
		return false
	}
	_, cgnat, _ := net.ParseCIDR("100.64.0.0/10")
	return cgnat.Contains(ip)
}
