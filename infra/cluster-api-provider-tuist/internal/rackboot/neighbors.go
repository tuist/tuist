package rackboot

import (
	"bufio"
	"io"
	"net"
	"os"
	"strings"
)

// NeighborsPath is the kernel's IPv4 neighbor table, which on the edge's host
// network holds the MAC behind each address on its segments.
const NeighborsPath = "/proc/net/arp"

// Neighbors looks up the MAC behind an address on the boot server's segment.
type Neighbors func(ip net.IP) (mac string, ok bool)

// ProcNeighbors reads the kernel's neighbor table on every lookup: a machine
// that just connected is in it, since the kernel resolved its MAC to answer.
func ProcNeighbors(ip net.IP) (string, bool) {
	f, err := os.Open(NeighborsPath)
	if err != nil {
		return "", false
	}
	defer f.Close()
	return lookupNeighbor(f, ip)
}

// lookupNeighbor finds ip's MAC in a table in /proc/net/arp's format, skipping
// entries the kernel has not resolved.
func lookupNeighbor(table io.Reader, ip net.IP) (string, bool) {
	scanner := bufio.NewScanner(table)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 4 || !net.ParseIP(fields[0]).Equal(ip) {
			continue
		}
		hw, err := net.ParseMAC(fields[3])
		if err != nil || fields[2] == "0x0" || hw.String() == "00:00:00:00:00:00" {
			continue
		}
		return hw.String(), true
	}
	return "", false
}
