// Command tart-cni is the CNI plugin invoked by kubelet when setting
// up Pod networking on a Mac mini node.
//
// What it does in this implementation:
//   - On ADD: assigns the Pod a host-routable IPv4 from the per-host
//     pod CIDR (carved out of the cluster CIDR) and reports it back
//     to kubelet via the standard CNI result struct.
//   - On DEL: releases the IP from the IPAM store.
//   - On CHECK: re-runs ADD's allocation read to verify state.
//
// What it deliberately doesn't do yet:
//   - Cross-host pod-to-pod routing. We rely on the CNI plugin chain
//     pattern: a follow-up plugin (WireGuard or similar) handles
//     cross-host overlay. This plugin's job is just IPAM + signaling
//     the IP back to kubelet so PodStatus.PodIP populates.
//   - kube-proxy-equivalent. Mac mini Pods can't yet be hit by
//     in-cluster Services. They can egress freely, and other Pods on
//     the *same* Mac mini can reach each other.
//
// State: line-delimited JSON at /var/lib/tart-cri/cni-ipam.json,
// guarded by a flock so concurrent kubelet invocations serialize.
package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"syscall"

	"github.com/containernetworking/cni/pkg/skel"
	cnitypes "github.com/containernetworking/cni/pkg/types"
	current "github.com/containernetworking/cni/pkg/types/100"
	"github.com/containernetworking/cni/pkg/version"
)

const ipamStatePath = "/var/lib/tart-cri/cni-ipam.json"

type netConf struct {
	cnitypes.NetConf
	// PodCIDR is the slice of cluster CIDR this Mac mini owns. Set in
	// the CNI config that kubelet writes during bootstrap.
	PodCIDR string `json:"podCIDR"`
}

type allocation struct {
	IP            string `json:"ip"`
	ContainerID   string `json:"container_id"`
	InterfaceName string `json:"interface_name"`
}

func main() {
	skel.PluginMainFuncs(
		skel.CNIFuncs{Add: cmdAdd, Del: cmdDel, Check: cmdCheck},
		version.All,
		"tart-cni",
	)
}

func cmdAdd(args *skel.CmdArgs) error {
	conf, err := parseConfig(args.StdinData)
	if err != nil {
		return err
	}

	ip, err := allocateIP(conf, args.ContainerID, args.IfName)
	if err != nil {
		return err
	}

	res := &current.Result{
		CNIVersion: current.ImplementedSpecVersion,
		IPs: []*current.IPConfig{{
			Address: net.IPNet{IP: ip, Mask: ipMask(conf)},
		}},
	}
	return cnitypes.PrintResult(res, conf.CNIVersion)
}

func cmdDel(args *skel.CmdArgs) error {
	return releaseIP(args.ContainerID)
}

func cmdCheck(args *skel.CmdArgs) error {
	allocs, err := loadAllocations()
	if err != nil {
		return err
	}
	for _, a := range allocs {
		if a.ContainerID == args.ContainerID {
			return nil
		}
	}
	return fmt.Errorf("no allocation found for container %s", args.ContainerID)
}

func parseConfig(stdin []byte) (*netConf, error) {
	c := &netConf{}
	if err := json.Unmarshal(stdin, c); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	if c.PodCIDR == "" {
		return nil, fmt.Errorf("podCIDR is required")
	}
	return c, nil
}

func allocateIP(conf *netConf, containerID, ifName string) (net.IP, error) {
	if err := os.MkdirAll(filepath.Dir(ipamStatePath), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(ipamStatePath, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return nil, err
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	allocs, err := readAllocations(f)
	if err != nil {
		return nil, err
	}

	// Idempotent: if this container already has an allocation, return it.
	for _, a := range allocs {
		if a.ContainerID == containerID {
			return net.ParseIP(a.IP), nil
		}
	}

	_, ipNet, err := net.ParseCIDR(conf.PodCIDR)
	if err != nil {
		return nil, err
	}
	used := map[string]bool{}
	for _, a := range allocs {
		used[a.IP] = true
	}

	// Skip .0 (network) and .1 (gateway).
	candidate := nextIP(ipNet.IP)
	candidate = nextIP(candidate)
	for ipNet.Contains(candidate) {
		if !used[candidate.String()] {
			break
		}
		candidate = nextIP(candidate)
	}
	if !ipNet.Contains(candidate) {
		return nil, fmt.Errorf("pod CIDR %s exhausted", conf.PodCIDR)
	}

	allocs = append(allocs, allocation{
		IP:            candidate.String(),
		ContainerID:   containerID,
		InterfaceName: ifName,
	})
	if err := writeAllocations(f, allocs); err != nil {
		return nil, err
	}
	return candidate, nil
}

func releaseIP(containerID string) error {
	f, err := os.OpenFile(ipamStatePath, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	allocs, err := readAllocations(f)
	if err != nil {
		return err
	}
	out := allocs[:0]
	for _, a := range allocs {
		if a.ContainerID != containerID {
			out = append(out, a)
		}
	}
	return writeAllocations(f, out)
}

func loadAllocations() ([]allocation, error) {
	f, err := os.Open(ipamStatePath)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return readAllocations(f)
}

func readAllocations(f *os.File) ([]allocation, error) {
	if _, err := f.Seek(0, 0); err != nil {
		return nil, err
	}
	var allocs []allocation
	dec := json.NewDecoder(f)
	if err := dec.Decode(&allocs); err != nil {
		// Empty file or stale state — treat as empty.
		return nil, nil //nolint:nilerr
	}
	return allocs, nil
}

func writeAllocations(f *os.File, allocs []allocation) error {
	if err := f.Truncate(0); err != nil {
		return err
	}
	if _, err := f.Seek(0, 0); err != nil {
		return err
	}
	return json.NewEncoder(f).Encode(allocs)
}

func ipMask(conf *netConf) net.IPMask {
	_, ipNet, _ := net.ParseCIDR(conf.PodCIDR)
	return ipNet.Mask
}

func nextIP(ip net.IP) net.IP {
	out := make(net.IP, len(ip))
	copy(out, ip)
	for i := len(out) - 1; i >= 0; i-- {
		out[i]++
		if out[i] != 0 {
			break
		}
	}
	return out
}
