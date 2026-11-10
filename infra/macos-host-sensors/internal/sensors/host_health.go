package sensors

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// HostHealth complements the hardware sensors with the signals needed to find
// long-lived hosts on an old kernel. TIME_WAIT accumulation is a symptom, not a
// definitive diagnosis of a frozen TCP clock.
type HostHealth struct {
	ProductVersion string
	KernelRelease  string
	UptimeSeconds  *float64
	TCPTimeWait    *uint64
	Complete       bool
}

type hostCommand func(context.Context, string, ...string) ([]byte, error)

func hostCommandOutput(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.WaitDelay = time.Second
	return cmd.Output()
}

func readHostHealth(run hostCommand, now time.Time) (*HostHealth, []error) {
	h := &HostHealth{}
	var errs []error
	// Bound each source separately so a stalled command does not suppress the
	// other source or leave this one-shot launchd job running indefinitely.
	read := func(name string, args ...string) ([]byte, error) {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		return run(ctx, name, args...)
	}
	data, err := read("/usr/sbin/sysctl", "-n", "kern.osproductversion", "kern.osrelease", "kern.boottime")
	if err == nil {
		err = h.parseSystemInfo(string(data), now)
	}
	if err != nil {
		errs = append(errs, fmt.Errorf("host system info: %w", err))
	}
	data, err = read("/usr/sbin/netstat", "-an", "-p", "tcp")
	if err == nil {
		var count uint64
		count, err = parseTCPTimeWait(string(data))
		if err == nil {
			h.TCPTimeWait = &count
		}
	}
	if err != nil {
		errs = append(errs, fmt.Errorf("host TCP sockets: %w", err))
	}
	h.Complete = len(errs) == 0
	return h, errs
}

var hostVersionPattern = regexp.MustCompile(`^[0-9]+\.[0-9]+(?:\.[0-9]+)?$`)
var bootTimePattern = regexp.MustCompile(`^\{ sec = ([0-9]+), usec = [0-9]+ \}`)

func (h *HostHealth) parseSystemInfo(output string, now time.Time) error {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 3 || !hostVersionPattern.MatchString(lines[0]) || !hostVersionPattern.MatchString(lines[1]) {
		return fmt.Errorf("unexpected sysctl version/boot-time format")
	}
	boot := bootTimePattern.FindStringSubmatch(lines[2])
	if boot == nil {
		return fmt.Errorf("unexpected kern.boottime format")
	}
	seconds, err := strconv.ParseInt(boot[1], 10, 64)
	if err != nil || seconds <= 0 || seconds > now.Unix() {
		return fmt.Errorf("invalid kern.boottime seconds")
	}
	uptime := now.Sub(time.Unix(seconds, 0)).Seconds()
	h.ProductVersion, h.KernelRelease = lines[0], lines[1]
	h.UptimeSeconds = &uptime
	return nil
}

func parseTCPTimeWait(output string) (uint64, error) {
	var count uint64
	headerFound := false
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) > 0 && fields[0] == "Proto" && strings.Contains(line, "Foreign Address") {
			headerFound = true
		}
		if len(fields) >= 6 && (fields[0] == "tcp4" || fields[0] == "tcp6") && fields[len(fields)-1] == "TIME_WAIT" {
			count++
		}
	}
	if !headerFound {
		return 0, fmt.Errorf("unexpected netstat TCP table format")
	}
	return count, nil
}
