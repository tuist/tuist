package netdev

import (
	"errors"
	"fmt"
	"net/netip"
	"os"
	"strings"
)

type LinkSpec struct {
	Name    string
	MTU     int
	Address netip.Prefix
	Route   netip.Prefix
}

// Link creates and converges the WireGuard interface, its address and its
// route.
type Link interface {
	Ensure(spec LinkSpec) error
}

var ErrUnsupported = errors.New("not supported on this platform")

const IPv4ForwardPath = "/proc/sys/net/ipv4/ip_forward"

// Forwarding enables IPv4 forwarding through a sysctl file and reports whether
// it is enabled afterwards. A failed write is not an error when the value is
// already 1, since /proc/sys is read-only in most containers and the sysctl
// may have been set by the pod spec.
type Forwarding struct {
	Path string
}

func (f Forwarding) Ensure() (bool, error) {
	path := f.Path
	if path == "" {
		path = IPv4ForwardPath
	}
	if enabled, err := readFlag(path); err == nil && enabled {
		return true, nil
	}
	writeErr := os.WriteFile(path, []byte("1\n"), 0o644)
	enabled, readErr := readFlag(path)
	if readErr != nil {
		return false, readErr
	}
	if !enabled {
		if writeErr != nil {
			return false, fmt.Errorf("%s is 0 and could not be set: %w", path, writeErr)
		}
		return false, fmt.Errorf("%s is still 0 after writing 1", path)
	}
	return true, nil
}

func readFlag(path string) (bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(string(data)) == "1", nil
}
