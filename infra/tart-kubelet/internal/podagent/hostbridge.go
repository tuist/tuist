package podagent

import (
	"fmt"
	"net"
)

// HostBridgeIPForVM returns the host's own IPv4 on the vmnet bridge that carries
// vmIP — i.e. the address a runner VM uses to reach a process on the host. It
// finds the host interface whose directly-connected IPv4 subnet contains the
// VM's IP and returns that interface's address.
//
// This is the reverse of tart-kubelet's existing host->VM path (the metrics
// forwarder), and it is what lets a one-shot VM's cache client reach the
// persistent host Kura. Portable net APIs only — no darwin-specific scoping is
// needed to *find* the address (that scoping matters only when the host dials
// the VM).
func HostBridgeIPForVM(vmIP string) (string, error) {
	ip := net.ParseIP(vmIP)
	if ip == nil {
		return "", fmt.Errorf("invalid VM IP %q", vmIP)
	}
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", fmt.Errorf("list interfaces: %w", err)
	}
	for _, ifc := range ifaces {
		if ifc.Flags&net.FlagUp == 0 {
			continue
		}
		addrs, err := ifc.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok || ipnet.IP.To4() == nil {
				continue
			}
			if ipnet.Contains(ip) {
				return ipnet.IP.String(), nil
			}
		}
	}
	return "", fmt.Errorf("no host interface is directly connected to VM IP %s", vmIP)
}
