//go:build linux

// sbx-init is PID 1 of the Firecracker guest. It mounts the pseudo
// filesystems, names and networks the guest from the kernel command line,
// then supervises sbx-agent for the life of the VM.
package main

import (
	"log/slog"
	"os"
	"strings"
	"time"

	"golang.org/x/sys/unix"

	"github.com/tuist/tuist/infra/sandbox-image/internal/guest"
	"github.com/tuist/tuist/infra/sandbox-image/internal/sysconfig"
)

const (
	agentPath    = "/usr/local/bin/sbx-agent"
	guestCIDR    = "10.0.0.2/30"
	guestGateway = "10.0.0.1"
	defaultPath  = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
)

func main() {
	log := newLogger(os.Stderr)
	if os.Getpid() != 1 {
		log.Warn("not running as PID 1")
	}
	os.Setenv("PATH", defaultPath)

	mountFilesystems(log)
	log = attachKmsg(log)

	// Firecracker's SendCtrlAltDel then reaches us as SIGINT instead of a
	// hard reboot.
	if err := unix.Reboot(unix.LINUX_REBOOT_CMD_CAD_OFF); err != nil {
		log.Warn("could not take over ctrl-alt-del", slog.Any("error", err))
	}

	cmdline := readCmdline(log)
	hostname := sysconfig.HostnameFromCmdline(cmdline)
	if err := guest.SetHostname("/", hostname); err != nil {
		log.Error("hostname", slog.Any("error", err))
	}
	dns := sysconfig.DNSFromCmdline(cmdline)
	if err := sysconfig.WriteResolvConf("/", dns); err != nil {
		log.Error("resolv.conf", slog.Any("error", err))
	}
	for _, dir := range []string{guest.WorkspaceMount, guest.MemoryMount} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			log.Error("mkdir", slog.String("dir", dir), slog.Any("error", err))
		}
	}
	if err := guest.ConfigureNetwork(guest.Interface, guestCIDR, guestGateway, 10*time.Second); err != nil {
		log.Error("network", slog.Any("error", err))
	}
	log.Info("guest ready",
		slog.String("hostname", hostname),
		slog.String("dns", strings.Join(dns, ",")),
		slog.String("address", guestCIDR))

	supervise(log)
}

func readCmdline(log *slog.Logger) map[string]string {
	raw, err := os.ReadFile("/proc/cmdline")
	if err != nil {
		log.Error("read /proc/cmdline", slog.Any("error", err))
		return map[string]string{}
	}
	return sysconfig.ParseCmdline(string(raw))
}
