// Package hostinfo reads what the hello and report frames need from the
// pod: memory capacity and usage, CPU count and the pod's resolvers.
package hostinfo

import (
	"os"
	"runtime"
	"strconv"
	"strings"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
)

func Capacity() protocol.Capacity {
	total, _ := meminfo()
	return protocol.Capacity{MemoryBytes: total, CPUs: runtime.NumCPU()}
}

func MemoryUsed() uint64 {
	total, available := meminfo()
	if total < available {
		return 0
	}
	return total - available
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
