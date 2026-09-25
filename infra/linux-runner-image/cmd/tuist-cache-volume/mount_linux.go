//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

type mountMessage struct {
	Source string `json:"source"`
	Mirror string `json:"mirror,omitempty"`
}

// The broker lives in the already privileged DinD sidecar inside the job's
// Kata VM. Passing descriptors avoids PID namespace assumptions and path races;
// neither the runner nor an ordinary Docker job container needs mount privileges.
func bindDirectory(socket, source, target string) error {
	ns, err := os.Open("/proc/self/ns/mnt")
	if err != nil {
		return err
	}
	defer ns.Close()
	fd, err := unix.Open(target, unix.O_PATH|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer unix.Close(fd)
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		return fmt.Errorf("cache mount helper unavailable (runner image/controller upgrade required): %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))
	// dockerd resolves `docker run -v` paths in the broker's namespace. Targets in
	// the shared work directory are mirrored there so child containers see them.
	message := mountMessage{Source: source}
	if resolved, err := filepath.EvalSymlinks(target); err == nil {
		if rel, err := filepath.Rel(filepath.Dir(socket), resolved); err == nil && filepath.IsLocal(rel) {
			message.Mirror = rel
		}
	}
	data, _ := json.Marshal(message)
	if _, _, err = conn.WriteMsgUnix(data, unix.UnixRights(int(ns.Fd()), fd), nil); err != nil {
		return err
	}
	response := make([]byte, 4096)
	n, err := conn.Read(response)
	if err != nil {
		return err
	}
	reply := string(response[:n])
	if warning, ok := strings.CutPrefix(reply, "ok: "); ok {
		fmt.Fprintf(os.Stderr, "::warning::Cache volume attached, but Docker containers started later will not see %s: %s\n", target, warning)
		return nil
	}
	if reply != "ok" {
		return fmt.Errorf("cache bind mount failed: %s", reply)
	}
	return nil
}

func serveMounts(socket, root string) error {
	if os.Geteuid() != 0 {
		return errors.New("mount helper must run as root inside the job VM")
	}
	sourceRoot, err := os.OpenRoot(root)
	if err != nil {
		return err
	}
	defer sourceRoot.Close()
	workRoot, err := os.OpenRoot(filepath.Dir(socket))
	if err != nil {
		return err
	}
	defer workRoot.Close()
	listener, err := net.ListenUnix("unixpacket", &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		return err
	}
	defer listener.Close()
	if err = os.Chmod(socket, 0666); err != nil {
		return err
	}
	slots := make(chan struct{}, 8)
	for {
		conn, err := listener.AcceptUnix()
		if err != nil {
			return err
		}
		select {
		case slots <- struct{}{}:
			go func() {
				defer func() { <-slots; conn.Close() }()
				_ = conn.SetDeadline(time.Now().Add(30 * time.Second))
				_, _ = conn.Write([]byte(mountReply(mountRequest(conn, sourceRoot, workRoot))))
			}()
		default:
			_, _ = conn.Write([]byte("mount helper busy"))
			conn.Close()
		}
	}
}

func mountReply(warning string, err error) string {
	if err != nil {
		return err.Error()
	}
	if warning != "" {
		return "ok: " + warning
	}
	return "ok"
}

// mountRequest returns a warning when the job's mount succeeded but the mirror
// for Docker children could not be created; the mirror is never required.
func mountRequest(conn *net.UnixConn, root, work *os.Root) (string, error) {
	data, control := make([]byte, 4096), make([]byte, unix.CmsgSpace(8*4))
	n, oobn, flags, _, err := conn.ReadMsgUnix(data, control)
	if err != nil {
		return "", err
	}
	messages, err := unix.ParseSocketControlMessage(control[:oobn])
	if err != nil {
		return "", err
	}
	var fds []int
	defer func() {
		for _, fd := range fds {
			unix.Close(fd)
		}
	}()
	for _, message := range messages {
		rights, err := unix.ParseUnixRights(&message)
		if err != nil {
			return "", err
		}
		for _, fd := range rights {
			unix.CloseOnExec(fd)
		}
		fds = append(fds, rights...)
	}
	if flags&(unix.MSG_TRUNC|unix.MSG_CTRUNC) != 0 || len(fds) != 2 {
		return "", errors.New("expected mount namespace and target directory descriptors")
	}
	var request mountMessage
	if err = json.Unmarshal(data[:n], &request); err != nil {
		return "", errors.New("invalid mount request")
	}
	source := request.Source
	parts := strings.Split(source, "/")
	if len(parts) != 2 || !directoryPattern.MatchString(parts[0]) || (parts[1] != "data" && !directoryPattern.MatchString(parts[1])) {
		return "", errors.New("invalid volume source")
	}
	// os.Root bounds all resolution to this pod's UID-scoped cache subtree.
	directory, err := root.OpenFile(source, os.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW, 0)
	if err != nil {
		return "", err
	}
	defer directory.Close()
	kind, err := unix.IoctlRetInt(fds[0], unix.NS_GET_NSTYPE)
	if err != nil || kind != unix.CLONE_NEWNS {
		return "", errors.New("invalid mount namespace descriptor")
	}
	// The files supplied to ExtraFiles must stay open until the worker exits.
	// Duplicate them so ownership remains with the request's descriptor cleanup.
	nsFD, err := unix.FcntlInt(uintptr(fds[0]), unix.F_DUPFD_CLOEXEC, 0)
	if err != nil {
		return "", err
	}
	ns := os.NewFile(uintptr(nsFD), "namespace")
	defer ns.Close()
	targetFD, err := unix.FcntlInt(uintptr(fds[1]), unix.F_DUPFD_CLOEXEC, 0)
	if err != nil {
		return "", err
	}
	targetCopy := os.NewFile(uintptr(targetFD), "target")
	defer targetCopy.Close()
	files, args, warning := []*os.File{directory, targetCopy, ns}, []string{"mount-worker"}, ""
	if request.Mirror != "" {
		if mirror, err := mirrorTarget(work, request.Mirror, fds[1]); err != nil {
			warning = err.Error()
		} else {
			defer mirror.Close()
			files, args = append(files, mirror), append(args, "mirror")
		}
	}
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, executable, args...)
	cmd.ExtraFiles = files
	output, err := cmd.CombinedOutput()
	var exit *exec.ExitError
	if errors.As(err, &exit) && exit.ExitCode() == mirrorSkippedExit {
		return strings.TrimSpace(string(output)), nil
	}
	if err != nil {
		return "", fmt.Errorf("mount worker: %s (%w)", strings.TrimSpace(string(output)), err)
	}
	return warning, nil
}

// mirrorTarget opens the client's target as the broker sees it. os.Root keeps
// resolution inside the work directory, and the inode check proves both
// namespaces name the same directory before anything is mounted.
func mirrorTarget(work *os.Root, path string, target int) (*os.File, error) {
	if !filepath.IsLocal(path) || filepath.Clean(path) != path || strings.Split(path, "/")[0] == "_tuist_cache" {
		return nil, errors.New("invalid mirror path")
	}
	mirror, err := work.OpenFile(path, os.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	var want, got unix.Stat_t
	if err = unix.Fstat(target, &want); err == nil {
		err = unix.Fstat(int(mirror.Fd()), &got)
	}
	if err == nil && (want.Dev != got.Dev || want.Ino != got.Ino) {
		err = errors.New("mirror path is not the cache target")
	}
	if err != nil {
		mirror.Close()
		return nil, err
	}
	return mirror, nil
}

func emptyDirectory(fd int) error {
	dir, err := unix.Openat(fd, ".", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open mount target: %w", err)
	}
	target := os.NewFile(uintptr(dir), "target")
	defer target.Close()
	entries, err := target.Readdirnames(1)
	if len(entries) != 0 {
		return errors.New("cache target is no longer empty")
	}
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	return nil
}

func mountWorker(mirror bool) error {
	runtime.LockOSThread()
	// This subprocess exits immediately afterward: never return its switched
	// thread to Go's thread pool or switch the long-lived broker's namespace.
	if err := unix.Unshare(unix.CLONE_FS); err != nil {
		return fmt.Errorf("unshare filesystem context: %w", err)
	}
	// Clone while still in the source namespace; OpenTree cannot clone a mount
	// belonging to another namespace. The detached tree can then move across.
	// Descriptor-only APIs also work when the target's /proc cannot see us.
	tree, err := unix.OpenTree(3, "", unix.OPEN_TREE_CLONE|unix.OPEN_TREE_CLOEXEC|unix.AT_EMPTY_PATH)
	if err != nil {
		return fmt.Errorf("clone mount tree: %w", err)
	}
	defer unix.Close(tree)
	// The job's mount comes first: the mirror only exists alongside it, so a
	// failed attach never leaves a mount behind in the broker's namespace.
	mirrorTree, broker := -1, -1
	if mirror {
		if mirrorTree, err = unix.OpenTree(3, "", unix.OPEN_TREE_CLONE|unix.OPEN_TREE_CLOEXEC|unix.AT_EMPTY_PATH); err != nil {
			return fmt.Errorf("clone mount tree: %w", err)
		}
		defer unix.Close(mirrorTree)
		if broker, err = unix.Open("/proc/self/ns/mnt", unix.O_RDONLY|unix.O_CLOEXEC, 0); err != nil {
			return err
		}
		defer unix.Close(broker)
	}
	if err := unix.Setns(5, unix.CLONE_NEWNS); err != nil {
		return fmt.Errorf("enter mount namespace: %w", err)
	}
	if err := emptyDirectory(4); err != nil {
		return err
	}
	if err := unix.MoveMount(tree, "", 4, "", unix.MOVE_MOUNT_F_EMPTY_PATH|unix.MOVE_MOUNT_T_EMPTY_PATH); err != nil {
		return fmt.Errorf("attach mount tree: %w", err)
	}
	if !mirror {
		return nil
	}
	if err := unix.Setns(broker, unix.CLONE_NEWNS); err != nil {
		return fmt.Errorf("%w: %v", errMirrorSkipped, err)
	}
	if err := emptyDirectory(6); err != nil {
		return fmt.Errorf("%w: %v", errMirrorSkipped, err)
	}
	if err := unix.MoveMount(mirrorTree, "", 6, "", unix.MOVE_MOUNT_F_EMPTY_PATH|unix.MOVE_MOUNT_T_EMPTY_PATH); err != nil {
		return fmt.Errorf("%w: %v", errMirrorSkipped, err)
	}
	return nil
}
