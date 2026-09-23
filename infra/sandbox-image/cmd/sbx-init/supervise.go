//go:build linux

package main

import (
	"log/slog"
	"os"
	osexec "os/exec"
	"os/signal"
	"time"

	"golang.org/x/sys/unix"

	"github.com/tuist/tuist/infra/sandbox-image/internal/guest"
)

const (
	minBackoff = time.Second
	maxBackoff = 30 * time.Second
	// A run at least this long resets the backoff: the agent was healthy.
	healthyRun = time.Minute
)

type supervisor struct {
	log       *slog.Logger
	path      string
	pid       int
	startedAt time.Time
	backoff   time.Duration
}

// supervise keeps sbx-agent running, reaps every orphan that gets reparented
// to PID 1 and powers the VM off on SIGTERM or SIGINT. It never returns.
func supervise(log *slog.Logger) {
	sigs := make(chan os.Signal, 16)
	signal.Notify(sigs, unix.SIGCHLD, unix.SIGTERM, unix.SIGINT)

	s := &supervisor{log: log, path: agentPath, backoff: minBackoff}
	restart := time.NewTimer(0)
	// SIGCHLD can coalesce, so also sweep on a timer.
	sweep := time.NewTicker(5 * time.Second)
	for {
		select {
		case sig := <-sigs:
			switch sig {
			case unix.SIGCHLD:
				s.reap(restart)
			case unix.SIGTERM, unix.SIGINT:
				s.shutdown()
			}
		case <-sweep.C:
			s.reap(restart)
		case <-restart.C:
			s.start(restart)
		}
	}
}

func (s *supervisor) start(restart *time.Timer) {
	cmd := osexec.Command(s.path)
	cmd.Env = []string{"PATH=" + defaultPath, "HOME=/root", "LANG=C.UTF-8"}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		s.log.Error("start sbx-agent", slog.Any("error", err))
		restart.Reset(s.nextBackoff())
		return
	}
	s.pid = cmd.Process.Pid
	s.startedAt = time.Now()
	// The reaper collects it; nothing here will call Wait.
	_ = cmd.Process.Release()
	s.log.Info("started sbx-agent", slog.Int("pid", s.pid))
}

// reap collects every exited child. Zombies from exec'd commands and the
// agent itself both land here; only the agent's exit schedules a restart.
func (s *supervisor) reap(restart *time.Timer) {
	for {
		var status unix.WaitStatus
		pid, err := unix.Wait4(-1, &status, unix.WNOHANG, nil)
		if err == unix.EINTR {
			continue
		}
		if err != nil || pid <= 0 {
			return
		}
		if pid != s.pid {
			continue
		}
		ran := time.Since(s.startedAt)
		s.log.Warn("sbx-agent exited",
			slog.Int("pid", pid),
			slog.Int("exit_status", status.ExitStatus()),
			slog.Bool("signaled", status.Signaled()),
			slog.Duration("ran", ran))
		s.pid = 0
		if ran >= healthyRun {
			s.backoff = minBackoff
		}
		restart.Reset(s.nextBackoff())
	}
}

func (s *supervisor) nextBackoff() time.Duration {
	delay := s.backoff
	s.backoff = min(s.backoff*2, maxBackoff)
	return delay
}

func (s *supervisor) shutdown() {
	s.log.Info("powering off")
	if s.pid > 0 {
		_ = unix.Kill(s.pid, unix.SIGTERM)
		s.waitFor(s.pid, 3*time.Second)
	}
	_ = unix.Kill(-1, unix.SIGTERM)
	time.Sleep(time.Second)
	_ = unix.Kill(-1, unix.SIGKILL)
	s.drain()
	if err := unix.Unmount(guest.WorkspaceMount, 0); err != nil && err != unix.EINVAL && err != unix.ENOENT {
		s.log.Warn("unmount workspace", slog.Any("error", err))
	}
	unix.Sync()
	if err := unix.Reboot(unix.LINUX_REBOOT_CMD_POWER_OFF); err != nil {
		s.log.Error("power off", slog.Any("error", err))
	}
}

func (s *supervisor) waitFor(pid int, timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		var status unix.WaitStatus
		got, err := unix.Wait4(pid, &status, unix.WNOHANG, nil)
		if got == pid || (err != nil && err != unix.EINTR) {
			s.pid = 0
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	_ = unix.Kill(pid, unix.SIGKILL)
}

func (s *supervisor) drain() {
	for {
		var status unix.WaitStatus
		pid, err := unix.Wait4(-1, &status, unix.WNOHANG, nil)
		if err == unix.EINTR {
			continue
		}
		if err != nil || pid <= 0 {
			return
		}
	}
}
