package driver

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// Runner executes host commands. stdin carries key material for cryptsetup,
// so implementations must never log or persist it.
type Runner interface {
	Run(ctx context.Context, stdin []byte, name string, args ...string) ([]byte, error)
}

// CommandError is returned by a Runner when a command exits non-zero.
type CommandError struct {
	Command  string
	ExitCode int
	Stderr   string
}

func (e *CommandError) Error() string {
	return fmt.Sprintf("%s exited with %d: %s", e.Command, e.ExitCode, strings.TrimSpace(e.Stderr))
}

func exitCode(err error) (int, bool) {
	var cmdErr *CommandError
	if errors.As(err, &cmdErr) {
		return cmdErr.ExitCode, true
	}
	return 0, false
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, stdin []byte, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return stdout.Bytes(), nil
	}
	command := strings.Join(append([]string{name}, args...), " ")
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return stdout.Bytes(), &CommandError{Command: command, ExitCode: exitErr.ExitCode(), Stderr: stderr.String()}
	}
	return stdout.Bytes(), fmt.Errorf("%s: %w", command, err)
}

type Mount struct {
	MajorMinor string
	MountPoint string
	FSType     string
	Source     string
}

type MountTable interface {
	Mounts() ([]Mount, error)
}

type ProcMountTable struct {
	Path string
}

func (t ProcMountTable) Mounts() ([]Mount, error) {
	f, err := os.Open(t.Path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return ParseMountInfo(f)
}

// ParseMountInfo parses the proc(5) mountinfo format.
func ParseMountInfo(r io.Reader) ([]Mount, error) {
	var mounts []Mount
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		separator := -1
		for i := 6; i < len(fields); i++ {
			if fields[i] == "-" {
				separator = i
				break
			}
		}
		if len(fields) < 6 || separator < 0 || len(fields) < separator+3 {
			return nil, fmt.Errorf("malformed mountinfo line %q", scanner.Text())
		}
		mounts = append(mounts, Mount{
			MajorMinor: fields[2],
			MountPoint: unescapeMountField(fields[4]),
			FSType:     fields[separator+1],
			Source:     unescapeMountField(fields[separator+2]),
		})
	}
	return mounts, scanner.Err()
}

func unescapeMountField(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+3 < len(s) {
			if v, err := strconv.ParseUint(s[i+1:i+4], 8, 8); err == nil {
				b.WriteByte(byte(v))
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

type FSStats struct {
	TotalBytes      int64
	AvailableBytes  int64
	UsedBytes       int64
	TotalInodes     int64
	AvailableInodes int64
	UsedInodes      int64
}

// Host reads filesystem and device metadata.
type Host interface {
	FSStats(path string) (FSStats, error)
	// DeviceNumber returns the "major:minor" of a block device node.
	DeviceNumber(path string) (string, error)
}
