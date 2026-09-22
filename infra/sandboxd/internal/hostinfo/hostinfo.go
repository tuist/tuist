// Package hostinfo reads what the hello and report frames need from the
// pod: memory capacity and usage, CPU count and the pod's resolvers.
//
// Memory comes from the pod's own cgroup when it has a limit: every guest
// runs inside the daemon's cgroup, so that limit, not the node's MemTotal,
// is the wall the server places sandboxes against. Without a cgroup limit
// the node's meminfo is the fallback.
package hostinfo

import (
	"os"
	"runtime"
	"strconv"
	"strings"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
)

const (
	cgroupMemoryMax     = "/sys/fs/cgroup/memory.max"
	cgroupMemoryCurrent = "/sys/fs/cgroup/memory.current"
)

func Capacity() protocol.Capacity {
	total, ok := cgroupValue(cgroupMemoryMax)
	if !ok {
		total, _ = meminfo()
	}
	return protocol.Capacity{MemoryBytes: total, CPUs: runtime.NumCPU()}
}

func MemoryUsed() uint64 {
	if used, ok := cgroupValue(cgroupMemoryCurrent); ok {
		return used
	}
	total, available := meminfo()
	if total < available {
		return 0
	}
	return total - available
}

func cgroupValue(path string) (uint64, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	return ParseCgroupValue(string(data))
}

// ParseCgroupValue reads a cgroup v2 memory file. "max" means no limit and
// reports false so the caller falls back to the node's memory.
func ParseCgroupValue(text string) (uint64, bool) {
	text = strings.TrimSpace(text)
	if text == "" || text == "max" {
		return 0, false
	}
	value, err := strconv.ParseUint(text, 10, 64)
	if err != nil {
		return 0, false
	}
	return value, true
}

func meminfo() (total, available uint64) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	return ParseMeminfo(string(data))
}

// ParseMeminfo returns MemTotal and MemAvailable in bytes.
func ParseMeminfo(text string) (total, available uint64) {
	for _, line := range strings.Split(text, "\n") {
		key, rest, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		fields := strings.Fields(rest)
		if len(fields) == 0 {
			continue
		}
		value, err := strconv.ParseUint(fields[0], 10, 64)
		if err != nil {
			continue
		}
		if len(fields) > 1 && strings.EqualFold(fields[1], "kB") {
			value *= 1024
		}
		switch key {
		case "MemTotal":
			total = value
		case "MemAvailable":
			available = value
		}
	}
	return total, available
}

// Resolvers lists the pod's nameservers from /etc/resolv.conf.
func Resolvers() []string {
	data, err := os.ReadFile("/etc/resolv.conf")
	if err != nil {
		return nil
	}
	return ParseResolvConf(string(data))
}

func ParseResolvConf(text string) []string {
	var servers []string
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[0] == "nameserver" {
			servers = append(servers, fields[1])
		}
	}
	return servers
}
