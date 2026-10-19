//go:build linux

package guest

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"golang.org/x/sys/unix"

	"github.com/tuist/tuist/infra/sandbox-image/internal/agent"
	"github.com/tuist/tuist/infra/sandbox-image/internal/sysconfig"
)

type System struct {
	Logger *slog.Logger
	// Root prefixes the rendered config files; empty means "/".
	Root string
}

func (s *System) Uptime() (time.Duration, error) {
	var ts unix.Timespec
	if err := unix.ClockGettime(unix.CLOCK_BOOTTIME, &ts); err != nil {
		return 0, err
	}
	return time.Duration(ts.Nano()), nil
}

func (s *System) SetTime(t time.Time) error {
	ts := unix.NsecToTimespec(t.UnixNano())
	return unix.ClockSettime(unix.CLOCK_REALTIME, &ts)
}

func (s *System) Configure(ctx context.Context, spec agent.ConfigureSpec) error {
	if spec.Hostname != "" {
		if err := SetHostname(s.root(), spec.Hostname); err != nil {
			return err
		}
	}
	if len(spec.DNS) > 0 {
		if err := sysconfig.WriteResolvConf(s.root(), spec.DNS); err != nil {
			return fmt.Errorf("resolv.conf: %w", err)
		}
	}
	// A resume recreates the tap with the same addresses but a fresh MAC on
	// the host side, so anything the guest learned before the pause is stale.
	if err := FlushNeighbors(Interface); err != nil {
		return fmt.Errorf("flush neighbours on %s: %w", Interface, err)
	}
	return EnsureWorkspace(ctx, WorkspaceDevice, WorkspaceMount, spec.FormatWorkspace)
}

func (s *System) root() string {
	if s.Root == "" {
		return "/"
	}
	return s.Root
}

// SetHostname applies the kernel hostname and renders /etc/hostname and
// /etc/hosts under root.
func SetHostname(root, hostname string) error {
	if err := unix.Sethostname([]byte(hostname)); err != nil {
		return fmt.Errorf("sethostname: %w", err)
	}
	if err := sysconfig.WriteHostname(root, hostname); err != nil {
		return fmt.Errorf("hostname file: %w", err)
	}
	if err := sysconfig.WriteHosts(root, hostname); err != nil {
		return fmt.Errorf("hosts file: %w", err)
	}
	return nil
}
