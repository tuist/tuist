package racknode

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// LocalHost is the node as a process sees it: its own filesystem and
// commands when Root is empty, as when the operator runs the apply over SSH,
// or, from the node agent's privileged pod, the host's filesystem under Root
// (/proc/1/root) and commands run in the host's namespaces through its own
// nsenter.
type LocalHost struct {
	Root string
}

// path is p on the host, with every symlink on the way resolved as the host
// resolves it: an absolute target from Root, not from this process's root.
func (h LocalHost) path(p string) string {
	if h.Root == "" {
		return p
	}
	resolved, err := resolveIn(h.Root, p)
	if err != nil {
		return filepath.Join(h.Root, p)
	}
	return resolved
}

// entry is p on the host with its directory resolved as path resolves it and
// its last element kept, so a write or removal acts on a symlink itself.
func (h LocalHost) entry(p string) string {
	if h.Root == "" {
		return p
	}
	return filepath.Join(h.path(filepath.Dir(p)), filepath.Base(p))
}

// resolveIn joins p onto root, following symlinks inside root. A path that
// does not exist yet is joined as it is from where it stops existing.
func resolveIn(root, p string) (string, error) {
	pending := strings.Split(filepath.Clean("/"+p), "/")[1:]
	current := "/"
	for hops := 0; len(pending) > 0; {
		part := pending[0]
		pending = pending[1:]
		switch part {
		case "", ".":
			continue
		case "..":
			current = filepath.Dir(current)
			continue
		}
		next := filepath.Join(current, part)
		info, err := os.Lstat(filepath.Join(root, next))
		if err != nil {
			current = filepath.Join(append([]string{next}, pending...)...)
			break
		}
		if info.Mode()&fs.ModeSymlink == 0 {
			current = next
			continue
		}
		if hops++; hops > 40 {
			return "", fmt.Errorf("too many symlinks in %s", p)
		}
		target, err := os.Readlink(filepath.Join(root, next))
		if err != nil {
			return "", err
		}
		if !filepath.IsAbs(target) {
			target = filepath.Join(current, target)
		}
		pending = append(strings.Split(filepath.Clean(target), "/")[1:], pending...)
		current = "/"
	}
	return filepath.Join(root, current), nil
}

func (h LocalHost) ReadFile(p string) ([]byte, error) { return os.ReadFile(h.path(p)) }

func (h LocalHost) Stat(p string) (fs.FileMode, bool, error) {
	info, err := os.Stat(h.path(p))
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return 0, false, nil
	case err != nil:
		return 0, false, err
	}
	return info.Mode(), true, nil
}

func (h LocalHost) WriteFile(p string, data []byte, mode fs.FileMode) error {
	full := h.entry(p)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return err
	}
	tmp := full + ".tuist-new"
	if err := os.WriteFile(tmp, data, mode); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, full)
}

func (h LocalHost) RemoveAll(p string) error { return os.RemoveAll(h.entry(p)) }

func (h LocalHost) Run(ctx context.Context, stdin []byte, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if h.Root != "" {
		cmd = exec.CommandContext(ctx, "/usr/bin/nsenter", append([]string{"-t", "1", "-m", "-u", "-i", "-n", "-p", "--", name}, args...)...)
		cmd.SysProcAttr = &syscall.SysProcAttr{Chroot: h.Root}
		cmd.Dir = "/"
	}
	cmd.Env = []string{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL=C"}
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return stdout.Bytes(), &ExitError{Command: strings.Join(append([]string{name}, args...), " "), Code: exitErr.ExitCode(), Stderr: stderr.String()}
	}
	return stdout.Bytes(), err
}

// Lock holds the host's apply lock until the returned func runs, so the
// operator's apply over SSH and the node agent's never overlap.
func (h LocalHost) Lock() (func(), error) {
	path := h.path("/run/tuist-rack-node.lock")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}
