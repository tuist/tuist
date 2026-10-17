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
	"path/filepath"
	"runtime"
	"strconv"
	"strings"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
)

const (
	cgroupRoot     = "/sys/fs/cgroup"
	procSelfCgroup = "/proc/self/cgroup"
)

func Capacity() protocol.Capacity {
	total, ok := cgroupValue("memory.max", true)
	if !ok {
		total, _ = meminfo()
	}
	return protocol.Capacity{MemoryBytes: total, CPUs: runtime.NumCPU()}
}

func MemoryUsed() uint64 {
	if used, ok := cgroupValue("memory.current", false); ok {
		return used
	}
	total, available := meminfo()
	if total < available {
		return 0
	}
	return total - available
}

// cgroupValue reads a memory file of the process's own cgroup v2 directory.
// Without a cgroup namespace the container sees the host hierarchy and
// /proc/self/cgroup names its directory under the root; with a private
// namespace the path is "/" and the file sits at the root. A limit of
// "max" at the leaf falls through to the ancestors when walkUp is set,
// since the pod slice carries the limit the container itself may lack.
func cgroupValue(file string, walkUp bool) (uint64, bool) {
	data, err := os.ReadFile(procSelfCgroup)
	if err != nil {
		return 0, false
	}
	return ReadCgroupValue(cgroupRoot, ParseCgroupPath(string(data)), file, walkUp)
}

func ReadCgroupValue(root, path, file string, walkUp bool) (uint64, bool) {
	for {
		if data, err := os.ReadFile(filepath.Join(root, path, file)); err == nil {
			if value, ok := ParseCgroupValue(string(data)); ok {
				return value, true
			}
		}
		if !walkUp || path == "/" || path == "." || path == "" {
			return 0, false
		}
		path = filepath.Dir(path)
	}
}

// ParseCgroupPath returns the cgroup v2 path of /proc/self/cgroup (the
// "0::" line), or "/" when there is none.
func ParseCgroupPath(text string) string {
	for _, line := range strings.Split(text, "\n") {
		if path, ok := strings.CutPrefix(line, "0::"); ok && path != "" {
			return strings.TrimSpace(path)
		}
	}
	return "/"
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
