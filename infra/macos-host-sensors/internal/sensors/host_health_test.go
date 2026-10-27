package sensors

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

const tcpTable = `Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
tcp4       0      0  192.0.2.1.22           192.0.2.2.1234         ESTABLISHED
tcp4       0      0  192.0.2.1.22           192.0.2.2.1235         TIME_WAIT
tcp6       0      0  ::1.1234               ::1.1235               TIME_WAIT
tcp4       0      0  *.22                   *.*                    LISTEN
`

func TestHostHealthReadsUptimeAndBothTCPFamilies(t *testing.T) {
	now := time.Unix(1800000000, 0)
	var calls int
	h, errs := readHostHealth(func(ctx context.Context, name string, args ...string) ([]byte, error) {
		calls++
		deadline, ok := ctx.Deadline()
		if !ok || time.Until(deadline) > 3*time.Second {
			t.Fatal("host command has no bounded deadline")
		}
		if name == "/usr/sbin/sysctl" {
			return []byte("26.3.2\n25.3.0\n{ sec = 1791360000, usec = 123 } old boot date\n"), nil
		}
		return []byte(tcpTable), nil
	}, now)
	if len(errs) != 0 || !h.Complete || calls != 2 || *h.UptimeSeconds != 100*24*60*60 || *h.TCPTimeWait != 2 {
		t.Fatalf("health = %+v, errors = %v, calls = %d", h, errs, calls)
	}
	metrics := Format(Readings{HostHealth: h})
	for _, want := range []string{
		"macos_host_health_collection_success 1\n",
		"macos_host_info{product_version=\"26.3.2\",kernel_release=\"25.3.0\"} 1\n",
		"macos_host_uptime_seconds 8.64e+06\n",
		"macos_host_tcp_time_wait 2\n",
	} {
		if !strings.Contains(metrics, want) {
			t.Errorf("missing %q in %s", want, metrics)
		}
	}
}

func TestHostHealthKeepsIndependentSourcesAndReportsFailure(t *testing.T) {
	for _, fail := range []string{"sysctl", "netstat"} {
		t.Run(fail, func(t *testing.T) {
			h, errs := readHostHealth(func(_ context.Context, name string, _ ...string) ([]byte, error) {
				if strings.HasSuffix(name, fail) {
					return nil, context.DeadlineExceeded
				}
				if strings.HasSuffix(name, "sysctl") {
					return []byte("26.6.2\n25.6.0\n{ sec = 1791360000, usec = 0 } date"), nil
				}
				return []byte(tcpTable), nil
			}, time.Unix(1800000000, 0))
			if h.Complete || len(errs) != 1 || !errors.Is(errs[0], context.DeadlineExceeded) {
				t.Fatalf("failed source hidden: %+v, %v", h, errs)
			}
			metrics := Format(Readings{HostHealth: h})
			if !strings.Contains(metrics, "macos_host_health_collection_success 0\n") {
				t.Fatal(metrics)
			}
			if fail == "sysctl" && (h.UptimeSeconds != nil || h.TCPTimeWait == nil || strings.Contains(metrics, "macos_host_info")) {
				t.Fatalf("failed sysctl lost TCP reading or emitted false system info: %s", metrics)
			}
			if fail == "netstat" && (h.UptimeSeconds == nil || h.TCPTimeWait != nil || strings.Contains(metrics, "macos_host_tcp_time_wait")) {
				t.Fatalf("failed netstat lost system info or emitted a false zero: %s", metrics)
			}
		})
	}
}

func TestHostSystemInfoRejectsMalformedAndFutureBootTimes(t *testing.T) {
	for _, data := range []string{
		"", "26.3.2\n25.3.0", "unknown\n25.3.0\n{ sec = 100, usec = 0 }",
		"26.3.2\n25.3.0\nnot a boot time", "26.3.2\n25.3.0\n{ sec = 2000000000, usec = 0 }",
		"26.3.2\n25.3.0\n{ sec = 99999999999999999999999, usec = 0 }",
	} {
		h := &HostHealth{}
		if err := h.parseSystemInfo(data, time.Unix(1800000000, 0)); err == nil || h.UptimeSeconds != nil {
			t.Fatalf("accepted malformed system info %q", data)
		}
	}
}

func TestTCPTimeWaitDistinguishesEmptyTableFromFailedRead(t *testing.T) {
	for _, output := range []string{"", "netstat: permission denied\n"} {
		if _, err := parseTCPTimeWait(output); err == nil {
			t.Fatalf("interpreted invalid output %q as healthy", output)
		}
	}
	count, err := parseTCPTimeWait("Proto Recv-Q Send-Q  Local Address  Foreign Address  (state)\n")
	if err != nil || count != 0 {
		t.Fatalf("empty TCP table = %d, %v", count, err)
	}
}
