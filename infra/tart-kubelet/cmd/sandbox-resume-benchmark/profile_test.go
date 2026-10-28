package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func profileFixture() []profileEvent {
	names := []string{"run_enter", "restore_started", "restore_finished", "state_removed", "resume_started", "resume_finished", "control_ready"}
	var events []profileEvent
	for i, name := range names {
		events = append(events, profileEvent{Event: name, PID: 42, UptimeNS: uint64(i+1) * 1e6, CPUUS: int64(i) * 100})
	}
	return events
}

func profileText(events []profileEvent) string {
	var text strings.Builder
	text.WriteString("ordinary Tart output\n")
	for _, event := range events {
		b, _ := json.Marshal(event)
		text.WriteString("TUIST_RESUME_PROFILE " + string(b) + "\n")
	}
	return text.String()
}

func TestProfileRejectsMisleadingTimings(t *testing.T) {
	for _, mutation := range []string{"missing", "duplicate", "mixed_pid", "backward_clock", "wrong_order"} {
		t.Run(mutation, func(t *testing.T) {
			events := profileFixture()
			switch mutation {
			case "missing":
				events = events[:len(events)-1]
			case "duplicate":
				events = append(events, events[len(events)-1])
			case "mixed_pid":
				events[2].PID++
			case "backward_clock":
				events[2].UptimeNS = 1
			case "wrong_order":
				events[1].Event, events[2].Event = events[2].Event, events[1].Event
			}
			if _, err := parseRuntimeProfile(strings.NewReader(profileText(events))); err == nil {
				t.Fatal("accepted unreliable phase measurements")
			}
		})
	}
}

func TestProfileReadsOnlyCurrentLaunch(t *testing.T) {
	path := filepath.Join(t.TempDir(), "vm.log")
	old := profileText(profileFixture())
	if err := os.WriteFile(path, []byte(old+profileText(profileFixture())), 0600); err != nil {
		t.Fatal(err)
	}
	p, err := readRuntimeProfile(t.Context(), path, int64(len(old)))
	if err != nil || p == nil {
		t.Fatalf("profile: %v, %v", p, err)
	}
	if p.RestoreAPIMS != 1 || p.ResumeAPIMS != 1 || p.RestoreCPUUS != 100 {
		t.Fatalf("incorrect call duration: %+v", p)
	}
	p, err = parseRuntimeProfile(strings.NewReader("unmodified runtime\n"))
	if err != nil || p != nil {
		t.Fatalf("invented measurements for uninstrumented binary: %v, %v", p, err)
	}
}

func TestProfileWaitsForDelayedLogDelivery(t *testing.T) {
	t.Setenv("TUIST_TART_PROFILE", "1")
	full := profileText(profileFixture())
	for _, prefix := range []string{"", full[:len(full)-12]} {
		path := filepath.Join(t.TempDir(), "vm.log")
		if err := os.WriteFile(path, []byte(prefix), 0600); err != nil {
			t.Fatal(err)
		}
		done := make(chan error, 1)
		go func() {
			profile, err := readRuntimeProfile(t.Context(), path, 0)
			if err == nil && profile == nil {
				err = errors.New("missing expected profile")
			}
			done <- err
		}()
		select {
		case err := <-done:
			t.Fatalf("returned before complete log delivery: %v", err)
		case <-time.After(30 * time.Millisecond):
		}
		f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0600)
		if err != nil {
			t.Fatal(err)
		}
		_, err = f.WriteString(full[len(prefix):])
		closeErr := f.Close()
		if err != nil || closeErr != nil {
			t.Fatalf("append: %v, close: %v", err, closeErr)
		}
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}
}

func TestProfileWaitHonorsDeadline(t *testing.T) {
	t.Setenv("TUIST_TART_PROFILE", "1")
	path := filepath.Join(t.TempDir(), "vm.log")
	if err := os.WriteFile(path, nil, 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Millisecond)
	defer cancel()
	if _, err := readRuntimeProfile(ctx, path, 0); !errors.Is(err, context.DeadlineExceeded) || !errors.Is(err, errIncompleteProfile) {
		t.Fatalf("expected bounded incomplete profile error: %v", err)
	}
}

func TestUninstrumentedPartialLogDoesNotRequireProfile(t *testing.T) {
	t.Setenv("TUIST_TART_PROFILE", "")
	path := filepath.Join(t.TempDir(), "vm.log")
	if err := os.WriteFile(path, []byte("ordinary output without a newline"), 0600); err != nil {
		t.Fatal(err)
	}
	profile, err := readRuntimeProfile(t.Context(), path, 0)
	if err != nil || profile != nil {
		t.Fatalf("uninstrumented log: %v, %v", profile, err)
	}
}

func TestReadAheadHonorsCancellationAndPreservesSnapshot(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state")
	if err := os.WriteFile(path, []byte("saved state"), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if err := readSnapshot(ctx, path); err != context.Canceled {
		t.Fatalf("cancellation: %v", err)
	}
	if err := readSnapshot(t.Context(), path); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "saved state" {
		t.Fatalf("read ahead changed snapshot: %q, %v", data, err)
	}
}

func TestOpenControlSocketIsNotGuestReadiness(t *testing.T) {
	// Keep the Unix socket path below macOS's 104-byte limit.
	home, err := os.MkdirTemp("/tmp", "resume-probe-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(home)
	dir := filepath.Join(home, "vms", "vm")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("unix", filepath.Join(dir, "control.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	c := &tart.Client{HomeDir: home, Binary: "/usr/bin/false"}
	if err := probeGuest(t.Context(), c, "vm", true, nil); err == nil {
		t.Fatal("open host socket incorrectly counted as guest readiness")
	}
	previous, err := os.Stat(filepath.Join(dir, "control.sock"))
	if err != nil {
		t.Fatal(err)
	}
	c.Binary = "/usr/bin/true"
	if err := probeGuest(t.Context(), c, "vm", true, previous); err == nil {
		t.Fatal("accepted the previous launch's stale control socket")
	}
}
